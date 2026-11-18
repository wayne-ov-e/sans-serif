import SwiftData
import SwiftUI

/// What a task line asks of the page when it is struck.
struct StrikeActions {
    /// The strike is committed: store it and start the hold before the task leaves.
    var strike: (TaskItem, [Stroke]) -> Void
    /// A drag back across a struck task has begun: keep it on the page meanwhile.
    var pauseHold: (TaskItem) -> Void
    /// The drag back stopped short: the task stays struck and the hold starts again.
    var resumeHold: (TaskItem) -> Void
    /// The strike is undone.
    var restore: (TaskItem) -> Void
    /// A drag across a task has begun, or ended. While one is going on, no
    /// struck task leaves the page, so nothing moves under the finger.
    var dragBegan: () -> Void = {}
    var dragEnded: () -> Void = {}
}

/// A task on the page. Tap it to edit it in place. Drag across it to strike it,
/// and drag back across it to undo while it is still on the page.
struct TaskLine: View {
    let task: TaskItem
    var focus: FocusState<PageView.Field?>.Binding
    @Binding var editingID: UUID?
    let actions: StrikeActions
    /// Off while a task is being carried to a new place.
    var canStrike = true
    /// Ink on the live page, faded ink in the archive.
    var strikeColor: Color = .ink
    /// Opens the task's menu, for VoiceOver and Switch Control.
    var showMenu: (() -> Void)?
    /// The lines of this task's menu while it is open. It floats beside the task, over the page.
    var menu: [MenuOption]?
    /// The task a keyboard shortcut has asked to strike, once it is back on the page as text.
    var pendingStrikeID: Binding<UUID?> = .constant(nil)

    /// Longer text is cut with an ellipsis on the page and shown in full when editing.
    static let lineLimit = 3
    /// The pen takes this long over each line of text.
    static let secondsPerLine = 0.16

    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var undos = 0
    /// The pen's way across the line, felt as it goes.
    @State private var ticks = DragTicks()
    /// Strikes that ended a drag. The drag was felt already, so its end is quiet.
    @State private var releases = 0
    /// Letting go now would count. Felt as one click when it becomes true.
    @State private var isArmed = false
    @State private var arms = 0

    @State private var text = ""
    @State private var lines: [StrikeLine] = []
    @State private var strokes: [Stroke] = []
    /// Lines struck so far. See `StrikeMarks`.
    @State private var progress = 0.0
    @State private var drag: Drag?
    @State private var commits = 0
    @State private var rowWidth: CGFloat = 0
    /// The bottom of the line in the page, to tell whether a menu has room below.
    @State private var bottomInPage: CGFloat = 0
    @Environment(\.listNamesTop) private var listNamesTop

    private enum Drag { case striking, undoing, ignored }

    private var field: PageView.Field { .task(task.id) }
    private var lineCount: Int { max(lines.count, 1) }

    var body: some View {
        if editingID == task.id {
            LineField(text: $text) { focus.wrappedValue = nil }
                .focused(focus, equals: field)
                .onAppear {
                    text = task.text
                    focus.wrappedValue = field
                }
                .onChange(of: focus.wrappedValue) { old, new in
                    if old == field, new != field, editingID == task.id { editingID = nil }
                }
                // Whatever ends the edit, the text is kept.
                .onDisappear(perform: commitEdit)
        } else {
            Text(task.text)
                .typeStyle(.task)
                .foregroundStyle(task.isLive ? .ink : .inkFaded)
                .lineLimit(Self.lineLimit)
                .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { proxy in
                        let measured = StrikeLine.measure(layouts, in: proxy)
                        StrikeMarks(lines: measured, strokes: strokes, progress: progress, color: strikeColor)
                            .onChange(of: measured, initial: true) { _, new in linesChanged(new) }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if task.isLive, menu == nil { editingID = task.id } }
                // A drag that starts anywhere on the task's row strikes it.
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onHorizontalDrag(onChanged: dragChanged, onEnded: dragEnded)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(PageSpace.name)).maxY } action: {
                    bottomInPage = $0
                }
                .overlay(alignment: menuCorner) {
                    // A point on the line's corner that the menu hangs from, so it
                    // takes no room and nothing on the page moves.
                    Color.clear.frame(width: 0, height: 0).overlay(alignment: menuHangs) {
                        if let menu {
                            TextMenu(options: menu)
                                .padding(.vertical, menuFitsBeside ? 3 : Self.menuGapBelow)
                                .offset(x: menuFitsBeside ? textWidth + Self.menuGap : 0)
                        }
                    }
                }
                .animation(.easeOut(duration: 0.25), value: task.isLive)
                .haptic(.drag, trigger: ticks)
                .haptic(.release, trigger: releases)
                .haptic(.edge, trigger: arms)
                .haptic(.pen, trigger: commits)
                .haptic(.lift, trigger: undos)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(task.text)
                .accessibilityValue(task.isLive ? "" : "Struck")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { if task.isLive { editingID = task.id } }
                .accessibilityAction(named: task.isLive ? "Strike" : "Undo strike") {
                    task.isLive ? strikeWithoutDrag() : undo()
                }
                .accessibilityAction(named: "Show menu") { showMenu?() }
        }
    }

    // MARK: Menu

    private static let menuGap: CGFloat = 24
    /// Between a long task and the menu below it.
    private static let menuGapBelow: CGFloat = 12
    /// Room a menu needs: its widest line, and its three lines.
    private static let menuWidth: CGFloat = 120
    private static let menuHeight: CGFloat = 120

    private var textWidth: CGFloat { lines.map(\.maxX).max() ?? 0 }

    /// The menu sits to the right of the text when there is room for it.
    private var menuFitsBeside: Bool { textWidth + Self.menuGap + Self.menuWidth <= rowWidth }

    /// Near the bottom of the page the menu grows upward, clear of the list names.
    private var menuGrowsUp: Bool { bottomInPage + Self.menuHeight > (listNamesTop ?? .infinity) }

    /// Beside the text: level with it. With no room beside: below the task,
    /// on its left edge, or above it when growing upward.
    private var menuCorner: Alignment {
        if menuFitsBeside { return menuGrowsUp ? .bottomLeading : .topLeading }
        return menuGrowsUp ? .topLeading : .bottomLeading
    }

    private var menuHangs: Alignment {
        menuGrowsUp ? .bottomLeading : .topLeading
    }

    // MARK: Editing

    /// Keeps the edit. A task emptied of its text is removed.
    private func commitEdit() {
        guard task.modelContext != nil else { return }
        let edited = text
            .split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if edited.isEmpty {
            context.delete(task)
        } else if edited != task.text {
            task.text = edited
        }
    }

    // MARK: Striking

    private func linesChanged(_ new: [StrikeLine]) {
        lines = new
        if pendingStrikeID.wrappedValue == task.id, !new.isEmpty {
            pendingStrikeID.wrappedValue = nil
            if task.isLive { strikeWithoutDrag() }
        }
        // A task that arrives already struck shows its stored lines in full.
        if !task.isLive, drag == nil {
            strokes = task.strokes(forLines: new.count)
            progress = Double(new.count)
        }
    }

    private func dragChanged(_ value: HorizontalDragValue) {
        guard let line = lines.first else { return }
        if drag == nil {
            // The first report of a drag has not moved yet. Wait to see which way it goes.
            guard abs(value.translation.width) >= 2 else { return }
            beginDrag(value, on: line)
        }

        switch drag {
        case .striking:
            // An Apple Pencil's pressure sets how thick the line is.
            if let pressure = value.pressure, !strokes.isEmpty {
                strokes[0].weight = Stroke.weight(forPressure: pressure)
            }
            guard let stroke = strokes.first else { return }
            // The first line follows the finger. The rest are drawn on the lift.
            let start = StrikePath.startX(stroke, on: line)
            let end = StrikePath.endX(stroke, on: line)
            let reach = ((value.location.x - start) / (end - start)).clamped(to: 0...1)
            // Ease in over the first few points, so a drag that starts part way
            // along the text does not make the line jump.
            let easeIn = (value.translation.width / 28).clamped(to: 0...1)
            progress = reach * easeIn
            feel(value, along: progress, armed: willStrike(value, on: line))
        case .undoing:
            let reach = undoReach(value, on: line)
            progress = Double(lineCount) * (1 - reach)
            feel(value, along: reach, armed: reach >= 0.5)
        case .ignored, nil:
            break
        }
    }

    private func beginDrag(_ value: HorizontalDragValue, on line: StrikeLine) {
        if !canStrike || menu != nil {
            drag = .ignored
        } else if task.isLive, value.translation.width > 0 {
            drag = .striking
            land()
            actions.dragBegan()
            let seed = UInt64.random(in: 0...UInt64.max)
            let run = max(abs(value.velocity.width), 1)
            let first = Stroke.drawn(
                seed: seed,
                lift: (line.midY - value.startLocation.y) / line.xHeight,
                slope: -value.velocity.height / run,
                speed: run
            )
            strokes = [first] + Stroke.generated(lines: lineCount, seed: seed).dropFirst()
        } else if !task.isLive, value.translation.width < 0 {
            drag = .undoing
            land()
            actions.dragBegan()
            actions.pauseHold(task)
        } else {
            drag = .ignored
        }
    }

    private func dragEnded(_ value: HorizontalDragValue) {
        defer {
            if drag == .striking || drag == .undoing { actions.dragEnded() }
            drag = nil
        }
        guard let line = lines.first else { return }

        switch drag {
        case .striking:
            // Commit when the drag has passed most of the text. Otherwise the line retracts.
            if willStrike(value, on: line) {
                // The lines below the first are drawn for the user, and felt one by one.
                if !PenHaptics.shared.lift(
                    speed: abs(value.velocity.width), extraLines: lineCount - 1, every: Self.secondsPerLine
                ) { releases += 1 }
                commit(dragged: true)
            } else {
                if !PenHaptics.shared.retract() { releases += 1 }
                retract()
            }
        case .undoing:
            if undoReach(value, on: line) >= 0.5 {
                if !PenHaptics.shared.lift(speed: abs(value.velocity.width)) { releases += 1 }
                undo(dragged: true)
            } else {
                if !PenHaptics.shared.retract() { releases += 1 }
                draw(to: Double(lineCount))
                actions.resumeHold(task)
            }
        case .ignored, nil:
            PenHaptics.shared.stop()
        }
    }

    /// How far a drag back has come, from 0 to 1.
    private func undoReach(_ value: HorizontalDragValue, on line: StrikeLine) -> Double {
        let length = max(line.maxX - line.minX, 1)
        return (-value.translation.width / (length * 0.7)).clamped(to: 0...1)
    }

    /// Letting go here strikes the task: the pen has passed most of the text.
    private func willStrike(_ value: HorizontalDragValue, on line: StrikeLine) -> Bool {
        progress >= 0.6 && value.translation.width >= min((line.maxX - line.minX) * 0.4, 90)
    }

    /// The pen lands: a continuous texture on iPhone, plain taps elsewhere.
    private func land() {
        isArmed = false
        if !PenHaptics.shared.land() { ticks.land() }
    }

    /// The pen moves across the line, and clicks once where letting go starts to count.
    private func feel(_ value: HorizontalDragValue, along: Double, armed: Bool) {
        if !PenHaptics.shared.move(speed: abs(value.velocity.width), along: along) {
            ticks.move(to: along)
        }
        if armed != isArmed {
            isArmed = armed
            if !PenHaptics.shared.click(armed: armed) { arms += 1 }
        }
    }

    private func commit(dragged: Bool = false) {
        if !dragged { commits += 1 }
        actions.strike(task, strokes)
        draw(to: Double(lineCount))
    }

    private func retract() {
        draw(to: 0) { strokes = [] }
    }

    /// Lifts the lines in reverse order, last line first.
    private func undo(dragged: Bool = false) {
        if !dragged { undos += 1 }
        actions.restore(task)
        draw(to: 0) { if task.isLive { strokes = [] } }
    }

    /// A strike made without a drag, by VoiceOver or the keyboard: the line is drawn for the user.
    private func strikeWithoutDrag() {
        strokes = Stroke.generated(lines: lineCount, seed: .random(in: 0...UInt64.max))
        commit()
    }

    /// Moves the pen to a number of lines struck. With Reduce Motion the lines
    /// appear together, without the drawing.
    private func draw(to target: Double, then completion: @escaping () -> Void = {}) {
        let duration = abs(target - progress) * Self.secondsPerLine
        guard !reduceMotion, duration > 0 else {
            progress = target
            completion()
            return
        }
        withAnimation(.easeOut(duration: duration)) {
            progress = target
        } completion: {
            completion()
        }
    }
}

/// A line of the page that can be typed on: no border, no placeholder, wraps like a task.
struct LineField: View {
    @Binding var text: String
    var selection: Binding<TextSelection?> = .constant(nil)
    /// Return was pressed. The line break is never kept in the text.
    let onReturn: () -> Void

    var body: some View {
        TextField("", text: $text, selection: selection, axis: .vertical)
            .textFieldStyle(.plain)
            .typeStyle(.task)
            .foregroundStyle(.ink)
            .tint(.ink)
            // A wrapping field takes Return as a line break on iOS and as submit on the Mac.
            .onChange(of: text) { _, new in
                guard new.last?.isNewline == true else { return }
                text.removeLast()
                onReturn()
            }
            .onSubmit(onReturn)
    }
}
