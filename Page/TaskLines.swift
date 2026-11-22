import SwiftData
import SwiftUI

/// The tasks of a page, top to bottom, and the empty line below them.
/// Hold a task to pick it up, then drag it to a new place.
struct TaskLines: View {
    let tasks: [TaskItem]
    var focus: FocusState<PageView.Field?>.Binding
    @Binding var editingID: UUID?
    let actions: StrikeActions
    /// True while a task is being carried.
    @Binding var isLifting: Bool
    @Binding var draft: String
    /// Where the cursor is on the empty line.
    var draftSelection: Binding<TextSelection?> = .constant(nil)
    let submitDraft: () -> Void
    /// The task whose menu is open, and the menu's lines. It grows downward from the task.
    var menuTaskID: UUID?
    var menuOptions: [MenuOption] = []
    /// A task was held and let go without being moved.
    var openMenu: ((TaskItem) -> Void)?
    /// The held line began to move: the menu makes way for the carrying.
    var closeMenu: (() -> Void)?
    var pendingStrikeID: Binding<UUID?> = .constant(nil)
    /// The tasks picked out to be deleted together. Nothing while none are being picked.
    var picked: Set<UUID>?
    var pick: ((TaskItem) -> Void)?
    /// The empty line grew or shrank by a row as it was written on.
    var draftRows: ((CGFloat) -> Void)?
    /// The page has nothing on it and nothing is being written: it says so.
    var showsEmptyWords = false

    @Environment(\.modelContext) private var context
    @Environment(\.pageMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counted for the haptic of a line put down in a new place.
    /// Counts the places a carried line has passed.
    @State private var slots = 0
    @State private var drops = 0

    /// Where each task sits when nothing is being carried.
    @State private var frames: [UUID: CGRect] = [:]
    @State private var carried: Carried?

    /// A task picked up off the page.
    private struct Carried: Equatable {
        let id: UUID
        /// Its place when it was picked up.
        let from: Int
        /// The place it would take if dropped now.
        var to: Int
        /// How far it has been moved.
        var offset: CGFloat
        /// Dropped, and settling into its place.
        var isSettling = false
        /// It has been moved since it was picked up. Held still, it opens the menu instead.
        var didMove = false
    }

    private nonisolated static let space = "lines"

    /// Whether the cursor on the empty line can be put where the app wants
    /// it. On iOS 18 it cannot: a field told where its cursor is stops the app
    /// as soon as the text is shortened under it, which the page does every
    /// time Return ends a task. Every tester on iOS 18.0 would have been
    /// stopped at their first task. There the cursor is left to the system.
    private static var cursorCanBePlaced: Bool {
        if #available(iOS 26, macOS 26, *) { true } else { false }
    }
    /// How long a picked-up line is held still before its menu opens.
    private static let menuHold: Duration = .seconds(0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.taskGap) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                let isCarried = carried?.id == task.id
                TaskLine(
                    task: task, focus: focus, editingID: $editingID, actions: actions,
                    canStrike: carried == nil && picked == nil, showMenu: { openMenu?(task) },
                    menu: menuTaskID == task.id ? menuOptions : nil,
                    pendingStrikeID: pendingStrikeID,
                    isPicked: picked.map { $0.contains(task.id) },
                    pick: { pick?(task) }
                )
                    // While tasks are picked out, the ones picked stand in full
                    // ink and the rest step back.
                    .opacity(picked.map { $0.contains(task.id) ? 1 : 0.38 } ?? 1)
                    .animation(.quick, value: picked)
                    // Behind a menu, every line but the one held recedes and cannot be touched.
                    .receded(menuTaskID != nil && menuTaskID != task.id)
                    .fadesUnderListNames()
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: {
                        // Measured frames follow a line as it is moved aside, so
                        // they are only trusted while every line is at rest.
                        if carried == nil { frames[task.id] = $0 }
                    }
                    .scaleEffect(isCarried && carried?.isSettling == false ? 1.03 : 1, anchor: .leading)
                    .offset(y: offset(of: task, at: index))
                    // The carried line, and the line with a menu, lie over the others.
                    .zIndex(isCarried || menuTaskID == task.id ? 1 : 0)
                    // The other lines step aside. The carried one follows the finger.
                    // Not over a line that is being edited: an animation laid over a
                    // text field keeps it from ever coming to rest.
                    .animation(isCarried || editingID == task.id ? nil : .shuffle, value: carried?.to)
                    .animation(editingID == task.id ? nil : .settle, value: isCarried)
                    .onLiftDrag(isEnabled: task.isLive && editingID != task.id && picked == nil) {
                        pickUp(task, at: index)
                    } onChanged: { translation in
                        carry(by: translation.height)
                    } onEnded: {
                        drop()
                    }
                    // A right click opens the menu a long press does.
                    .onSecondaryClick { if task.isLive, carried == nil, menuTaskID == nil, picked == nil { openMenu?(task) } }
                    .transition(.opacity)
            }

            // The empty paper below the last task. With nothing typed and no
            // cursor in it, it is a blank line.
            LineField(text: $draft, selection: Self.cursorCanBePlaced ? draftSelection : .constant(nil), onReturn: submitDraft)
                .focused(focus, equals: .newTask)
                .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded() } action: { draftRows?($0) }
                .accessibilityLabel("New task")
                // A list with nothing on it says so, where the first task
                // will be written, until the pen is put there (Wayne, Nov 21,
                // 2026: "when list is empty show something").
                .overlay(alignment: .topLeading) {
                    // Simply there or not: faded out, the app was at times
                    // never at rest again after the first tap on an empty
                    // page, and a UI walk waited minutes at every key.
                    EmptyPageWords().opacity(showsEmptyWords ? 1 : 0)
                }
                .receded(menuTaskID != nil)
                .disabled(picked != nil)
                .fadesUnderListNames()
        }
        .coordinateSpace(.named(Self.space))
        // The page changed under a carried line, from another device or a
        // widget: its places no longer mean what they did. It is put back.
        .onChange(of: tasks.map(\.id)) { _, _ in
            guard carried != nil else { return }
            carried = nil
            isLifting = false
        }
        .animation(.quick, value: menuTaskID)
        .animation(.quick, value: menuOptions.map(\.id))
        // Room to tap below the last line when the page is full.
        .padding(.bottom, metrics.taskGap)
        // Picked up, each place it passes, and put down.
        .haptic(.pickUp, trigger: carried?.id) { $0 != nil }
        .haptic(.selection, trigger: slots)
        .haptic(.putDown, trigger: drops)
    }

    // MARK: Reordering

    private func offset(of task: TaskItem, at index: Int) -> CGFloat {
        guard let carried else { return 0 }
        return offset(of: task, at: index, while: carried)
    }

    private func offset(of task: TaskItem, at index: Int, while carried: Carried) -> CGFloat {
        if task.id == carried.id { return carried.offset }
        // Lines between the old place and the new one move over by the height of the carried line.
        let step = (frames[carried.id]?.height ?? 0) + metrics.taskGap
        if carried.to > carried.from, index > carried.from, index <= carried.to { return -step }
        if carried.to < carried.from, index >= carried.to, index < carried.from { return step }
        return 0
    }

    private func pickUp(_ task: TaskItem, at index: Int) {
        guard carried == nil else { return }
        carried = Carried(id: task.id, from: index, to: index, offset: 0)
        isLifting = true
        // Held still a little longer, its menu opens under the finger. The line
        // is still held: the same finger can go on to carry it, and the menu
        // makes way. The hold never has to choose between the two.
        let id = task.id
        Task { @MainActor in
            try? await Task.sleep(for: Self.menuHold)
            guard let held = carried, held.id == id, !held.didMove, !held.isSettling else { return }
            openMenu?(task)
        }
    }

    /// How far a held line must be moved before it counts as being carried.
    /// More than a resting finger wanders.
    private static let carryDistance: CGFloat = 10

    private func carry(by distance: CGFloat) {
        guard var moving = carried, !moving.isSettling, let frame = frames[moving.id] else { return }
        if !moving.didMove {
            // Until it is clearly being carried, the line stays where it is.
            guard abs(distance) > Self.carryDistance else { return }
            moving.didMove = true
            // Asked every time: during a gesture this view's own idea of
            // whether a menu is open can be a moment old.
            closeMenu?()
        }
        moving.offset = distance
        // Its new place is below every line whose middle it has passed.
        let middle = frame.midY + distance
        let before = moving.to
        moving.to = tasks.count { other in
            other.id != moving.id && (frames[other.id]?.midY ?? .infinity) < middle
        }
        // Each place it passes is felt. Not the picking up, which has its own.
        if moving.to != before { slots += 1 }
        carried = moving
    }

    private func drop() {
        guard let moving = carried, !moving.isSettling else { return }
        guard moving.didMove else {
            // Let go without moving: the line is put back, and its menu stays.
            // If it had not opened by itself yet, it opens now.
            carried = nil
            isLifting = false
            if menuTaskID != moving.id, let task = tasks.first(where: { $0.id == moving.id }) { openMenu?(task) }
            return
        }
        let settled = restingOffset(of: moving)
        guard !reduceMotion, settled != moving.offset else {
            finishDrop(moving)
            return
        }
        withAnimation(.shuffle) {
            carried?.offset = settled
            carried?.isSettling = true
        } completion: {
            finishDrop(moving)
        }
    }

    /// How far the carried line sits from where it started once it is in its new place.
    private func restingOffset(of moving: Carried) -> CGFloat {
        // The places were counted when the line was picked up. Should the page
        // have changed since, nothing is read past its end.
        guard moving.from < tasks.count, moving.to < tasks.count, moving.from >= 0, moving.to >= 0 else { return 0 }
        let passed = moving.to > moving.from
            ? tasks[(moving.from + 1)...moving.to]
            : tasks[moving.to..<moving.from]
        let distance = passed.reduce(0) { $0 + (frames[$1.id]?.height ?? 0) + metrics.taskGap }
        return moving.to > moving.from ? distance : -distance
    }

    /// Stores the new order and lets go, in one step so nothing jumps.
    private func finishDrop(_ moving: Carried) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        // Every line now rests where it was moved to.
        var settled = moving
        settled.offset = restingOffset(of: moving)
        for (index, task) in tasks.enumerated() {
            let shift = offset(of: task, at: index, while: settled)
            if shift != 0, let frame = frames[task.id] {
                frames[task.id] = frame.offsetBy(dx: 0, dy: shift)
            }
        }
        withTransaction(transaction) {
            // Only if the line carried is still where it was picked up from.
            if moving.to != moving.from, tasks.indices.contains(moving.from), tasks[moving.from].id == moving.id {
                drops += 1
                var others = tasks
                let task = others.remove(at: moving.from)
                let place = min(moving.to, others.count)
                context.place(
                    task,
                    below: place > 0 ? others[place - 1] : nil,
                    above: place < others.count ? others[place] : nil
                )
            }
            carried = nil
        }
        isLifting = false
    }
}

/// What an empty list's page says, in faded ink where its first task will go.
struct EmptyPageWords: View {
    static let words = PageSnapshot.emptyWords

    var body: some View {
        Text(Self.words)
            .typeStyle(.task)
            .foregroundStyle(.inkFaded)
            .frame(maxWidth: .infinity, alignment: .leading)
            .allowsHitTesting(false)
    }
}
