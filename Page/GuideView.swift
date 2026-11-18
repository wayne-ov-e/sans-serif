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

    /// The lines, in order. "Circle what matters." waits for the circle gesture,
    /// which comes with the widgets.
    enum Step: Int, CaseIterable {
        case cross, write, hold, swipe, pullUp, pullDown, end

        var line: String {
            switch self {
            case .cross: "Cross me off."
            case .write: "Tap below and write your own."
            case .hold: "Hold a line for more."
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
            case .swipe: "Swipe sideways along the bottom of the page."
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
    @State private var turnAmount: CGFloat = 0
    /// Counted for the haptic of a step crossed off.
    @State private var steps = 0

    private static let ownLine = -1

    var body: some View {
        PageColumn(
            showsArchive: showsArchive,
            showsHeader: showsSettings,
            footerStaysClear: keyboardIsUp && HourEntry.shared.typing != nil,
            onTapPaper: tapPaper,
            turn: turnAmount,
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
        } incoming: {
            EmptyView()
        } footer: {
            if keyboardIsUp, let which = HourEntry.shared.typing {
                HourEntryWords(which: which)
            } else if keyboardIsUp {
                BottomWord(word: "done") { isWriting = false }
            } else if step == .end {
                BottomWord(word: "begin") { end(struck: true) }
            } else {
                BottomWord(word: "skip", isFaded: true) { end(struck: false) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // The swipe for the next list is made down here, beside the names.
                    .overlay {
                        if step == .swipe { GuideGesture(kind: .sideways).padding(.leading, 56) }
                    }
            }
        }
        .haptic(.pen, trigger: steps)
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
            // The pulls are made on the empty paper, and have their guide there.
            switch step {
            case .pullUp where !showsArchive: GuideGesture(kind: .up).padding(.top, 44)
            case .pullDown where !showsSettings: GuideGesture(kind: .down).padding(.top, 44)
            default: EmptyView()
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
            showsRing: isActive && each == .hold && menuLine == nil,
            onStruckByDrag: { complete(.cross, felt: true) }
        )
        .holdable(id: each.rawValue, isEnabled: step == .hold, menuLine: $menuLine, options: menuOptions)
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
            .holdable(id: Self.ownLine, isEnabled: step == .hold, menuLine: $menuLine, options: menuOptions)
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
            Text(Date.now.formatted(.dateTime.month(.wide).year()))
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

    /// The menu a held line opens. Here every line of it only puts the menu away.
    private var menuOptions: [MenuOption] {
        [
            MenuOption(title: "Move to") { closeMenu() },
            MenuOption(title: "Copy") { closeMenu() },
            MenuOption(title: "Delete", isDestructive: true) { closeMenu() },
        ]
    }

    // MARK: Doing what the lines say

    /// - Parameter felt: the step was a drag that had its own haptics on the way.
    private func complete(_ done: Step, felt: Bool = false) {
        guard step == done, let next = Step(rawValue: done.rawValue + 1) else { return }
        if !felt { steps += 1 }
        step = next
    }

    private func closeMenu() {
        guard menuLine != nil else { return }
        menuLine = nil
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

    /// There is no next list yet, so the page gives and comes back.
    private func turnChanged(_ amount: CGFloat) {
        guard step == .swipe, menuLine == nil else { return }
        turnAmount = amount * 0.5
    }

    private func turnEnded(_ amount: CGFloat, _ speed: CGFloat) {
        guard step == .swipe else { return }
        withAnimation(reduceMotion ? nil : .settle) { turnAmount = 0 }
        if abs(amount) > 0.15 { complete(.swipe) }
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
            .overlay(alignment: .bottomLeading) {
                Color.clear.frame(width: 0, height: 0).overlay(alignment: .topLeading) {
                    if isHeld { TextMenu(options: options).padding(.top, 12) }
                }
            }
            .receded(menuLine.wrappedValue != nil && !isHeld)
            .zIndex(isHeld ? 1 : 0)
    }
}
