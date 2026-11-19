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
        /// The name of a list that is being added.
        case newList
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
    /// The pages stand in a row, one per list. This is where the row is, in
    /// pages: 1 is the second list in the middle of the paper. At rest it is
    /// the open list's own place. One value moves for a swipe, a tap and a
    /// second tap that comes before the first has landed, so quick turns keep
    /// their speed and run into one another.
    @State private var position: CGFloat = 0
    /// The row is moving, under a finger or by itself.
    @State private var isTurning = false
    /// A finger is moving the row.
    @State private var isDraggingTurn = false
    /// The list the row is heading for. The list names already show it.
    @State private var heading: TaskList?
    /// The page turned to is on screen, and the real one is being laid out under it.
    @State private var stripCovers = false
    /// Counts turns, so that one cut short by the next does not finish twice.
    @State private var turns = 0
    /// A new list is being named, after the last name.
    @State private var isNamingList = false
    /// Something the app has to say, shown where the list names are for a moment.
    @State private var notice: String?
    #if os(iOS)
    /// The share sheet is up for this list.
    @State private var sharing: ListShare?
    #endif
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
            footerStaysClear: keyboardIsUp && HourEntry.shared.typing != nil,
            scrollDisabled: isLifting,
            onTapPaper: tapPaper,
            turn: CGFloat(index(of: list)) - place,
            strip: strip,
            stripCovers: stripCovers,
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
        } footer: {
            Group {
            if keyboardIsUp, let which = HourEntry.shared.typing {
                // A work hour is being typed in settings: AM, PM and done.
                HourEntryWords(which: which)
            } else if let notice {
                Button { self.notice = nil } label: {
                    Text(notice)
                        .typeStyle(.monthLabel)
                        .foregroundStyle(.inkFaded)
                        .frame(maxWidth: .infinity, minHeight: metrics.minTouchHeight, alignment: .leading)
                }
                .buttonStyle(.plain)
            } else if case .task(_, let moving) = menu {
                // A task is held: what can be done with it stands where the list names were.
                MenuRow(options: taskMenuOptions, label: moving ? "Move to" : nil, note: moving ? nil : menuNote)
            } else if keyboardIsUp, renamingID == nil, !isNamingList {
                // While writing, the list names make way for a way to stop.
                // On the right, above the keyboard's own return key, where the thumb already is.
                BottomWord(word: "done") { focus = nil }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
            ListNames(
                lists: lists,
                current: heading ?? list,
                select: turn,
                menuListID: menu?.listID,
                menuOptions: listMenuOptions,
                openMenu: { menu = .list($0.id, confirmingDelete: false) },
                renamingID: $renamingID,
                focus: $focus,
                rename: { context.rename($0, to: $1) },
                isNamingList: $isNamingList,
                addList: addList,
                openArchive: { showsArchive = true },
                openSettings: { showsSettings = true }
            )
            }
            }
            // The row of words changes with a short fade. Only the row: an
            // animation laid over the whole page reaches the text fields too.
            .animation(.quick, value: menu?.taskID)
            .animation(.quick, value: notice)
        }
        // Turning to a list: a swipe ticks where letting go will turn the page.
        // Then, for a swipe or a tap on a name, one short crisp haptic at the
        // instant the page sets off.
        #if os(iOS)
        .sheet(item: $sharing) { item in
            ShareSheet(item: item).ignoresSafeArea()
        }
        #endif
        .haptic(.pen, trigger: isNamingList) { $0 }
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
        // At rest the row stands at the open list. Lists can be added, removed and reordered.
        .onChange(of: lists.map(\.id), initial: true) {
            if !isTurning { position = CGFloat(index(of: list)) }
        }
        .onChange(of: list.id) {
            if !isTurning { position = CGFloat(index(of: list)) }
            // What was held or half done belongs to the page that was left.
            held = [:]
            isCrossing = false
            editingID = nil
            isLifting = false
            showsSettings = false
            menu = nil
            isNamingList = false
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
        context.strike(task, strokeData: Stroke.encode(strokes), by: list.isShared ? CloudSync.shared.myName : nil)
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
        // The page had begun to follow the same drag: it lets go.
        if isDraggingTurn {
            isDraggingTurn = false
            isTurning = false
            isTurnArmed = false
            position = CGFloat(index(of: list))
        }
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

    // MARK: Turning

    private func index(of list: TaskList) -> Int {
        lists.firstIndex { $0 === list } ?? 0
    }

    /// Where the row of pages is now.
    private var place: CGFloat {
        isTurning ? position : CGFloat(index(of: list))
    }

    /// Every other list's page, beside this one. While a landed page covers
    /// the real one, this list's is among them.
    private var strip: [StripPage] {
        lists.enumerated().compactMap { index, other in
            guard stripCovers || other !== list else { return nil }
            return StripPage(id: other.id, x: CGFloat(index) - place, view: AnyView(PagePreview(list: other)))
        }
    }

    /// A list name was tapped. It always leads to that list's page, its own included.
    private func turn(to target: TaskList) {
        guard menu == nil else { return }
        guard isTurning || target !== list else {
            showsArchive = false
            showsSettings = false
            return
        }
        go(to: target)
    }

    /// Sends the row of pages to a list. Called again before it has arrived,
    /// the row goes on from where it is, at the speed it has.
    /// What was being written stays on the list it was written on.
    private func go(to target: TaskList, animation: Animation = .turn) {
        addDraft()
        focus = nil
        let changesCourse = target !== (heading ?? list)
        // Coming back to the page that never left: nothing needs covering.
        let returns = target === list && !stripCovers
        heading = target
        turns += 1
        let token = turns
        // Felt at the instant the turn is asked for, as the page sets off.
        if changesCourse, !PenHaptics.shared.snap() { turnTaps += 1 }
        var still = Transaction()
        still.disablesAnimations = true
        guard !reduceMotion else {
            // No sliding: the new page fades in over the old one.
            withAnimation(.easeInOut(duration: 0.2)) {
                select(target)
                position = CGFloat(index(of: target))
                showsArchive = false
                showsSettings = false
                isTurning = false
                stripCovers = false
                heading = nil
            }
            return
        }
        isTurning = true
        withAnimation(animation) {
            position = CGFloat(index(of: target))
        } completion: {
            // Another turn took over before this one arrived.
            guard token == turns else { return }
            guard !returns else {
                isTurning = false
                heading = nil
                return
            }
            // The real page takes the place of the one that slid in. The one that
            // slid in stays on top for a moment, so the swap is never seen.
            withTransaction(still) {
                stripCovers = true
                select(target)
                showsArchive = false
                showsSettings = false
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                guard token == turns else { return }
                withTransaction(still) {
                    isTurning = false
                    stripCovers = false
                    heading = nil
                }
            }
        }
    }

    /// Ends a turn that is still on its way, without waiting for it: the list
    /// it was heading for becomes the page now.
    private func settle() {
        guard isTurning, let target = heading else { return }
        turns += 1
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            select(target)
            position = CGFloat(index(of: target))
            showsArchive = false
            showsSettings = false
            isTurning = false
            stripCovers = false
            heading = nil
        }
    }

    /// A sideways drag along the bottom of the page moves the row of pages
    /// with the finger. Left for the next list, right for the one before.
    /// Not while writing or carrying a task, or in settings.
    private func turnChanged(_ amount: CGFloat) {
        // Not while a task is being struck or a strike undone: that drag is the pen's.
        guard !isWriting, !isLifting, !showsSettings, !isCrossing, menu == nil else { return }
        // A new swipe while the row is still moving by itself: that turn is
        // finished at once, and the row follows the finger from the next movement on.
        guard isDraggingTurn || !isTurning else {
            settle()
            return
        }
        // The first few points are left for a task to claim the drag as a strike.
        guard isDraggingTurn || abs(amount) > 0.03 else { return }
        isDraggingTurn = true
        isTurning = true
        heading = nil
        let here = CGFloat(index(of: list))
        let last = CGFloat(max(lists.count - 1, 0))
        var wanted = here - amount.clamped(to: -1...1)
        // There is no page past the first or the last: the row gives a little and no more.
        if wanted < 0 { wanted *= 0.2 }
        if wanted > last { wanted = last + (wanted - last) * 0.2 }
        position = wanted
        // The same distance `turnEnded` asks for.
        let armed = abs(amount) > 0.35 && lists.neighbour(of: list, by: amount < 0 ? 1 : -1) != nil
        if armed != isTurnArmed {
            isTurnArmed = armed
            turnArms += 1
        }
    }

    private func turnEnded(_ amount: CGFloat, _ speed: CGFloat) {
        isTurnArmed = false
        guard isDraggingTurn else { return }
        isDraggingTurn = false
        let neighbour = lists.neighbour(of: list, by: amount < 0 ? 1 : -1)
        // Far enough, or a quick flick the same way.
        let flicked = abs(amount) > 0.05 && speed * amount > 0 && abs(speed) > 1.2
        if amount != 0, let neighbour, abs(amount) > 0.35 || flicked {
            go(to: neighbour)
        } else {
            // Pulled well past the first or the last page: the paper stops there.
            if neighbour == nil, abs(amount) > 0.2 { bumps += 1 }
            go(to: list, animation: .settle)
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
        // The one that matters. Drawing a loop round the task does the same.
        options.append(MenuOption(title: task.isCircled ? "Uncircle" : "Circle") {
            menu = nil
            context.toggleCircle(task)
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
        #if os(iOS)
        // Invite people, see who is on the list, stop sharing or leave.
        options.append(MenuOption(title: held.isShared ? "Shared" : "Share") {
            menu = nil
            share(held)
        })
        #endif
        options.append(MenuOption(title: "New list") {
            menu = nil
            isNamingList = true
        })
        // The last list cannot be deleted: there would be no page left.
        if lists.count > 1 {
            options.append(MenuOption(title: "Delete list", isDestructive: true) {
                menu = .list(id, confirmingDelete: true)
            })
        }
        return options
    }

    /// A name was written for a new list: it is added after the last, and becomes the page.
    private func addList(named name: String) {
        guard let new = try? context.addList(named: name) else { return }
        settle()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { select(new) }
    }

    /// On a shared list, who wrote the held task and who struck it.
    private var menuNote: String? {
        guard list.isShared, case .task(let id, _) = menu,
              let task = (list.tasks ?? []).first(where: { $0.id == id }), let who = task.addedBy
        else { return nil }
        return "Added by \(who)"
    }

    #if os(iOS)
    /// Opens the system's sharing sheet for a list. The list has to be in
    /// iCloud first, so this can take a moment, and can fail.
    private func share(_ target: TaskList) {
        guard CloudSync.shared.isRunning else {
            say("Turn on iCloud sync to share.")
            return
        }
        Task { @MainActor in
            do {
                let share = target.isSomeoneElses
                    ? try await CloudSync.shared.joinedShare(for: target)
                    : try await CloudSync.shared.share(for: target)
                sharing = ListShare(share: share, list: target)
            } catch {
                say("Could not reach iCloud to share.")
            }
        }
    }
    #endif

    /// A word from the app, at the bottom of the page, for a few seconds.
    private func say(_ words: String) {
        notice = words
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(4))
            if notice == words { notice = nil }
        }
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
        guard !showsArchive, !showsSettings, menu == nil, !isTurning,
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
                guard !isTurning else { return }
                menu = nil
                focus = nil
                showsArchive = false
                showsSettings.toggle()
            },
            showsArchive: showsArchive,
            toggleArchive: {
                guard !isTurning else { return }
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
            context.addTask(String(line), to: list, by: CloudSync.shared.myName) != nil || added
        }
    }
}
