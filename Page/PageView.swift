import CloudKit
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
    /// How tall the line being written is: it changes when the words wrap.
    @State private var draftHeight: CGFloat = 0
    @State private var draftSelection: TextSelection?
    /// The task a keyboard shortcut has asked to strike.
    @State private var pendingStrikeID: UUID?
    @State private var keyboardIsUp = false
    /// A task is picked up for reordering. The page holds still meanwhile.
    @State private var isLifting = false
    /// The archive is showing instead of the page.
    @State private var showsArchive = false
    /// "Delete all" was chosen for a struck task: everything under its heading
    /// of the archive is about to go, and the page asks first.
    @State private var isConfirmingDone = false
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
    /// Where the open page is while the row moves by itself. See `TurnFlight`.
    @State private var flight = TurnFlight()
    /// A finger caught the row while it was moving: how far the row then was
    /// from where a drag of that length would have put it. The row goes on
    /// from where it was caught.
    @State private var caught: CGFloat = 0
    /// How far the finger had gone when it caught the row, to tell its own
    /// travel from where the row happened to be.
    @State private var caughtAt: CGFloat?
    /// The list the row is heading for. The list names already show it.
    @State private var heading: TaskList?
    /// The page turned to is on screen, and the real one is being laid out under it.
    @State private var stripCovers = false
    /// A turn to another list is putting the archive or settings away. The
    /// turn was felt as it set off: the sheet leaving is not felt as well
    /// (Wayne, Nov 19, 2026: from the archive to another list gave two haptics).
    @State private var turnPutsSheetsAway = false
    @State private var quiets = 0
    /// Counts turns, so that one cut short by the next does not finish twice.
    @State private var turns = 0
    /// A new list is being named, after the last name.
    @State private var isNamingList = false
    /// Something the app has to say, shown where the list names are for a moment.
    @State private var notice: String?
    /// The list being shared. Its lines stand where settings do, in their place.
    @State private var sharingID: UUID?
    /// Counts the times the share lines were brought down.
    @State private var shareOpens = 0
    /// The menu that is open, if any.
    @State private var menu: PageMenu?
    /// The held task's menu is asking when it repeats, and how far it has got.
    @State private var repeatStep: RepeatStep?
    /// Counted when the day changes, so that a repeat whose day has come is on the page.
    @State private var days = 0
    /// Tasks picked out to be deleted together. Nothing while none are being picked.
    @State private var picked: Set<UUID>?
    /// The question before the picked tasks are deleted is showing.
    @State private var isConfirmingPicked = false
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
            footerStaysClear: keyboardIsUp && keysAreElsewhere,
            scrollDisabled: isLifting,
            onTapPaper: tapPaper,
            turn: CGFloat(index(of: list)) - place,
            strip: strip,
            stripCovers: stripCovers,
            flight: flight,
            onTurnChanged: turnChanged,
            onTurnEnded: turnEnded,
            followsEnd: followsEnd,
            endKey: endKey,
            onPullPastEnd: pullPastEnd,
            onPullPastTop: pullPastTop
        ) {
            headerLines
        } content: {
            taskLines
        } archive: {
            archiveLines
        } footer: {
            footerWords
        }
        // Turning to a list: a swipe ticks where letting go will turn the page.
        // Then, for a swipe or a tap on a name, one short crisp haptic at the
        // instant the page sets off.
        .haptic(.pen, trigger: isNamingList) { $0 }
        .haptic(.selection, trigger: turnArms)
        .haptic(.turn, trigger: turnTaps)
        // The archive and settings, coming and going, are felt the same way.
        .sheetHaptics(showsArchive, quietly: turnPutsSheetsAway)
        // The question about deleting what is done is asked afresh for each menu.
        .onChange(of: menu) { _, _ in
            isConfirmingDone = false
            repeatStep = nil
        }
        .modifier(DayWatch(days: $days))
        // A line put down: whatever was struck meanwhile may leave now.
        .onChange(of: isLifting) { _, lifting in if !lifting { restartHold() } }
        // The task or list a menu was open on has gone, from here or another device.
        .onChange(of: menuIsStale) { _, stale in if stale { menu = nil } }
        .sheetHaptics(showsSettings, quietly: turnPutsSheetsAway)
        // The lines above the page put away while a name or an hour is being
        // typed in them: the typing ends and what was typed is kept.
        .onChange(of: showsSettings) { _, shows in
            if !shows, keysAreElsewhere { HourEntry.shared.dones += 1 }
        }
        .haptic(.edge, trigger: bumps)
        .haptic(.putDown, trigger: removals)
        .haptic(.pen, trigger: copies)
        .haptic(.warning, trigger: isConfirmingDelete) { $0 }
        .haptic(.pen, trigger: menu?.listID) { $0 != nil }
        // At rest the row stands at the open list. Lists can be added, removed and reordered.
        .onChange(of: lists.map(\.id), initial: true) { rest() }
        .onChange(of: list.id) { pageChanged() }
        .onChange(of: focus) { old, new in focusChanged(old, new) }
        .onChange(of: keysAreElsewhere) { old, new in keysMoved(old, new) }
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
        // Something iCloud has to say: a list that could not be joined.
        .onReceive(NotificationCenter.default.publisher(for: CloudSync.said)) { note in
            if let words = note.object as? String { say(words) }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardIsUp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardIsUp = false
        }
        #endif
    }

    // The parts of the page, each on its own: together in `body` they were
    // more than the compiler would work out.

    /// Sharing a list, or settings, above the page.
    @ViewBuilder private var headerLines: some View {
        if let shared = lists.first(where: { $0.id == sharingID }) {
            ShareLines(list: shared) {
                // Leaving is deleting the list here: the page asks first.
                showsSettings = false
                menu = .list(shared.id, confirmingDelete: true)
            }
            // Asked afresh each time the lines are brought down: who is on
            // the list may have changed since, and no old question is left open.
            .id(shareOpens)
        } else {
            SettingsLines()
        }
    }

    private var taskLines: some View {
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
            pendingStrikeID: $pendingStrikeID,
            picked: picked,
            pick: { task in
                // Only what is still to do can be picked.
                guard task.isLive else { return }
                isConfirmingPicked = false
                if picked?.contains(task.id) == true { picked?.remove(task.id) } else { picked?.insert(task.id) }
            },
            draftRows: { draftHeight = $0 }
        )
    }

    /// The row at the bottom of the page: list names, or the words for what is going on.
    private var footerWords: some View {
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
        } else if picked != nil {
            // Tasks are being picked out: what to do with them stands where the list names were.
            MenuRow(
                options: pickedOptions(pickedNow),
                label: isConfirmingPicked ? "Delete \(pickedNow.count)?" : "\(pickedNow.count) picked"
            )
        } else if case .task(_, let moving) = menu {
            // A task is held: what can be done with it stands where the list names were.
            MenuRow(
                options: taskMenuOptions,
                label: moving ? "Move to" : repeatStep?.label ?? doneQuestion,
                note: moving || isConfirmingDone || repeatStep != nil ? nil : menuNote,
                ticks: repeatStep?.isDays ?? false,
                showing: repeatShowing
            )
        } else if keyboardIsUp, renamingID == nil, !isNamingList {
            // While writing, the list names make way for a way to stop.
            // On the right, above the keyboard's own return key, where the thumb already is.
            BottomWord(word: "done") {
                focus = nil
                // And for a field that is not the page's own.
                if HourEntry.shared.isWritingElsewhere { HourEntry.shared.dones += 1 }
            }
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
            openSettings: openSettings
        )
        }
        }
        // The row of words changes with a short fade. Only the row: an
        // animation laid over the whole page reaches the text fields too.
        .animation(.quick, value: menu?.taskID)
        .animation(.quick, value: repeatStep)
        .animation(.quick, value: notice)
        .animation(.quick, value: picked != nil)
        .animation(.quick, value: isConfirmingPicked)
    }

    private var archiveLines: some View {
        ArchiveLines(
            list: list, focus: $focus, menuTaskID: menu?.taskID,
            openMenu: { menu = .task($0.id, moving: false) },
            closeMenu: { menu = nil }
        )
    }

    /// Live tasks, and struck ones that have not left yet, in page order.
    private var tasksOnPage: [TaskItem] {
        // Read so that the page is looked at again when the day changes.
        _ = days
        return (list.tasks ?? [])
            .filter { $0.isOnPage || held[$0.id] != nil }
            .sorted(by: TaskItem.inPageOrder)
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
        // Nor while a line is carried: the hold starts again when it is put down.
        guard !isLifting else { return }
        // The pen is still drawing when the hold starts.
        let drawing = Duration.seconds(TaskLine.secondsPerLine * Double(TaskLine.lineLimit))
        Task { @MainActor in
            try? await Task.sleep(for: Self.hold + drawing)
            // A newer hold has taken over, or a finger is on a task again.
            guard !isCrossing, !isLifting, held.values.contains(token) else { return }
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
            caught = 0
            caughtAt = nil
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
    /// `speed`: a finger let go of the row at this speed, in pages a second.
    private func go(to target: TaskList, animation: Animation? = nil, speed: CGFloat? = nil) {
        addDraft()
        focus = nil
        let changesCourse = target !== (heading ?? list)
        // Coming back to the page that never left: nothing needs covering.
        let returns = target === list && !stripCovers
        heading = target
        turns += 1
        let token = turns
        // A sheet the turn puts away says nothing of its own: the turn is felt
        // already. Only when there is a sheet to put away, and only until it
        // is away. This used to be said on every turn and held for 1.2 s, so a
        // sheet pulled up or down just after a turn was not felt at all
        // (Wayne, Nov 21, 2026).
        if target !== list, showsArchive || showsSettings {
            // Counted apart from the turns: a later turn back to the open
            // page starts no quiet of its own, and must not keep this one.
            quiets += 1
            let quiet = quiets
            turnPutsSheetsAway = true
            // In case the turn never lands: it is not left quiet for good.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.2))
                if quiet == quiets { turnPutsSheetsAway = false }
            }
        }
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
            Task { @MainActor in turnPutsSheetsAway = false }
            return
        }
        // How far there is to go: from where the row is, if it is already moving.
        let end = CGFloat(index(of: target))
        let start = isTurning ? position : CGFloat(index(of: list))
        var spring = animation ?? .turn(across: abs(end - start))
        if animation == nil, let speed {
            // Positive towards the page turned to.
            spring = .turn(across: abs(end - start), atSpeed: end > start ? speed : -speed)
        }
        isTurning = true
        // When the spring is nominally over the page is still coming to rest:
        // measured, 5 pt from its place. The swap takes two or three frames,
        // and done at that moment it held the page there before it went on,
        // so the turn seemed to catch at the end (Wayne, Nov 20, 2026:
        // "animation ending still feels a bit not smooth"). So the swap waits
        // a little longer, until the page is within half a point. Waiting for
        // the spring to be wholly at rest took 0.65 s, too long before the
        // page can be written on.
        let rest = Animation.turnTime(across: abs(end - start)) * 0.45
        withAnimation(spring) {
            position = end
        } completion: {
            // Another turn took over before this one arrived.
            guard token == turns else { return }
            guard !returns else {
                isTurning = false
                heading = nil
                turnPutsSheetsAway = false
                return
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(rest))
                guard token == turns else { return }
                // The real page takes the place of the one that slid in. The one that
                // slid in stays on top for a moment, so the swap is never seen.
                withTransaction(still) {
                    stripCovers = true
                    select(target)
                    showsArchive = false
                    showsSettings = false
                }
                try? await Task.sleep(for: .milliseconds(80))
                guard token == turns else { return }
                withTransaction(still) {
                    isTurning = false
                    stripCovers = false
                    heading = nil
                }
                // The sheets are away: the next one pulled is felt again.
                turnPutsSheetsAway = false
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
        }        // A moment later, once the sheets have heard they are away.
        Task { @MainActor in turnPutsSheetsAway = false }
    }

    /// A sideways drag along the bottom of the page moves the row of pages
    /// with the finger. Left for the next list, right for the one before.
    /// Not while writing or carrying a task, or in settings.
    private func turnChanged(_ amount: CGFloat) {
        // Not while a task is being struck or a strike undone: that drag is the pen's.
        guard !isWriting, !isLifting, !showsSettings, !isCrossing, menu == nil, picked == nil else { return }
        // A new swipe while the row is still moving by itself: that turn is
        // finished at once, and the row follows the finger from the next movement on.
        guard isDraggingTurn || !isTurning else {
            catchRow(at: amount)
            return
        }
        // The first few points are left for a task to claim the drag as a strike.
        guard isDraggingTurn || abs(amount) > 0.03 else { return }
        if !isDraggingTurn {
            caught = 0
            caughtAt = nil
        }
        isDraggingTurn = true
        isTurning = true
        heading = nil
        let here = CGFloat(index(of: list))
        let last = CGFloat(max(lists.count - 1, 0))
        // How far the row has been moved from the open page, the catch included.
        let amount = (amount - caught).clamped(to: -1...1)
        var wanted = here - amount
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

    /// A finger comes down on the row while it is moving by itself. The row
    /// stops where it is and follows the finger from there: it does not jump
    /// to the end of the turn first. The page nearest the middle of the paper
    /// becomes the open one.
    private func catchRow(at amount: CGFloat) {
        let now = CGFloat(index(of: list)) - flight.x
        let nearest = min(max(Int(now.rounded()), 0), max(lists.count - 1, 0))
        guard lists.indices.contains(nearest) else {
            settle()
            return
        }
        turns += 1
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            if lists[nearest] !== list {
                select(lists[nearest])
                showsArchive = false
                showsSettings = false
            }
            position = now
            stripCovers = false
            heading = nil
            isTurning = true
            isDraggingTurn = true
        }
        // A drag of this length from the nearest page would stand at
        // `nearest - amount`. The row is at `now`.
        caught = amount - (CGFloat(nearest) - now)
        caughtAt = amount
    }

    private func turnEnded(_ amount: CGFloat, _ speed: CGFloat) {
        isTurnArmed = false
        guard isDraggingTurn else { return }
        isDraggingTurn = false
        // The finger's own travel, apart from where a caught row stood.
        let finger = amount - (caughtAt ?? 0)
        let wasCaught = caughtAt != nil
        var amount = amount - caught
        caught = 0
        caughtAt = nil
        // A quick flick turns the way the finger went, wherever the row was caught.
        let flicked = abs(finger) > 0.05 && speed * finger > 0 && abs(speed) > 1.2
        if flicked { amount = finger }
        let neighbour = lists.neighbour(of: list, by: amount < 0 ? 1 : -1)
        // Far enough. A row that was caught and let go again goes to the page
        // nearest the middle: it is not sent back against the turn it was on.
        let far = abs(amount) > (wasCaught ? 0.5 : 0.35)
        if amount != 0, let neighbour, far || flicked {
            // The page goes on at the speed the finger had. The row moves
            // against the finger's count: a drag to the left is a turn onward.
            go(to: neighbour, speed: -speed)
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
        if !task.isLive { return doneOptions(task) }
        if let repeatStep { return repeatOptions(task, at: repeatStep) }
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
        // Several at once: this one is picked, and a tap on each of the others picks it too.
        if (list.tasks ?? []).count(where: \.isOnPage) > 1 {
            options.append(MenuOption(title: "Select") {
                menu = nil
                focus = nil
                picked = [task.id]
            })
        }
        // The one that matters. Drawing a loop round the task does the same.
        options.append(MenuOption(title: task.isCircled ? "Uncircle" : "Circle") {
            menu = nil
            context.toggleCircle(task)
        })
        // When it comes back after it is struck.
        options.append(MenuOption(title: "Repeat") { repeatStep = .rule })
        // No confirmation: deleting a task is undone with a shake or Cmd+Z.
        options.append(MenuOption(title: "Delete", isDestructive: true) {
            menu = nil
            removals += 1
            withAnimation(reduceMotion ? nil : .shuffle) {
                context.endRepeat(of: task)
                context.delete(task)
            }
        })
        return options
    }

    /// When a task repeats, asked a step at a time in the same row: how often,
    /// then which day. A rule tapped is kept at once, with today as its day,
    /// so the row can be left at any step.
    private func repeatOptions(_ task: TaskItem, at step: RepeatStep) -> [MenuOption] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day, .weekday], from: .now)
        let rule = task.rule?.every
        func keep(_ every: Repeat.Every) {
            Tap.word()
            context.setRepeat(Repeat(every), on: task)
        }
        switch step {
        case .rule:
            var options = [
                MenuOption(title: "Daily") {
                    keep(.day)
                    menu = nil
                },
                MenuOption(title: "Weekly") {
                    if case .week = rule {} else { keep(.week([today.weekday ?? 2])) }
                    repeatStep = .week
                },
                MenuOption(title: "Monthly") {
                    if case .month = rule {} else { keep(.month(today.day ?? 1)) }
                    repeatStep = .month
                },
                MenuOption(title: "Yearly") {
                    if case .year = rule {} else { keep(.year(month: today.month ?? 1, day: today.day ?? 1)) }
                    repeatStep = .yearMonth
                },
            ]
            if task.repeats != nil {
                options.append(MenuOption(title: "Never") {
                    Tap.word()
                    context.setRepeat(nil, on: task)
                    menu = nil
                })
            }
            return options
        case .week:
            var chosen: Set<Int> = []
            if case .week(let days) = rule { chosen = days }
            return Repeat.weekOrder.map { day in
                MenuOption(title: Repeat.weekdayNames[day - 1], isFaded: !chosen.contains(day)) {
                    // Several days can be chosen. The last one cannot be given up.
                    var days = chosen
                    if days.contains(day) { days.remove(day) } else { days.insert(day) }
                    if !days.isEmpty { keep(.week(days)) }
                }
            }
        case .month:
            var chosen = 0
            if case .month(let day) = rule { chosen = day }
            return (Array(1...31) + [Repeat.lastDay]).map { day in
                MenuOption(title: day == Repeat.lastDay ? "Last" : "\(day)", isFaded: day != chosen) {
                    keep(.month(day))
                    menu = nil
                }
            }
        case .yearMonth:
            var chosen = 0
            if case .year(let month, _) = rule { chosen = month }
            return (1...12).map { month in
                MenuOption(title: Repeat.monthNames[month - 1], isFaded: month != chosen) {
                    Tap.word()
                    repeatStep = .yearDay(month)
                }
            }
        case .yearDay(let month):
            var chosen = 0
            if case .year(month, let day) = rule { chosen = day }
            return (1...Repeat.days(in: month)).map { day in
                MenuOption(title: "\(day)", isFaded: day != chosen) {
                    keep(.year(month: month, day: day))
                    menu = nil
                }
            }
        }
    }

    /// The word a row of days opens on: the day already chosen.
    private var repeatShowing: String? {
        guard let repeatStep, case .task(let id, _) = menu,
              let rule = (list.tasks ?? []).first(where: { $0.id == id })?.rule?.every
        else { return nil }
        switch (repeatStep, rule) {
        case (.month, .month(let day)): return day == Repeat.lastDay ? "Last" : "\(day)"
        case (.yearMonth, .year(let month, _)): return Repeat.monthNames[month - 1]
        case (.yearDay(let shown), .year(let month, let day)) where shown == month: return "\(day)"
        default: return nil
        }
    }

    /// A struck task held in the archive: put it back, copy it, delete it, or
    /// delete everything done under the same heading (Wayne, Nov 19, 2026:
    /// "being able to delete past done things in archive").
    private func doneOptions(_ task: TaskItem) -> [MenuOption] {
        let group = list.doneGroup(with: task)
        if isConfirmingDone {
            return [
                MenuOption(title: "Yes, delete", isDestructive: true) {
                    menu = nil
                    removals += 1
                    withAnimation(reduceMotion ? nil : .shuffle) {
                        _ = context.deleteTasks(Set(group.map(\.id)), in: list)
                    }
                },
                MenuOption(title: "Keep") { menu = nil },
            ]
        }
        var options = [
            MenuOption(title: "Restore") {
                menu = nil
                withAnimation(reduceMotion ? nil : .shuffle) { context.restore(task) }
            },
            MenuOption(title: "Copy") {
                menu = nil
                copies += 1
                copy(task.text)
            },
            // No confirmation for one: it is undone with a shake or Cmd+Z.
            MenuOption(title: "Delete", isDestructive: true) {
                menu = nil
                removals += 1
                withAnimation(reduceMotion ? nil : .shuffle) { context.delete(task) }
            },
        ]
        // Everything under the same heading, at once. This asks first.
        if group.count > 1 {
            options.append(MenuOption(title: "Delete all", isDestructive: true) { isConfirmingDone = true })
        }
        return options
    }

    /// The question before everything under a heading of the archive is deleted.
    private var doneQuestion: String? {
        guard isConfirmingDone, case .task(let id, _) = menu,
              let task = (list.tasks ?? []).first(where: { $0.id == id }), !task.isLive
        else { return nil }
        let group = list.doneGroup(with: task)
        if list.doneToday().contains(where: { $0.id == id }) { return "Delete \(group.count) done today?" }
        let month = (task.struckDate ?? .now).formatted(.dateTime.month(.wide))
        return "Delete \(group.count) from \(month)?"
    }

    /// The picked tasks that are still on the page to do. One that was struck
    /// or deleted meanwhile, here or on another device, is not counted and
    /// not deleted with the rest.
    private var pickedNow: Set<UUID> {
        (picked ?? []).intersection(tasksOnPage.filter(\.isLive).map(\.id))
    }

    /// The menu is open on something that is no longer there to be held.
    private var menuIsStale: Bool {
        switch menu {
        case .task(let id, _):
            guard let task = (list.tasks ?? []).first(where: { $0.id == id }) else { return true }
            // On the page, a task that has left it. In the archive, one put back.
            return showsArchive ? task.isLive : !tasksOnPage.contains { $0.id == id }
        case .list(let id, _):
            return !lists.contains { $0.id == id }
        case nil:
            return false
        }
    }

    /// What can be done with the tasks picked out. Deleting several asks first.
    private func pickedOptions(_ picked: Set<UUID>) -> [MenuOption] {
        if isConfirmingPicked {
            return [
                MenuOption(title: "Yes, delete", isDestructive: true) {
                    removals += 1
                    withAnimation(reduceMotion ? nil : .shuffle) { _ = context.deleteTasks(picked, in: list) }
                    stopPicking()
                },
                MenuOption(title: "Keep") { isConfirmingPicked = false },
            ]
        }
        var options: [MenuOption] = []
        if !picked.isEmpty {
            options.append(MenuOption(title: "Delete", isDestructive: true) { isConfirmingPicked = true })
        }
        let live = Set(tasksOnPage.filter(\.isLive).map(\.id))
        if picked != live {
            options.append(MenuOption(title: "All") { self.picked = live })
        }
        options.append(MenuOption(title: "done") {
            Tap.word()
            stopPicking()
        })
        return options
    }

    private func stopPicking() {
        picked = nil
        isConfirmingPicked = false
    }

    /// Rename and Delete list. Deleting asks first, because the tasks and the archive go with it.
    private var listMenuOptions: [MenuOption] {
        guard case .list(let id, let confirming) = menu, let held = lists.first(where: { $0.id == id })
        else { return [] }
        if confirming {
            return [
                // Someone else's list is left, not deleted: it stays theirs.
                MenuOption(title: held.isSomeoneElses ? "Yes, leave" : "Yes, delete", isDestructive: true) {
                    menu = nil
                    removals += 1
                    context.delete(held)
                },
                MenuOption(title: held.isSomeoneElses ? "Stay" : "Keep") { menu = nil },
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
            options.append(MenuOption(title: held.isSomeoneElses ? "Leave list" : "Delete list", isDestructive: true) {
                menu = .list(id, confirmingDelete: true)
            })
        }
        return options
    }

    /// A name was written for a new list: it is added after the last, and becomes the page.
    private func addList(named name: String) {
        guard let new = try? context.addList(named: name) else { return }
        settle()
        withAnimation(reduceMotion ? nil : .quick) { select(new) }
    }

    /// On a shared list, who wrote the held task and who struck it.
    private var menuNote: String? {
        guard list.isShared, case .task(let id, _) = menu,
              let task = (list.tasks ?? []).first(where: { $0.id == id })
        else { return nil }
        return task.byLine
    }

    /// At rest the row of names stands at the open list.
    private func rest() {
        if !isTurning { position = CGFloat(index(of: list)) }
    }

    private func pageChanged() {
        rest()
        // What was held or half done belongs to the page that was left.
        held = [:]
        isCrossing = false
        editingID = nil
        isLifting = false
        showsSettings = false
        menu = nil
        picked = nil
        isConfirmingPicked = false
        isNamingList = false
    }

    private func focusChanged(_ old: Field?, _ new: Field?) {
        // Leaving the empty line keeps what was typed on it.
        if old == .newTask, new != .newTask { addDraft() }
        // With a keyboard, the page listens whenever nothing is being written.
        // Not while an hour is typed in settings: that field is not one
        // of the page's own, and taking the keys back here took them from
        // it, so with a keyboard attached an hour could not be typed at all.
        if new == nil, Self.hasKeyboard, !keysAreElsewhere { focus = .page }
    }

    private func keysMoved(_ before: Bool, _ elsewhere: Bool) {
        if !elsewhere, focus == nil, Self.hasKeyboard { focus = .page }
    }

    /// A new task is being written: the page keeps its line in the best place.
    private var followsEnd: Bool {
        let field: Field? = focus
        return field == .newTask && !showsArchive
    }

    /// Changes when the end of the page moves while a task is being written.
    private var endKey: Int {
        var hasher = Hasher()
        hasher.combine(tasksOnPage.count)
        // Not what is typed: moving the page at every letter lost letters,
        // as the field was drawn again under the keys. Only a new row.
        hasher.combine(draftHeight)
        return hasher.finalize()
    }

    /// An hour or a name is being typed in the lines above the page.
    private var keysAreElsewhere: Bool {
        HourEntry.shared.typing != nil || HourEntry.shared.isWritingElsewhere
    }

    /// Brings down the lines for sharing a list, where settings stand.
    private func share(_ target: TaskList) {
        var canShare = CloudSync.shared.isRunning
        #if DEBUG
        if ShareLines.isPreview { canShare = true }
        #endif
        guard canShare else {
            say("Turn on iCloud sync to share.")
            return
        }
        focus = nil
        showsArchive = false
        sharingID = target.id
        shareOpens += 1
        showsSettings = true
    }

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
        guard !isWriting, !isLifting, menu == nil, picked == nil else { return }
        if showsSettings {
            showsSettings = false
        } else {
            showsArchive = true
        }
    }

    /// Dragging down past the top of the archive goes back to the page.
    /// Dragging down past the top of the page brings settings down.
    private func pullPastTop() {
        guard !isWriting, !isLifting, menu == nil, picked == nil else { return }
        if showsArchive {
            showsArchive = false
        } else {
            openSettings()
        }
    }

    /// Settings come down. Not the lines for sharing a list, which stand in the same place.
    private func openSettings() {
        sharingID = nil
        showsSettings = true
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
        guard !showsArchive, !showsSettings, menu == nil, !isTurning, picked == nil,
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
        if isConfirmingPicked {
            isConfirmingPicked = false
        } else if picked != nil {
            stopPicking()
        } else if menu != nil {
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
                stopPicking()
                focus = nil
                showsArchive = false
                if showsSettings { showsSettings = false } else { openSettings() }
            },
            showsArchive: showsArchive,
            toggleArchive: {
                guard !isTurning else { return }
                menu = nil
                stopPicking()
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
        // A tap on the empty paper while tasks are picked out lets them all go.
        guard picked == nil else {
            stopPicking()
            return
        }
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

/// The steps of asking when a held task repeats.
enum RepeatStep: Equatable {
    /// How often.
    case rule
    /// Which days of the week.
    case week
    /// Which day of the month.
    case month
    /// Which month of the year, and then which day of it.
    case yearMonth
    case yearDay(Int)

    /// What the row of words is for, said before them.
    var label: String {
        switch self {
        case .rule: "Repeat"
        case .week, .yearMonth: "Every"
        case .month: "On the"
        case .yearDay(let month): Repeat.monthNames[month - 1]
        }
    }

    /// A row of days, felt as it slides.
    var isDays: Bool { self != .rule }
}

/// A repeat that waited for today is on the page when today begins, and when
/// the app is come back to: `days` is counted up, and the page looks again.
private struct DayWatch: ViewModifier {
    @Binding var days: Int
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                days += 1
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { days += 1 } }
    }
}

