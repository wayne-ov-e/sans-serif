import SwiftUI

/// The list names at the bottom of the page, with tasks left as a raised number.
/// Tap a name to turn to that list. Hold a name for its menu, which grows upward from it.
struct ListNames: View {
    let lists: [TaskList]
    let current: TaskList?
    let select: (TaskList) -> Void
    /// The list whose menu is open, and the menu's lines.
    var menuListID: UUID?
    var menuOptions: [MenuOption] = []
    var openMenu: ((TaskList) -> Void)?
    /// The list whose name is being rewritten in place.
    @Binding var renamingID: UUID?
    var focus: FocusState<PageView.Field?>.Binding
    let rename: (TaskList, String) -> Void
    /// A way to the archive without a drag, for VoiceOver and Switch Control.
    var openArchive: (() -> Void)?
    /// A way to settings without a drag.
    var openSettings: (() -> Void)?

    @Environment(\.pageMetrics) private var metrics
    @AppStorage(Setting.showCounts.key) private var showCounts = Setting.showCounts.defaultValue
    /// Where each name starts, so a menu can line up with the name it grows from.
    @State private var leadingEdges: [UUID: CGFloat] = [:]

    private nonisolated static let space = "names"

    var body: some View {
        HStack(alignment: .top, spacing: metrics.listNameGap) {
            ForEach(lists) { list in
                Group {
                    if renamingID == list.id {
                        NameField(list: list, renamingID: $renamingID, focus: focus, rename: rename)
                    } else {
                        name(list)
                    }
                }
                // Behind a menu, every name but the one held recedes.
                .receded(menuListID != nil && menuListID != list.id)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.space)).minX } action: {
                    leadingEdges[list.id] = $0
                }
            }
        }
        .coordinateSpace(.named(Self.space))
        // The menu stands on top of the names and grows upward from the one held.
        .overlay(alignment: .topLeading) {
            Color.clear
                .frame(width: 0, height: 0)
                .overlay(alignment: .bottomLeading) {
                    if let menuListID {
                        TextMenu(options: menuOptions)
                            .padding(.bottom, 10)
                            .offset(x: leadingEdges[menuListID] ?? 0)
                    }
                }
        }
        .animation(.quick, value: current?.id)
        .animation(.quick, value: menuListID)
        .animation(.quick, value: menuOptions.map(\.id))
    }

    private func name(_ list: TaskList) -> some View {
        let isCurrent = list === current
        // The name that is held stays in ink while its menu is open.
        let inInk = menuListID == nil ? isCurrent : menuListID == list.id
        return HStack(alignment: .top, spacing: metrics.countGap) {
            Text(list.name).typeStyle(.listName)
            if showCounts {
                Text("\(list.liveCount)").typeStyle(.count)
            }
        }
        .foregroundStyle(inInk ? .ink : .inkFaded)
        .frame(minHeight: metrics.minTouchHeight)
        // The gap on either side of a name belongs to it, so short names are easy to hit.
        .contentShape(Rectangle().inset(by: -metrics.listNameGap / 2))
        .onTapGesture { select(list) }
        .onLongPressGesture(minimumDuration: Lift.holdDuration) { openMenu?(list) }
        .onSecondaryClick { openMenu?(list) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(list.name)
        .accessibilityValue(showCounts ? "\(list.liveCount) left" : "")
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { select(list) }
        .accessibilityAction(named: "Show archive") {
            select(list)
            openArchive?()
        }
        .accessibilityAction(named: "Show settings") { openSettings?() }
        .accessibilityAction(named: "Show menu") { openMenu?(list) }
    }
}

/// A list name being rewritten where it stands.
private struct NameField: View {
    let list: TaskList
    @Binding var renamingID: UUID?
    var focus: FocusState<PageView.Field?>.Binding
    let rename: (TaskList, String) -> Void

    @Environment(\.pageMetrics) private var metrics
    @State private var text = ""

    private var field: PageView.Field { .listName(list.id) }

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .typeStyle(.listName)
            .foregroundStyle(.ink)
            .tint(.ink)
            #if os(iOS)
            .textInputAutocapitalization(.never)
            .submitLabel(.done)
            #endif
            .fixedSize()
            .frame(minWidth: 24, minHeight: metrics.minTouchHeight, alignment: .leading)
            .focused(focus, equals: field)
            .onAppear {
                text = list.name
                focus.wrappedValue = field
            }
            .onSubmit { focus.wrappedValue = nil }
            .onChange(of: focus.wrappedValue) { old, new in
                // Whatever ends the writing, the name is kept. A blank name changes nothing.
                guard old == field, new != field else { return }
                rename(list, text)
                renamingID = nil
            }
            .accessibilityLabel("List name")
    }
}
