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

    @Environment(\.modelContext) private var context
    @Environment(\.pageMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counted for the haptic of a line put down in a new place.
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
    /// How long a picked-up line is held still before its menu opens.
    private static let menuHold: Duration = .seconds(0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.taskGap) {
            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                let isCarried = carried?.id == task.id
                TaskLine(
                    task: task, focus: focus, editingID: $editingID, actions: actions,
                    canStrike: carried == nil, showMenu: { openMenu?(task) },
                    menu: menuTaskID == task.id ? menuOptions : nil,
                    pendingStrikeID: pendingStrikeID
                )
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
                    .animation(isCarried ? nil : .shuffle, value: carried?.to)
                    .animation(.settle, value: isCarried)
                    .onLiftDrag(isEnabled: task.isLive && editingID != task.id) {
                        pickUp(task, at: index)
                    } onChanged: { translation in
                        carry(by: translation.height)
                    } onEnded: {
                        drop()
                    }
                    // A right click opens the menu a long press does.
                    .onSecondaryClick { if task.isLive, carried == nil, menuTaskID == nil { openMenu?(task) } }
                    .transition(.opacity)
            }

            // The empty paper below the last task. With nothing typed and no
            // cursor in it, it is a blank line.
            LineField(text: $draft, selection: draftSelection, onReturn: submitDraft)
                .focused(focus, equals: .newTask)
                .accessibilityLabel("New task")
                .receded(menuTaskID != nil)
                .fadesUnderListNames()
        }
        .coordinateSpace(.named(Self.space))
        .animation(.quick, value: menuTaskID)
        .animation(.quick, value: menuOptions.map(\.id))
        .haptic(.pen, trigger: menuTaskID) { $0 != nil }
        // Room to tap below the last line when the page is full.
        .padding(.bottom, metrics.taskGap)
        // Picked up, each place it passes, and put down.
        .haptic(.pickUp, trigger: carried?.id) { $0 != nil }
        .haptic(.selection, trigger: carried?.to) { $0 != nil }
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
        moving.to = tasks.count { other in
            other.id != moving.id && (frames[other.id]?.midY ?? .infinity) < middle
        }
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
            if moving.to != moving.from, tasks.indices.contains(moving.from) {
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
