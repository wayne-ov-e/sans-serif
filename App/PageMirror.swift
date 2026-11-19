import Foundation
import SwiftData
import WidgetKit

extension ModelContext {
    /// The page as the widgets show it. Tasks struck a moment ago are still
    /// in it, struck: each widget shows them so, then lets them leave.
    func pageSnapshot(current: UUID?, at now: Date = .now) throws -> PageSnapshot {
        PageSnapshot(
            lists: try lists().map { list in
                let tasks = (list.tasks ?? []).sorted { $0.order < $1.order }
                let shown = tasks.filter { task in
                    guard let struck = task.struckDate else { return true }
                    return now.timeIntervalSince(struck) < PageSnapshot.keep
                }
                // Circled tasks come first, in the order they were circled. The rest keep page order.
                let ordered = shown.filter(\.isCircled).sorted { ($0.circledDate ?? .distantPast) < ($1.circledDate ?? .distantPast) }
                    + shown.filter { !$0.isCircled }
                // As many live lines as a widget can show, and the struck ones among them.
                var live = 0
                let lines = ordered.prefix { task in
                    if task.isLive { live += 1 }
                    return live <= PageSnapshot.linesPerList
                }
                return PageSnapshot.List(
                    id: list.id,
                    name: list.name,
                    lines: lines.map { PageSnapshot.Line(id: $0.id, text: $0.text, struck: $0.struckDate) },
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
    ///
    /// It must not wait for that moment itself. The widget is only drawn again
    /// once the tap has been dealt with, and when this waited for the line to
    /// leave, all the widget ever showed was the line already gone.
    private func outsideChange() async {
        refresh()
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(PageSnapshot.linger + 0.1))
            refresh()
        }
    }

    func refresh() {
        guard let context else { return }
        try? context.apply(page.takePending())
        guard let snapshot = try? context.pageSnapshot(current: current) else { return }
        if snapshot != page.snapshot {
            page.snapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        }
        // The Live Activity is drawn at once, so there a struck line leaves a moment after the strike.
        WorkHoursActivity.sync(snapshot.leaving(struckBefore: Date.now.addingTimeInterval(-PageSnapshot.linger)))
    }
}
