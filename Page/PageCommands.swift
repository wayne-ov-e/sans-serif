import SwiftUI

/// What the menu bar and the keyboard can ask of the page in the front window.
struct PageCommands {
    var lists: [(id: UUID, name: String)]
    var select: (UUID) -> Void
    var showsSettings: Bool
    var toggleSettings: () -> Void
    var showsArchive: Bool
    var toggleArchive: () -> Void
    /// Strikes the task the cursor is in. `nil` when the cursor is not in a task.
    var strikeTask: (() -> Void)?
}

extension FocusedValues {
    @Entry var pageCommands: PageCommands?
}

/// The menu bar on the Mac, and the same shortcuts with a keyboard on iPad
/// (brief: Interaction model). Cmd+1, 2, 3 turn to a list, Cmd+comma opens settings.
struct PageMenuCommands: Commands {
    @FocusedValue(\.pageCommands) private var page

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { page?.toggleSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(page == nil)
        }
        CommandMenu("List") {
            ForEach(Array((page?.lists ?? []).prefix(9).enumerated()), id: \.element.id) { index, list in
                Button(list.name) { page?.select(list.id) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
            Divider()
            Button(page?.showsArchive == true ? "Hide Archive" : "Show Archive") { page?.toggleArchive() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(page == nil)
            Divider()
            Button("Strike Task") { page?.strikeTask?() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(page?.strikeTask == nil)
        }
    }
}
