import SwiftData
import SwiftUI
#if os(iOS)
import GameController
#endif

/// One list as a page of text: its tasks, the empty paper below them, and the
/// list names at the bottom.
struct PageView: View {
    let list: TaskList
    let lists: [TaskList]
    /// Turn to another list.
    let select: (TaskList) -> Void

    enum Field: Hashable {
        /// A task being edited in place.
        case task(UUID)
        /// The empty line below the last task.
        case newTask
        /// A list name being rewritten.
        case listName(UUID)
        /// Nothing is being written. With a keyboard attached the page itself
        /// listens, so that typing starts a task.
        case page
    }

    @Environment(\.modelContext) private var context
    @Environment(\.pageMetrics) private var metrics
    @FocusState private var focus: Field?
    @State private var editingID: UUID?
    @State private var draft = ""
    @State private var draftSelection: TextSelection?
    /// The task a keyboard shortcut has asked to strike.
    @State private var pendingStrikeID: UUID?
    @State private var keyboardIsUp = false
    /// A task is picked up for reordering. The page holds still meanwhile.
    @State private var isLifting = false
    /// The archive is showing instead of the page.
    @State private var showsArchive = false
    /// Settings are showing above the page.
    @State private var showsSettings = false
    /// The list being turned to, while the page turns.
    @State private var incoming: TaskList?
    /// The side it comes from: 1 for the right, -1 for the left.
    @State private var incomingSide = 0
    /// How far the page has turned, as a fraction of its width.
    @State private var turnAmount: CGFloat = 0
    /// The turn is finishing by itself. The list names already show where it is going.
    @State private var isLanding = false
    /// The page turned to is on screen, and the real one is being laid out under it.
    @State private var incomingCovers = false
    /// Counts turns, so that one cut short by the next does not finish twice.
    @State private var landings = 0
    /// The menu that is open, if any.
    @State private var menu: PageMenu?
    /// The list whose name is being rewritten.
    @State private var renamingID: UUID?
    /// Struck tasks still on the page, each with the token of its current hold.
    @State private var held: [UUID: Int] = [:]
    @State private var holds = 0
    /// A finger is dragging across a task, to strike it or to undo a strike.
    @State private var isCrossing = false
    /// Counted for haptics: a turn past the last page, a line removed or moved away, a copy.
    @State private var bumps = 0
    /// The page has been pulled far enough that letting go will turn it.
    @State private var isTurnArmed = false
    @State private var turnArms = 0
    /// Turns counted where the crisp haptic cannot be played, for one plain tap instead.
    @State private var turnTaps = 0
    @State private var removals = 0
    @State private var copies = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A struck task holds for about a second, then leaves for the archive.
    static let hold: Duration = .seconds(1)
    private static let paused = -1

    var body: some View {
        PageColumn(
            pageID: list.id,
            showsArchive: showsArchive,
            showsHeader: showsSettings,
            contentReceded: menu?.listID != nil,
            footerReceded: menu?.taskID != nil,
            scrollDisabled: isLifting,
            onTapPaper: tapPaper,
            turn: turnAmount,
            incomingSide: incoming == nil ? 0 : incomingSide,
            incomingCovers: incomingCovers,
            onTurnChanged: turnChanged,
            onTurnEnded: turnEnded,
            onPullPastEnd: pullPastEnd,
            onPullPastTop: pullPastTop
        ) {
            SettingsLines()
        } content: {
            TaskLines(
                tasks: tasksOnPage,
                focus: $focus,
                editingID: $editingID,
                actions: StrikeActions(
                    strike: strike, pauseHold: pauseHold, resumeHold: startHold, restore: restore,
                    dragBegan: crossingBegan, dragEnded: crossingEnded
                ),
                isLifting: $isLifting,
                draft: $draft,
                draftSelection: $draftSelection,
                submitDraft: submitDraft,
                menuTaskID: menu?.taskID,
                menuOptions: taskMenuOptions,
                openMenu: { menu = .task($0.id, moving: false) },
                closeMenu: { menu = nil },
                pendingStrikeID: $pendingStrikeID
            )
        } archive: {
            ArchiveLines(list: list, focus: $focus)
        } incoming: {
            if let incoming { PagePreview(list: incoming) }
        } footer: {
            if keyboardIsUp, renamingID == nil {
                // While writing, the list names make way for a way to stop.
                BottomWord(word: "done") { focus = nil }
            } else {
            ListNames(
                lists: lists,
                current: isLanding ? incoming ?? list : list,
                select: turn,
                menuListID: menu?.listID,
                menuOptions: listMenuOptions,
                openMenu: { menu = .list($0.id, confirmingDelete: false) },
                renamingID: $renamingID,
                focus: $focus,
                rename: { context.rename($0, to: $1) },
                openArchive: { showsArchive = true },
                openSettings: { showsSettings = true }
            )
            }
        }
        // Turning to a list: a swipe ticks where letting go will turn the page.
        // Then, for a swipe or a tap on a name, one short crisp haptic at the
        // instant the page sets off.
        .haptic(.selection, trigger: turnArms)
        .haptic(.turn, trigger: turnTaps)
        // The archive and settings, coming and going, are felt the same way.
        .sheetHaptics(showsArchive)
        .sheetHaptics(showsSettings)
        .haptic(.edge, trigger: bumps)
        .haptic(.putDown, trigger: removals)
        .haptic(.pen, trigger: copies)
        .haptic(.warning, trigger: isConfirmingDelete) { $0 }
        .haptic(.pen, trigger: menu?.listID) { $0 != nil }
        .onChange(of: list.id) {
            // What was held or half done belongs to the page that was left.
            held = [:]
            isCrossing = false
            editingID = nil
            isLifting = false
            showsSettings = false
            menu = nil
        }
        .onChange(of: focus) { old, new in
            // Leaving the empty line keeps what was typed on it.
            if old == .newTask, new != .newTask { addDraft() }
            // With a keyboard, the page listens whenever nothing is being written.
            if new == nil, Self.hasKeyboard { focus = .page }
        }
        .onAppear { if Self.hasKeyboard { focus = .page } }
        .background {
            Color.clear
                .focusable()
                .focused($focus, equals: .page)
                .focusEffectDisabled()
                .onKeyPress(phases: .down, action: keyPressed)
        }
        #if os(macOS)
        .onExitCommand(perform: escape)
        #endif
        .focusedSceneValue(\.pageCommands, commands)
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardIsUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardIsUp = false
        }
        #endif
    }

    /// Live tasks, and struck ones that have not left yet, in page order.
    private var tasksOnPage: [TaskItem] {
        (list.tasks ?? [])
            .filter { $0.isLive || held[$0.id] != nil }
            .sorted { $0.order < $1.order }
    }

    private func strike(_ task: TaskItem, with strokes: [Stroke]) {
        context.strike(task, strokeData: Stroke.encode(strokes))
        startHold(task)
    }

    /// Struck tasks leave together, a hold after the last strike. Each new
    /// strike starts the hold again for all of them, and none leaves while a
    /// finger is still crossing a task, so the lines never move under it.
    private func startHold(_ task: TaskItem) {
        held[task.id] = 0
        restartHold()
    }

    private func restartHold() {
        holds += 1
        let token = holds
        for id in held.keys where held[id] != Self.paused { held[id] = token }
        guard held.values.contains(token), !isCrossing else { return }
        // The pen is still drawing when the hold starts.
        let drawing = Duration.seconds(TaskLine.secondsPerLine * Double(TaskLine.lineLimit))
        Task { @MainActor in
            try? await Task.sleep(for: Self.hold + drawing)
            // A newer hold has taken over, or a finger is on a task again.
            guard !isCrossing, held.values.contains(token) else { return }
            withAnimation(reduceMotion ? nil : .shuffle) {
                held = held.filter { $0.value != token }
            }
        }
    }

    private func crossingBegan() {
        isCrossing = true
        // Whatever was about to leave waits.
        holds += 1
        for id in held.keys where held[id] != Self.paused { held[id] = holds }
    }

    private func crossingEnded() {
        isCrossing = false
        restartHold()
    }

    private func pauseHold(_ task: TaskItem) {
        held[task.id] = Self.paused
    }

    private func restore(_ task: TaskItem) {
        context.restore(task)
        held[task.id] = nil
    }

    /// A list name was tapped. It always leads to that list's page, its own included.
    private func turn(to target: TaskList) {
        guard menu == nil else { return }
        if isLanding {
            // A second name tapped while the page is still turning: the first
            // turn is finished at once, and the next sets off from there.
            guard target !== incoming, let current = finishLanding() else { return }
            Task { @MainActor in
                // One frame, so the page is drawn at rest before it moves again.
                try? await Task.sleep(for: .milliseconds(20))
                guard !isLanding, turnAmount == 0 else { return }
                begin(target, from: current)
            }
            return
        }
        guard target !== list else {
            showsArchive = false
            showsSettings = false
            return
        }
        begin(target, from: list)
    }

    private func begin(_ target: TaskList, from current: TaskList) {
        guard target !== current else { return }
        let from = lists.firstIndex { $0 === current } ?? 0
        let to = lists.firstIndex { $0 === target } ?? 0
        incoming = target
        incomingSide = to > from ? 1 : -1
        land(on: target)
    }

    /// Ends a turn that is still on its way, without waiting for it: the list
    /// being turned to becomes the page now. Returns that list.
    @discardableResult
    private func finishLanding() -> TaskList? {
        guard isLanding, let target = incoming else { return nil }
        // Whatever the turn had still to do is no longer wanted.
        landings += 1
        var swap = Transaction()
        swap.disablesAnimations = true
        withTransaction(swap) {
            select(target)
            turnAmount = 0
            showsArchive = false
            showsSettings = false
            incoming = nil
            incomingCovers = false
            isLanding = false
        }
        return target
    }

    /// A sideways drag on empty paper or the list names turns the page: it
    /// follows the finger, with the next list beside it. Left for the next list,
    /// right for the one before. Not while writing or carrying a task, or in settings.
    private func turnChanged(_ amount: CGFloat) {
        guard !isWriting, !isLifting, !showsSettings, menu == nil else { return }
        // A new swipe while the page is still turning: that turn is finished at
        // once, and the page follows the finger from the next movement on.
        guard !isLanding else {
            finishLanding()
            return
        }
        let side = amount < 0 ? 1 : -1
        if amount != 0, let target = lists.neighbour(of: list, by: side) {
            incoming = target
            incomingSide = side
            turnAmount = amount.clamped(to: -1...1)
            // The same distance `turnEnded` asks for.
            let armed = abs(amount) > 0.35
            if armed != isTurnArmed {
                isTurnArmed = armed
                turnArms += 1
            }
        } else {
            // There is no page past the first or the last: the page gives a little and no more.
            incoming = nil
            turnAmount = amount * 0.2
        }
    }

    private func turnEnded(_ amount: CGFloat, _ speed: CGFloat) {
        isTurnArmed = false
        guard !isLanding else { return }
        // Far enough, or a quick flick the same way.
        let flicked = abs(amount) > 0.05 && speed * amount > 0 && abs(speed) > 1.2
        if let target = incoming, turnAmount != 0, abs(amount) > 0.35 || flicked {
            land(on: target)
        } else {
            // Pulled well past the first or the last page: the paper stops there.
            if incoming == nil, abs(amount) > 0.2 { bumps += 1 }
            withAnimation(.settle) {
                turnAmount = 0
            } completion: {
                if !isLanding { incoming = nil }
            }
        }
    }

    /// Finishes the turn, then makes the incoming list the page.
    /// What was being written stays on the list it was written on.
    private func land(on target: TaskList) {
        addDraft()
        focus = nil
        isLanding = true
        landings += 1
        let token = landings
        // Felt at the instant the turn is asked for, as the page sets off.
        if !PenHaptics.shared.snap() { turnTaps += 1 }
        let arrive = {
            showsArchive = false
            showsSettings = false
            select(target)
            turnAmount = 0
            incoming = nil
            isLanding = false
        }
        guard !reduceMotion else {
            // No sliding: the new page fades in over the old one.
            withAnimation(.easeInOut(duration: 0.2)) { arrive() }
            return
        }
        withAnimation(.turn) {
            turnAmount = CGFloat(-incomingSide)
        } completion: {
            // Another turn took over before this one arrived.
            guard token == landings, isLanding else { return }
            // The real page takes the place of the one that slid in. The one that
            // slid in stays on top for a moment, so the swap is never seen.
            var swap = Transaction()
            swap.disablesAnimations = true
            withTransaction(swap) {
                incomingCovers = true
                select(target)
                turnAmount = 0
                showsArchive = false
                showsSettings = false
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard token == landings else { return }
                withTransaction(swap) {
                    incoming = nil
                    incomingCovers = false
                    isLanding = false
                }
            }
        }
    }

    // MARK: Menus

    /// Move to, Copy, Delete. Move to opens the other lists in the same menu.
    private var taskMenuOptions: [MenuOption] {
        guard case .task(let id, let moving) = menu,
              let task = (list.tasks ?? []).first(where: { $0.id == id })
        else { return [] }
        if moving {
            return lists.filter { $0 !== list }.map { other in
                MenuOption(title: other.name) {
                    menu = nil
                    removals += 1
                    withAnimation(reduceMotion ? nil : .shuffle) { context.move(task, to: other) }
                }
            }
        }
        // No Edit: a tap on the task already edits it.
        var options: [MenuOption] = []
        if lists.count > 1 {
            options.append(MenuOption(title: "Move to") { menu = .task(id, moving: true) })
        }
        options.append(MenuOption(title: "Copy") {
            menu = nil
            copies += 1
            copy(task.text)
        })
        // No confirmation: deleting a task is undone with a shake or Cmd+Z.
        options.append(MenuOption(title: "Delete", isDestructive: true) {
            menu = nil
            removals += 1
            withAnimation(reduceMotion ? nil : .shuffle) { context.delete(task) }
        })
        return options
    }

    /// Rename and Delete list. Deleting asks first, because the tasks and the archive go with it.
    private var listMenuOptions: [MenuOption] {
        guard case .list(let id, let confirming) = menu, let held = lists.first(where: { $0.id == id })
        else { return [] }
        if confirming {
            return [
                MenuOption(title: "Yes, delete", isDestructive: true) {
                    menu = nil
                    removals += 1
                    context.delete(held)
                },
                MenuOption(title: "Keep") { menu = nil },
            ]
        }
        var options = [MenuOption(title: "Rename") {
            menu = nil
            renamingID = id
        }]
        // The last list cannot be deleted: there would be no page left.
        if lists.count > 1 {
            options.append(MenuOption(title: "Delete list", isDestructive: true) {
                menu = .list(id, confirmingDelete: true)
            })
        }
        return options
    }

    /// The question before a list is deleted is showing.
    private var isConfirmingDelete: Bool {
        if case .list(_, confirmingDelete: true) = menu { true } else { false }
    }

    private func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// Dragging up past the end of the page shows what is done, or puts settings away.
    /// Not while writing or carrying.
    private func pullPastEnd() {
        guard !isWriting, !isLifting, menu == nil else { return }
        if showsSettings {
            showsSettings = false
        } else {
            showsArchive = true
        }
    }

    /// Dragging down past the top of the archive goes back to the page.
    /// Dragging down past the top of the page brings settings down.
    private func pullPastTop() {
        guard !isWriting, !isLifting, menu == nil else { return }
        if showsArchive {
            showsArchive = false
        } else {
            showsSettings = true
        }
    }

    // MARK: Keyboard

    /// Mac, and iPad with a keyboard attached.
    private static var hasKeyboard: Bool {
        #if os(macOS)
        true
        #else
        GCKeyboard.coalesced != nil
        #endif
    }

    private var isWriting: Bool { focus != nil && focus != .page }

    /// Start typing, and a task starts on the empty line (brief: Interaction model).
    private func keyPressed(_ press: KeyPress) -> KeyPress.Result {
        if press.key == .escape {
            escape()
            return .handled
        }
        guard !showsArchive, !showsSettings, menu == nil, !isLanding,
              press.modifiers.subtracting([.shift, .capsLock]).isEmpty,
              press.characters.count == 1, let character = press.characters.first,
              character.isLetter || character.isNumber || character.isPunctuation || character.isSymbol
        else { return .ignored }
        draft += press.characters
        focus = .newTask
        // The cursor goes after what was typed, not around it.
        let end = TextSelection(insertionPoint: draft.endIndex)
        draftSelection = end
        Task { @MainActor in draftSelection = end }
        return .handled
    }

    /// Escape puts away whatever is open, one thing at a time.
    private func escape() {
        if menu != nil {
            menu = nil
        } else if isWriting {
            focus = nil
        } else if showsSettings {
            showsSettings = false
        } else if showsArchive {
            showsArchive = false
        }
    }

    private var commands: PageCommands {
        PageCommands(
            lists: lists.map { ($0.id, $0.name) },
            select: { id in
                if let target = lists.first(where: { $0.id == id }) { turn(to: target) }
            },
            showsSettings: showsSettings,
            toggleSettings: {
                guard !isLanding else { return }
                menu = nil
                focus = nil
                showsArchive = false
                showsSettings.toggle()
            },
            showsArchive: showsArchive,
            toggleArchive: {
                guard !isLanding else { return }
                menu = nil
                focus = nil
                showsSettings = false
                showsArchive.toggle()
            },
            strikeTask: editingID.map { id in
                {
                    // The task goes back on the page as text, and the pen crosses it there.
                    pendingStrikeID = id
                    editingID = nil
                    focus = nil
                }
            }
        )
    }

    /// Tapping empty paper starts a task. While writing, it puts the pen down instead.
    private func tapPaper() {
        // A tap on the page behind a menu puts it away.
        guard menu == nil else {
            menu = nil
            return
        }
        guard !showsArchive else { return }
        // A tap on the page behind settings puts them away.
        guard !showsSettings else {
            showsSettings = false
            return
        }
        focus = isWriting ? nil : .newTask
    }

    /// Return on the empty line: keep the task and start the next one.
    /// Return on a blank line stops writing.
    private func submitDraft() {
        if addDraft() {
            // Return puts the pen down on iOS. Pick it up again once that has happened.
            Task { @MainActor in focus = .newTask }
        } else {
            focus = nil
        }
    }

    /// Adds what is on the empty line, one task per line of text.
    @discardableResult
    private func addDraft() -> Bool {
        let lines = draft.split(whereSeparator: \.isNewline)
        draft = ""
        return lines.reduce(false) { added, line in
            context.addTask(String(line), to: list) != nil || added
        }
    }
}
