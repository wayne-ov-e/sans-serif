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
    /// A new list is being named, after the last name.
    var isNamingList: Binding<Bool> = .constant(false)
    var addList: ((String) -> Void)?
    /// A way to the archive without a drag, for VoiceOver and Switch Control.
    var openArchive: (() -> Void)?
    /// A way to settings without a drag.
    var openSettings: (() -> Void)?

    @Environment(\.pageMetrics) private var metrics
    @AppStorage(Setting.showCounts.key) private var showCounts = Setting.showCounts.defaultValue
    /// Where each name starts, so a menu can line up with the name it grows from.
    @State private var leadingEdges: [UUID: CGFloat] = [:]
    /// How wide the row of names may be before it slides.
    @State private var rowWidth: CGFloat = 0

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
                .id(list.id)
            }
            if isNamingList.wrappedValue {
                NewNameField(isNaming: isNamingList, focus: focus) { addList?($0) }
                    .id(Self.newName)
                    .transition(.opacity)
            } else if addList != nil {
                // The empty paper beside the names. A hold here starts a new
                // list where the next name would stand.
                Color.clear
                    // As tall as a name and no taller: left to itself it would take the whole page.
                    .frame(minWidth: metrics.minTouchHeight, maxWidth: .infinity)
                    .frame(height: metrics.minTouchHeight)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: Lift.holdDuration + 0.15) {
                        if menuListID == nil, renamingID == nil { isNamingList.wrappedValue = true }
                    }
                    .accessibilityHidden(true)
            }
        }
        // The row is at least as wide as the page, so the empty paper reaches its far edge.
        .frame(minWidth: rowWidth, alignment: .leading)
        .animation(.quick, value: isNamingList.wrappedValue)
        .modifier(NamesThatScroll(showing: isNamingList.wrappedValue ? AnyHashable(Self.newName) : AnyHashable(current?.id)))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .coordinateSpace(.named(Self.space))
        // The menu stands on top of the names and grows upward from the one held.
        // It is outside the sliding row, which would keep taps above it from landing.
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

    private static let newName = "new list"

    private func name(_ list: TaskList) -> some View {
        let isCurrent = list === current
        // The name that is held stays in ink while its menu is open.
        let inInk = menuListID == nil ? isCurrent : menuListID == list.id
        return HStack(alignment: .top, spacing: metrics.countGap) {
            Text(list.name).typeStyle(.listName)
            // A small raised plus: this list is shared with other people.
            if list.isShared {
                Text("+").typeStyle(.count)
            }
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
        .accessibilityValue([list.isShared ? "Shared" : nil, showCounts ? "\(list.liveCount) left" : nil]
            .compactMap { $0 }.joined(separator: ", "))
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

/// With more names than the page is wide, the row slides sideways, and keeps
/// the current name in view. A row that fits does not move. Menus still grow
/// out of it, above the names.
private struct NamesThatScroll: ViewModifier {
    let showing: AnyHashable

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                content
            }
            .scrollIndicators(.hidden)
            // A finger does not slide the row: along the bottom of the page a
            // sideways flick turns to the next list, and the two fought over
            // it (Wayne, Nov 19, 2026). The row moves by itself to keep the
            // open list's name in view, so every name is still reached by
            // turning to it.
            .scrollDisabled(true)
            // The gap around a name belongs to it, above and below the row too.
            .scrollClipDisabled()
            .onChange(of: showing, initial: true) { _, new in
                withAnimation(.quick) { proxy.scrollTo(new, anchor: .trailing) }
            }
        }
    }
}

/// The name of a new list, written after the last name. Left blank, no list is added.
private struct NewNameField: View {
    @Binding var isNaming: Bool
    var focus: FocusState<PageView.Field?>.Binding
    let add: (String) -> Void

    @Environment(\.pageMetrics) private var metrics
    @State private var text = ""

    var body: some View {
        TextField("", text: $text, prompt: Text("new list").foregroundStyle(.inkFaded))
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
            .focused(focus, equals: .newList)
            .onAppear { focus.wrappedValue = .newList }
            .onSubmit { focus.wrappedValue = nil }
            .onChange(of: focus.wrappedValue) { old, new in
                guard old == .newList, new != .newList else { return }
                let name = text
                isNaming = false
                add(name)
            }
            .accessibilityLabel("New list name")
    }
}
