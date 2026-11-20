import SwiftUI

/// One line of a text menu.
struct MenuOption: Identifiable {
    let title: String
    /// Delete actions are in red ink.
    var isDestructive = false
    /// One of several that is not the one chosen: a day of the week not picked.
    var isFaded = false
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
    /// A row of days: sliding it is felt, a tick for each day that goes by.
    var ticks = false
    /// The word the row opens on, slid into view: the day already chosen.
    var showing: String?

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
        // Six words are wider than a phone. Set a little closer, the last of
        // them shows at the edge and says the row goes on.
        let gap = label == nil && options.count > 5 ? metrics.listNameGap * 0.75 : metrics.listNameGap
        return HStack(alignment: .firstTextBaseline, spacing: gap) {
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
                        .foregroundStyle(option.isDestructive ? .inkRed : option.isFaded ? .inkFaded : .ink)
                        .frame(minHeight: metrics.minTouchHeight)
                        // The gap on either side of a word belongs to it.
                        .contentShape(Rectangle().inset(by: -gap / 2))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(ticks && !option.isFaded ? .isSelected : [])
                .id(option.id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Where a new row of words begins, for one that was slid along.
        .background(alignment: .leading) { Color.clear.frame(width: 1, height: 1).id(RowThatScrolls.start) }
        .transition(.opacity)
        // On a narrow page a long row slides sideways. One that fits does not move.
        .modifier(RowThatScrolls(ticks: ticks, showing: showing, label: label))
    }
}

private struct RowThatScrolls: ViewModifier {
    var ticks = false
    var showing: String?
    var label: String?

    static let start = "row start"

    /// About one short word and the gap after it.
    private static let tick: CGFloat = 44

    func body(content: Content) -> some View {
        ScrollViewReader { reader in
            ScrollView(.horizontal) { content }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .scrollClipDisabled()
                // Each day that slides by is felt (Wayne, Nov 20, 2026).
                .onScrollGeometryChange(for: Int.self) { geometry in
                    Int((geometry.contentOffset.x / Self.tick).rounded(.down))
                } action: { old, new in
                    if ticks, old != new, opened { Tap.step() }
                }
                .onChange(of: label, initial: true) {
                    // A new row of words: it opens on the one chosen, and
                    // getting there is not the hand's doing, so it is not felt.
                    opened = false
                    Task { @MainActor in
                        // Once the new words have their places, and once more
                        // when the row has finished changing: asked only the
                        // first time, a slow phone left the row short of the
                        // day chosen (found by the walk, Nov 20, 2026).
                        for wait in [40, 220] {
                            try? await Task.sleep(for: .milliseconds(wait))
                            if let showing {
                                reader.scrollTo(showing, anchor: .center)
                            } else {
                                reader.scrollTo(Self.start, anchor: .leading)
                            }
                        }
                        try? await Task.sleep(for: .milliseconds(250))
                        opened = true
                    }
                }
        }
    }

    @State private var opened = false
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
