import SwiftUI

/// One line of a text menu.
struct MenuOption: Identifiable {
    let title: String
    /// Delete actions are in red ink.
    var isDestructive = false
    let action: () -> Void

    var id: String { title }
}

/// A menu as plain lines of text, growing from the item that was held.
/// The rest of the page is blurred behind it; a tap there puts it away.
struct TextMenu: View {
    let options: [MenuOption]

    /// Between the lines of a menu.
    static let gap: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            ForEach(options) { option in
                Button(action: option.action) {
                    Text(option.title)
                        .typeStyle(.action)
                        .foregroundStyle(option.isDestructive ? .inkRed : .ink)
                        // Each line's target reaches half way to its neighbours.
                        .contentShape(Rectangle().inset(by: -Self.gap / 2))
                }
                .buttonStyle(.plain)
            }
        }
        .fixedSize()
        .transition(.opacity)
    }
}

/// A held task's menu, as words in a row at the bottom of the page, where the
/// list names are. It is always in the same place, under the thumb, and never
/// covers a task. `label` says what the row is for when its words are list names.
struct MenuRow: View {
    let options: [MenuOption]
    var label: String?
    /// A line above the row: on a shared list, who wrote the task.
    var note: String?

    @Environment(\.pageMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let note {
                Text(note)
                    .typeStyle(.monthLabel)
                    .foregroundStyle(.inkFaded)
            }
            row
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.listNameGap) {
            if let label {
                Text(label)
                    .typeStyle(.monthLabel)
                    .foregroundStyle(.inkFaded)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(options) { option in
                Button(action: option.action) {
                    Text(option.title)
                        .typeStyle(.action)
                        .foregroundStyle(option.isDestructive ? .inkRed : .ink)
                        .frame(minHeight: metrics.minTouchHeight)
                        // The gap on either side of a word belongs to it.
                        .contentShape(Rectangle().inset(by: -metrics.listNameGap / 2))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
        // On a narrow page a long row slides sideways. One that fits does not move.
        .modifier(RowThatScrolls())
    }
}

private struct RowThatScrolls: ViewModifier {
    func body(content: Content) -> some View {
        ScrollView(.horizontal) { content }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .scrollClipDisabled()
    }
}

/// What a menu is open on.
enum PageMenu: Equatable {
    /// A task's menu, or its list of places to move to.
    case task(UUID, moving: Bool)
    /// A list's menu, or the question before it is deleted.
    case list(UUID, confirmingDelete: Bool)

    var taskID: UUID? {
        if case .task(let id, _) = self { id } else { nil }
    }

    var listID: UUID? {
        if case .list(let id, _) = self { id } else { nil }
    }
}
