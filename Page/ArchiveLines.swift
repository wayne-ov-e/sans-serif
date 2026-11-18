import SwiftData
import SwiftUI

/// What is done: a list's struck tasks, grouped by month, newest first.
/// The current month is open. Past months fold into one line each; tap a month
/// to open or fold it. Drag back across a task, right to left, to restore it.
struct ArchiveLines: View {
    let list: TaskList
    var focus: FocusState<PageView.Field?>.Binding

    @Environment(\.modelContext) private var context
    @Environment(\.pageMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Months whose fold has been changed by hand, and to what.
    @State private var opened: [Date: Bool] = [:]

    var body: some View {
        let months = list.archive()
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                let isOpen = isOpen(month)
                VStack(alignment: .leading, spacing: metrics.archiveTaskGap) {
                    label(month, isOpen: isOpen)
                    if isOpen {
                        ForEach(month.tasks) { task in
                            TaskLine(
                                task: task,
                                focus: focus,
                                editingID: .constant(nil),
                                actions: StrikeActions(
                                    strike: { _, _ in }, pauseHold: { _ in }, resumeHold: { _ in }, restore: restore
                                ),
                                strikeColor: .inkFaded
                            )
                            .fadesUnderListNames()
                            .transition(.opacity)
                        }
                    }
                }
                .padding(.top, gap(above: index, in: months))
            }
        }
        .padding(.bottom, metrics.taskGap)
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
