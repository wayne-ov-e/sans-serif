import SwiftData
import SwiftUI

/// The first page: a to-do list about the app itself (brief: First run). Each
/// line is an instruction, and doing what it says crosses it off. There are no
/// overlays, arrows or pop-ups.
struct GuideView: View {
    /// The user's lists. What they write here is carried into the first one.
    let lists: [TaskList]
    /// Opened again from the Gestures line in settings, not for the first time.
    let isReplay: Bool
    let finish: () -> Void

    /// The lines, in order.
    enum Step: Int, CaseIterable {
        case cross, write, hold, circle, repeats, swipe, pullUp, pullDown, end

        var line: String {
            switch self {
            case .cross: "Cross me off."
            case .write: "Tap below and write your own."
            case .hold: "Hold a line for more."
            case .circle: "Circle what matters."
            case .repeats: "Hold me to repeat."
            case .swipe: "Swipe along the bottom for the next list."
            case .pullUp: "Pull up for what is done."
            case .pullDown: "Pull down for settings."
            case .end: "That is all. The page is yours."
            }
        }

        /// What VoiceOver says the line asks for.
        var hint: String {
            switch self {
            case .cross: "Drag across the line to strike it."
            case .write: "Tap the empty paper and write a task."
            case .hold: "Hold a line to open its menu, then put the menu away."
            case .circle: "Draw a loop round the line, or hold it and choose Circle."
            case .repeats: "Hold the line, choose Repeat, then how often."
            case .swipe: "Swipe sideways along the bottom of the page to the next list, then swipe back."
            case .pullUp: "Drag up to see what is done, then drag down to come back."
            case .pullDown: "Drag down to see settings, then drag up to come back."
            case .end: "Tap begin."
            }
        }

        var seed: UInt64 { UInt64(rawValue) &* 7919 &+ 101 }
    }

    @Environment(\.modelContext) private var context
    @Environment(\.pageMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var step = Step.cross
    /// The task the user wrote in the second step. It stays live.
    @State private var ownTask: String?
    @State private var draft = ""
    @FocusState private var isWriting: Bool
    @State private var keyboardIsUp = false
    @State private var showsArchive = false
    @State private var showsSettings = false
    /// The line whose menu is open: a step, or -1 for the user's own task.
    @State private var menuLine: Int?
    /// Where the row of two pages is: 0 is this page, 1 the next list's.
    @State private var position: CGFloat = 0
    /// The next list's page is the one showing.
    @State private var isOnNext = false
    @State private var hasSeenNext = false
    @State private var isDraggingTurn = false
    /// "Circle what matters." has its loop.
    @State private var isCircled = false
    /// The held line's row shows how often, after Repeat was chosen.
    @State private var isChoosingRepeat = false
    /// How often the repeat line was set to come back: the small word after it.
    @State private var repeatMark: String?
    /// Counted for the haptic of a page turned.
    @State private var turnTaps = 0
    /// Counted for the haptic of a step crossed off.
    @State private var steps = 0

    private static let ownLine = -1

    var body: some View {
        PageColumn(
            showsArchive: showsArchive,
            showsHeader: showsSettings,
            footerStaysClear: keyboardIsUp && HourEntry.shared.typing != nil,
            onTapPaper: tapPaper,
            turn: -position,
            // The next list's page stands beside this one for the swipe, as in the app.
            strip: step == .swipe ? [StripPage(id: "next", x: 1 - position, view: AnyView(nextPage))] : [],
            onTurnChanged: turnChanged,
            onTurnEnded: turnEnded,
            onPullPastEnd: pullPastEnd,
            onPullPastTop: pullPastTop
        ) {
            SettingsLines(showsGestures: false)
        } content: {
            lines
        } archive: {
            archive
        } footer: {
            if keyboardIsUp, let which = HourEntry.shared.typing {
                HourEntryWords(which: which)
            } else if menuLine != nil {
                MenuRow(options: isChoosingRepeat ? repeatOptions : menuOptions, label: isChoosingRepeat ? "Repeat" : nil)
            } else if keyboardIsUp {
                BottomWord(word: "done") { isWriting = false }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else if step == .end {
                BottomWord(word: "begin") { end(struck: true) }
            } else if step == .swipe {
                // The list names, as on the page: the one that is open is in ink,
                // and a tap on a name turns to it as a swipe does.
                HStack(alignment: .firstTextBaseline, spacing: metrics.listNameGap) {
                    ForEach(Array(listNames.enumerated()), id: \.offset) { index, name in
                        Button { go(toNext: index == 1) } label: {
                            Text(name)
                                .typeStyle(.listName)
                                .foregroundStyle((index == 1) == isOnNext ? .ink : .inkFaded)
                                .frame(minHeight: metrics.minTouchHeight)
                                .contentShape(Rectangle().inset(by: -metrics.listNameGap / 2))
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    BottomWord(word: "skip", isFaded: true) { end(struck: false) }
                }
                .animation(.quick, value: isOnNext)
                // The swipe is made down here, along the names.
                .overlay(alignment: .top) {
                    if !hasSeenNext { GuideGesture(kind: .sideways).offset(y: -40) }
                }
            } else {
                BottomWord(word: "skip", isFaded: true) { end(struck: false) }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .haptic(.pen, trigger: steps)
        .haptic(.turn, trigger: turnTaps)
        .haptic(.pen, trigger: menuLine) { $0 != nil }
        .sheetHaptics(showsArchive)
        .sheetHaptics(showsSettings)
        .onChange(of: isWriting) { _, writing in
            // Whatever ends the writing, what was written is kept.
            if !writing { keepDraft() }
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

    // MARK: The page

    private var lines: some View {
        VStack(alignment: .leading, spacing: metrics.taskGap) {
            ForEach(Step.allCases.filter { $0.rawValue <= step.rawValue }, id: \.self) { each in
                line(each)
                if each == .write {
                    if let ownTask {
                        own(ownTask)
                    } else if step == .write {
                        emptyLine
                    }
                }
            }
        }
        // The pulls are made on the empty paper, and have their guide there,
        // below the last line. It lies over the paper and adds nothing to its
        // length: with nine lines above, it made the page longer than the
        // screen, and a drag up then moved the page along instead of pulling it.
        .overlay(alignment: .bottom) {
            Color.clear.frame(height: 0).overlay(alignment: .top) {
                switch step {
                case .pullUp where !showsArchive: GuideGesture(kind: .up).padding(.top, 36)
                // The page is at its fullest here: shorter, and closer to the line.
                case .pullDown where !showsSettings: GuideGesture(kind: .down, length: 96).padding(.top, 36)
                default: EmptyView()
                }
            }
        }
        .padding(.bottom, metrics.taskGap)
        .animation(reduceMotion ? nil : .shuffle, value: step)
        .animation(.quick, value: menuLine)
    }

    private func line(_ each: Step) -> some View {
        let isActive = each == step
        return GuideLine(
            text: each.line,
            isStruck: each.rawValue < step.rawValue,
            seed: each.seed,
            strikesByDrag: isActive && each == .cross,
            showsRing: isActive && (each == .hold || each == .repeats) && menuLine == nil && repeatMark == nil,
            circlesByDrag: isActive && each == .circle,
            isCircled: each == .circle && isCircled,
            mark: each == .repeats ? repeatMark : nil,
            onStruckByDrag: { complete(.cross, felt: true) },
            onCircled: circle
        )
        .holdable(
            id: each.rawValue, isEnabled: holds, menuLine: $menuLine, options: menuOptions
        )
        .fadesUnderListNames()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(each.line)
        .accessibilityValue(each.rawValue < step.rawValue ? "Done" : "")
        .accessibilityHint(isActive ? each.hint : "")
        .accessibilityAction(named: "Do this step") {
            if isActive, each != .write, each != .end { complete(each) }
        }
    }

    /// The user's own task, in ink among the instructions.
    private func own(_ text: String) -> some View {
        Text(text)
            .typeStyle(.task)
            .foregroundStyle(.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .holdable(
                id: Self.ownLine, isEnabled: holds, menuLine: $menuLine, options: menuOptions
            )
            .fadesUnderListNames()
            .transition(.opacity)
    }

    /// The empty line of the second step: a cursor and a dotted ring until it is tapped.
    private var emptyLine: some View {
        ZStack(alignment: .leading) {
            LineField(text: $draft) { isWriting = false }
                .focused($isWriting)
                .accessibilityLabel("New task")
            if !isWriting, draft.isEmpty {
                HStack(spacing: 14) {
                    Rectangle().fill(Color.ink).frame(width: 2, height: 28)
                    GuideRing()
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .transition(.opacity)
            }
        }
        .animation(.quick, value: isWriting)
    }

    /// What is done so far, as the archive will show it.
    private var archive: some View {
        VStack(alignment: .leading, spacing: metrics.archiveTaskGap) {
            // As the archive will show them: struck today.
            Text("Done today")
                .typeStyle(.monthLabel)
                .foregroundStyle(.inkFaded)
                .accessibilityAddTraits(.isHeader)
            ForEach(Step.allCases.filter { $0.rawValue < step.rawValue }.reversed(), id: \.self) { each in
                GuideLine(text: each.line, isStruck: true, seed: each.seed, strikeColor: .inkFaded, writesIn: false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(each.line)
                    .accessibilityValue("Struck")
            }
        }
        .padding(.bottom, metrics.taskGap)
    }

    /// A line can be held for its menu from the step that says so until the
    /// steps about the menu are done.
    private var holds: Bool { step == .hold || step == .circle || step == .repeats }

    /// The menu a held line opens: the same six words as on the page. Here
    /// they only put the menu away, but Circle and Repeat: those do what
    /// their own lines ask for.
    private var menuOptions: [MenuOption] {
        [
            MenuOption(title: "Move to") { closeMenu() },
            MenuOption(title: "Copy") { closeMenu() },
            MenuOption(title: "Select") { closeMenu() },
            MenuOption(title: "Circle") {
                closeMenu()
                circle()
            },
            MenuOption(title: "Repeat") {
                // Only the repeat line, on its own step, goes on to how often.
                if step == .repeats, menuLine == Step.repeats.rawValue {
                    isChoosingRepeat = true
                } else {
                    closeMenu()
                }
            },
            MenuOption(title: "Delete", isDestructive: true) { closeMenu() },
        ]
    }

    /// How often, as the page asks. Here any of them will do, and the days of
    /// a week or a month are not gone into: the word alone is written.
    private var repeatOptions: [MenuOption] {
        ["Daily", "Weekly", "Monthly", "Yearly"].map { word in
            MenuOption(title: word) { setRepeat(word.lowercased()) }
        }
    }

    /// The names at the bottom of the page for the swipe: the user's first two lists.
    private var listNames: [String] {
        let names = lists.prefix(2).map(\.name)
        return names + ["life", "work"].suffix(2 - names.count)
    }

    /// The next list's page, as the swipe finds it: one line, saying how to come back.
    private var nextPage: some View {
        VStack(alignment: .leading, spacing: metrics.taskGap) {
            Text("Swipe back, or tap \(listNames[0]).")
                .typeStyle(.task)
                .foregroundStyle(.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Doing what the lines say

    /// - Parameter felt: the step was a drag that had its own haptics on the way.
    private func complete(_ done: Step, felt: Bool = false) {
        guard step == done, let next = Step(rawValue: done.rawValue + 1) else { return }
        if !felt { steps += 1 }
        step = next
    }

    /// The circle line has its loop. It is left to be seen for a moment before the line is struck.
    private func circle() {
        guard step == .circle, !isCircled else { return }
        isCircled = true
        steps += 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            complete(.circle, felt: true)
        }
    }

    /// The repeat line has its small word. It is left to be seen for a moment before the line is struck.
    private func setRepeat(_ mark: String) {
        closeMenu()
        guard step == .repeats, repeatMark == nil else { return }
        repeatMark = mark
        steps += 1
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            complete(.repeats, felt: true)
        }
    }

    private func closeMenu() {
        guard menuLine != nil else { return }
        menuLine = nil
        isChoosingRepeat = false
        complete(.hold)
    }

    private func tapPaper() {
        if menuLine != nil {
            closeMenu()
        } else if showsSettings {
            showsSettings = false
            complete(.pullDown)
        } else if step == .write, !showsArchive {
            isWriting.toggle()
        }
    }

    private func keepDraft() {
        let text = draft
            .split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !text.isEmpty, step == .write else { return }
        ownTask = text
        complete(.write)
    }

    /// The swipe turns to the next list's page and back, as it does in the app.
    private func turnChanged(_ amount: CGFloat) {
        guard step == .swipe, menuLine == nil else { return }
        guard isDraggingTurn || abs(amount) > 0.03 else { return }
        isDraggingTurn = true
        var wanted = (isOnNext ? 1 : 0) - amount.clamped(to: -1...1)
        // There are two pages here and no more: past either, the row only gives a little.
        if wanted < 0 { wanted *= 0.2 }
        if wanted > 1 { wanted = 1 + (wanted - 1) * 0.2 }
        position = wanted
    }

    private func turnEnded(_ amount: CGFloat, _ speed: CGFloat) {
        guard isDraggingTurn else { return }
        isDraggingTurn = false
        // Far enough, or a quick flick the same way.
        let flicked = abs(amount) > 0.05 && speed * amount > 0 && abs(speed) > 1.2
        let turns = abs(amount) > 0.35 || flicked
        if turns, !isOnNext, amount < 0 {
            go(toNext: true)
        } else if turns, isOnNext, amount > 0 {
            go(toNext: false)
        } else {
            withAnimation(reduceMotion ? nil : .settle) { position = isOnNext ? 1 : 0 }
        }
    }

    /// Turns to the next list's page, or back. Back from it, the line is done.
    private func go(toNext next: Bool) {
        guard step == .swipe, next != isOnNext else { return }
        isOnNext = next
        if next { hasSeenNext = true }
        if !PenHaptics.shared.snap() { turnTaps += 1 }
        withAnimation(reduceMotion ? nil : .turn) {
            position = next ? 1 : 0
        } completion: {
            if !isOnNext, hasSeenNext { complete(.swipe, felt: true) }
        }
    }

    private func pullPastEnd() {
        guard menuLine == nil, !isWriting else { return }
        if showsSettings {
            showsSettings = false
            complete(.pullDown)
        } else if step.rawValue >= Step.pullUp.rawValue {
            showsArchive = true
        }
    }

    private func pullPastTop() {
        guard menuLine == nil, !isWriting else { return }
        if showsArchive {
            showsArchive = false
            complete(.pullUp)
        } else if step.rawValue >= Step.pullDown.rawValue {
            showsSettings = true
        }
    }

    /// Begin, or skip. The user's own task goes to their first list either way.
    /// After begin, the first time, the struck lines go to its archive.
    private func end(struck: Bool) {
        isWriting = false
        keepDraft()
        if let first = lists.first {
            let keeps = struck && !isReplay
            context.finishGuide(
                ownTask: ownTask,
                struckLines: keeps ? Step.allCases.filter { $0 != .end }.map(\.line) : [],
                in: first
            )
            // Saved before the page appears. The page turns undo on, and on
            // iOS 26 SwiftData stops the app when it is asked to undo a change
            // to something made before undo was on and not yet saved: every
            // new user's app stopped here, at the end of the first page.
            try? context.save()
        }
        finish()
    }
}

private extension View {
    /// Hold the line, and its menu opens below it while the other lines recede.
    func holdable(id: Int, isEnabled: Bool, menuLine: Binding<Int?>, options: [MenuOption]) -> some View {
        let isHeld = menuLine.wrappedValue == id
        return self
            .onLiftDrag(isEnabled: isEnabled && menuLine.wrappedValue == nil) {
                menuLine.wrappedValue = id
            } onChanged: { _ in
            } onEnded: {
            }
            .receded(menuLine.wrappedValue != nil && !isHeld)
            .zIndex(isHeld ? 1 : 0)
    }
}
