import Foundation
import SwiftData
import WidgetKit

extension ModelContext {
    /// A struck task stays in the widgets for this long, struck, then leaves.
    static let widgetLinger: TimeInterval = 2.5

    /// The page as the widgets and the Live Activity show it.
    func pageSnapshot(current: UUID?, at now: Date = .now) throws -> PageSnapshot {
        PageSnapshot(
            lists: try lists().map { list in
                let tasks = (list.tasks ?? []).sorted { $0.order < $1.order }
                let shown = tasks.filter { task in
                    guard let struck = task.struckDate else { return true }
                    return now.timeIntervalSince(struck) < Self.widgetLinger
                }
                return PageSnapshot.List(
                    id: list.id,
                    name: list.name,
                    lines: shown.prefix(PageSnapshot.linesPerList).map {
                        PageSnapshot.Line(id: $0.id, text: $0.text, struck: $0.struckDate)
                    },
                    left: tasks.count(where: \.isLive)
                )
            },
            current: current
        )
    }

    /// Takes strikes made in a widget or the Live Activity into the store.
    /// The last word on a task wins: struck then undone leaves it live.
    func apply(_ changes: [PendingChange]) throws {
        guard !changes.isEmpty else { return }
        let tasks = try fetch(FetchDescriptor<TaskItem>())
        for change in changes {
            guard let task = tasks.first(where: { $0.id == change.task }) else { continue }
            if change.struck {
                strike(task, at: change.date)
            } else if !task.isLive {
                restore(task)
            }
        }
    }
}

/// Keeps what is outside the app in step with the page: the widgets, and the
/// Live Activity of the working hours.
@MainActor
final class PageMirror {
    static let shared = PageMirror()

    private var context: ModelContext?
    private var page = SharedPage.shared
    private var observer: (any NSObjectProtocol)?
    /// The list open in the app. The Live Activity shows this one.
    var current: UUID? {
        didSet { if current != oldValue { refresh() } }
    }

    func start(context: ModelContext, page: SharedPage = .shared) {
        self.context = context
        self.page = page
        OutsideChanges.handler = { [weak self] in await self?.outsideChange() }
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in PageMirror.shared.refresh() }
        }
        refresh()
    }

    /// Something was struck outside the app while the app is running. The
    /// line shows struck for a moment, then leaves.
    private func outsideChange() async {
        refresh()
        try? await Task.sleep(for: .seconds(ModelContext.widgetLinger + 0.1))
        refresh()
    }

    func refresh() {
        guard let context else { return }
        try? context.apply(page.takePending())
        guard let snapshot = try? context.pageSnapshot(current: current) else { return }
        if snapshot != page.snapshot {
            page.snapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        }
        WorkHoursActivity.sync(snapshot)
    }
}
