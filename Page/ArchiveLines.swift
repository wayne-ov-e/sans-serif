import SwiftData
import SwiftUI

/// What is done: what was struck today under a heading of its own, then a
/// list's older struck tasks, grouped by month, newest first. An empty
/// archive says "Nothing so far.". The current month is open. Past months fold into one line each; tap a month
/// to open or fold it. Drag back across a task, right to left, to restore it.
struct ArchiveLines: View {
    let list: TaskList
    var focus: FocusState<PageView.Field?>.Binding
    /// The struck task that is held, with its menu at the bottom of the page.
    var menuTaskID: UUID?
    /// A hold on a struck task opens its menu: put it back, copy it, delete it.
    var openMenu: (TaskItem) -> Void = { _ in }
    var closeMenu: () -> Void = {}

    @Environment(\.modelContext) private var context
    @Environment(\.pageMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Months whose fold has been changed by hand, and to what.
    @State private var opened: [Date: Bool] = [:]

    var body: some View {
        let today = list.doneToday()
        let months = list.archive(before: .now)
        VStack(alignment: .leading, spacing: 0) {
            if today.isEmpty, months.isEmpty {
                // An empty archive says so, in the voice of a heading.
                Text("Nothing so far.")
                    .typeStyle(.monthLabel)
                    .foregroundStyle(.inkFaded)
            }
            if !today.isEmpty {
                // Today has a heading of its own, above the months, and is always open.
                VStack(alignment: .leading, spacing: metrics.archiveTaskGap) {
                    Text("Done today")
                        .typeStyle(.monthLabel)
                        .foregroundStyle(.inkFaded)
                        .accessibilityAddTraits(.isHeader)
                        .fadesUnderListNames()
                    ForEach(today) { task in line(task) }
                }
                .padding(.bottom, months.isEmpty ? 0 : metrics.monthGap)
            }
            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                let isOpen = isOpen(month)
                VStack(alignment: .leading, spacing: metrics.archiveTaskGap) {
                    label(month, isOpen: isOpen)
                    if isOpen {
                        ForEach(month.tasks) { task in line(task) }
                    }
                }
                .padding(.top, gap(above: index, in: months))
            }
        }
        .padding(.bottom, metrics.taskGap)
        // A tap anywhere but on the menu puts it away.
        .contentShape(Rectangle())
        .onTapGesture { if menuTaskID != nil { closeMenu() } }
        // The menu opening is felt, as it is on the page.
        .haptic(.pen, trigger: menuTaskID) { $0 != nil }
        .animation(.quick, value: menuTaskID)
    }

    private func line(_ task: TaskItem) -> some View {
        TaskLine(
            task: task,
            focus: focus,
            editingID: .constant(nil),
            actions: StrikeActions(
                strike: { _, _ in }, pauseHold: { _ in }, resumeHold: { _ in }, restore: restore
            ),
            strikeColor: .inkFaded,
            showMenu: { openMenu(task) },
            // Held, it is not dragged back to the page meanwhile.
            menu: menuTaskID == task.id ? [] : nil
        )
        // Behind a menu, every line but the one held recedes, as on the page.
        .receded(menuTaskID != nil && menuTaskID != task.id)
        .fadesUnderListNames()
        .onLongPressGesture(minimumDuration: Lift.holdDuration) { if menuTaskID == nil { openMenu(task) } }
        .onSecondaryClick { if menuTaskID == nil { openMenu(task) } }
        .transition(.opacity)
    }

    private func label(_ month: ArchiveMonth, isOpen: Bool) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .shuffle) {
                opened[month.month] = !isOpen
            }
        } label: {
            Text(month.month.formatted(.dateTime.month(.wide).year()))
                .typeStyle(.monthLabel)
                .foregroundStyle(.inkFaded)
                // A 44 pt target around a 20 pt line.
                .contentShape(Rectangle().inset(by: -12))
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOpen ? "Open" : "Folded")
        .accessibilityAddTraits(.isHeader)
        .receded(menuTaskID != nil)
        .fadesUnderListNames()
    }

    private func isOpen(_ month: ArchiveMonth) -> Bool {
        opened[month.month] ?? Calendar.current.isDate(month.month, equalTo: .now, toGranularity: .month)
    }

    /// Folded months sit close together. An open month has more room around it.
    private func gap(above index: Int, in months: [ArchiveMonth]) -> CGFloat {
        guard index > 0 else { return 0 }
        return isOpen(months[index]) || isOpen(months[index - 1]) ? metrics.monthGap : metrics.foldedMonthGap
    }

    /// The line lifts first, then the task goes back to its place on the page.
    private func restore(_ task: TaskItem) {
        let lifting = Duration.seconds(TaskLine.secondsPerLine * Double(TaskLine.lineLimit))
        Task { @MainActor in
            if !reduceMotion { try? await Task.sleep(for: lifting) }
            guard task.modelContext != nil else { return }
            withAnimation(reduceMotion ? nil : .shuffle) {
                context.restore(task)
            }
        }
    }
}
