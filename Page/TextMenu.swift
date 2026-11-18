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
                        .typeStyle(.listName)
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
