import SwiftData
import SwiftUI

/// The settings, as lines of text at the top of the page. A line that is struck
/// is off. Tap a line to strike it or to turn it on again. Dragging across it
/// and back does the same.
struct SettingsLines: View {
    /// The Gestures line plays the first page again. It is left out on that page itself.
    var showsGestures = true

    @Environment(\.pageMetrics) private var metrics
    @AppStorage(Setting.guideReplay.key) private var guideReplay = Setting.guideReplay.defaultValue
    @AppStorage(Setting.workHours.key) private var workHours = Setting.workHours.defaultValue

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsGap) {
            SettingLine(name: "Show counts", setting: Setting.showCounts, seed: 11)
            SettingLine(name: "iCloud sync", setting: Setting.iCloudSync, seed: 23)
            SettingLine(name: "Haptics", setting: Setting.haptics, seed: 37)
            SettingLine(name: "Dark paper", setting: Setting.darkPaper, seed: 41)
            #if os(iOS)
            // The page on the Lock Screen during working hours, and the hours below it.
            VStack(alignment: .leading, spacing: 2) {
                SettingLine(name: "Work hours", setting: Setting.workHours, seed: 53)
                if workHours {
                    HoursLine().transition(.opacity)
                    ShownListLine().transition(.opacity)
                }
            }
            .animation(.quick, value: workHours)
            #endif
            if showsGestures {
                // Not a setting to strike: a tap shows how the page works.
                Button {
                    guideReplay = true
                } label: {
                    Text("Gestures")
                        .typeStyle(.task)
                        .foregroundStyle(.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows how the page works")
            }
        }
    }
}

private struct SettingLine: View {
    let name: String
    let stroke: Stroke

    @AppStorage private var isOn: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var line: StrikeLine?
    /// How much of the line is struck, from 0 to 1.
    @State private var progress = 0.0
    @State private var drag: Drag?
    @State private var changes = 0
    @State private var ticks = DragTicks()
    @State private var releases = 0
    @State private var isArmed = false
    @State private var arms = 0

    private enum Drag { case striking, undoing, ignored }

    init(name: String, setting: BoolSetting, seed: UInt64) {
        self.name = name
        // The same pen line every time settings open.
        stroke = Stroke.generated(seed: seed)
        _isOn = AppStorage(wrappedValue: setting.defaultValue, setting.key)
    }

    var body: some View {
        Text(name)
            .typeStyle(.task)
            .foregroundStyle(isOn ? .ink : .inkFaded)
            .lineLimit(1)
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { proxy in
                    let measured = StrikeLine.measure(layouts, in: proxy)
                    StrikeMarks(lines: measured, strokes: [stroke], progress: progress)
                        .onChange(of: measured.first, initial: true) { _, new in line = new }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // A tap turns the line off or on. The pen draws or lifts the line by itself.
            .onTapGesture { set(!isOn) }
            .onHorizontalDrag(onChanged: dragChanged, onEnded: dragEnded)
            .animation(.easeOut(duration: 0.25), value: isOn)
            .onAppear { progress = isOn ? 0 : 1 }
            // Changed somewhere else, by VoiceOver or another window.
            .onChange(of: isOn) { _, new in if drag == nil { draw(to: new ? 0 : 1) } }
            .haptic(.drag, trigger: ticks)
            .haptic(.release, trigger: releases)
            .haptic(.edge, trigger: arms)
            .haptic(.pen, trigger: changes)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(isOn ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
            .accessibilityAction { set(!isOn) }
    }

    private func dragChanged(_ value: HorizontalDragValue) {
        guard let line else { return }
        if drag == nil {
            // The first report of a drag has not moved yet. Wait to see which way it goes.
            guard abs(value.translation.width) >= 2 else { return }
            if isOn, value.translation.width > 0 {
                drag = .striking
            } else if !isOn, value.translation.width < 0 {
                drag = .undoing
            } else {
                drag = .ignored
            }
            if drag != .ignored {
                isArmed = false
                if !PenHaptics.shared.land() { ticks.land() }
            }
        }
        switch drag {
        case .striking:
            let start = StrikePath.startX(stroke, on: line)
            let end = StrikePath.endX(stroke, on: line)
            let reach = ((value.location.x - start) / (end - start)).clamped(to: 0...1)
            progress = reach * (value.translation.width / 28).clamped(to: 0...1)
            feel(value, along: progress, armed: willStrike(value, on: line))
        case .undoing:
            progress = 1 - undoReach(value, on: line)
            feel(value, along: 1 - progress, armed: 1 - progress >= 0.5)
        case .ignored, nil:
            break
        }
    }

    private func dragEnded(_ value: HorizontalDragValue) {
        defer { drag = nil }
        guard let line else { return }
        switch drag {
        case .striking:
            end(value, counted: willStrike(value, on: line))
            set(!willStrike(value, on: line), dragged: true)
        case .undoing:
            end(value, counted: undoReach(value, on: line) >= 0.5)
            set(undoReach(value, on: line) >= 0.5, dragged: true)
        case .ignored, nil:
            break
        }
    }

    private func willStrike(_ value: HorizontalDragValue, on line: StrikeLine) -> Bool {
        progress >= 0.6 && value.translation.width >= min((line.maxX - line.minX) * 0.4, 90)
    }

    /// The pen moves across the line, and clicks once where letting go starts to count.
    private func feel(_ value: HorizontalDragValue, along: Double, armed: Bool) {
        if !PenHaptics.shared.move(speed: abs(value.velocity.width), along: along) { ticks.move(to: along) }
        if armed != isArmed {
            isArmed = armed
            if !PenHaptics.shared.click(armed: armed) { arms += 1 }
        }
    }

    /// The pen lifts: a flick if the drag counted, a small soft tap if it did not.
    private func end(_ value: HorizontalDragValue, counted: Bool) {
        let played = counted
            ? PenHaptics.shared.lift(speed: abs(value.velocity.width))
            : PenHaptics.shared.retract()
        if !played { releases += 1 }
    }

    private func undoReach(_ value: HorizontalDragValue, on line: StrikeLine) -> Double {
        (-value.translation.width / (max(line.maxX - line.minX, 1) * 0.7)).clamped(to: 0...1)
    }

    private func set(_ on: Bool, dragged: Bool = false) {
        if on != isOn {
            isOn = on
            // A drag was felt on the way. A tap is felt as the pen lands.
            if !dragged { changes += 1 }
        }
        draw(to: on ? 0 : 1)
    }

    private func draw(to target: Double) {
        let duration = abs(target - progress) * TaskLine.secondsPerLine
        withAnimation(reduceMotion || duration == 0 ? nil : .easeOut(duration: duration)) {
            progress = target
        }
    }
}

/// Which list the Live Activity shows, as words under the hours: "showing
/// the open list", or "showing work". A tap on the name goes to the next
/// choice: the open list, then each list in turn.
private struct ShownListLine: View {
    @Query(sort: TaskList.rowOrder) private var lists: [TaskList]
    @AppStorage(WorkHours.listKey) private var chosen = ""

    private var chosenID: UUID? {
        guard let id = UUID(uuidString: chosen), lists.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// A list that was chosen and has since been deleted reads as the open list.
    private var name: String {
        lists.first { $0.id == chosenID }?.name ?? "the open list"
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("showing").foregroundStyle(.inkFaded)
            Text(name)
                .foregroundStyle(.ink)
                .lineLimit(1)
                // Pencil dots under a word that can be changed, as under the hours.
                .underline(pattern: .dot, color: .inkFaded)
                .padding(.vertical, 6)
                .contentShape(Rectangle().inset(by: -6))
                .onTapGesture {
                    chosen = WorkHours.nextList(after: chosenID, in: lists.map(\.id))?.uuidString ?? ""
                }
                .haptic(.selection, trigger: chosen)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Live Activity shows")
                .accessibilityValue(name)
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Tap for the next list")
        }
        .typeStyle(.listName)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The working hours, as words under their line: "9 AM to 5 PM". Each hour
/// is changed where it stands. A tap on it brings up the number keys and the
/// hour is typed. A drag across it runs through the hours instead, later to
/// the right and earlier to the left.
private struct HoursLine: View {
    @AppStorage(WorkHours.startKey) private var start = WorkHours.standard.start
    @AppStorage(WorkHours.endKey) private var end = WorkHours.standard.end

    private var hours: WorkHours { WorkHours(start: start, end: end) }
    /// Counts the times the eight-hour limit has just been met. Zero when the note is not showing.
    @State private var capNotes = 0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            HourWord(hour: hours.start, name: "Starts", which: .start) {
                set(hours.steppingStart(by: $0))
            } typed: {
                set(hours.typingStart($0, afternoon: HourEntry.shared.afternoon))
            }
            Text("to").foregroundStyle(.inkFaded)
            HourWord(hour: hours.end, name: "Ends", which: .end) {
                set(hours.steppingEnd(by: $0))
            } typed: {
                set(hours.typingEnd($0, afternoon: HourEntry.shared.afternoon))
            }
            // Said for a moment when one end has pushed the other along.
            if capNotes > 0 {
                Text("eight hours at most")
                    .typeStyle(.monthLabel)
                    .foregroundStyle(.inkFaded)
                    .transition(.opacity)
            }
        }
        // The note fades by the changes below, not by an animation laid over
        // the whole line: over an hour being typed, that kept the app from
        // ever coming to rest, and a UI test waited a minute at every step.
        .typeStyle(.listName)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func set(_ new: WorkHours) {
        // Both ends moved and the hours are at their longest: one was pushed along by the other.
        if new.start != start, new.end != end, new.length == WorkHours.longest {
            withAnimation(.quick) { capNotes += 1 }
            let shown = capNotes
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if capNotes == shown { withAnimation(.quick) { capNotes = 0 } }
            }
        }
        start = new.start
        end = new.end
    }
}

private struct HourWord: View {
    let hour: Int
    /// What VoiceOver calls it.
    let name: String
    let which: HourEntry.Which
    /// Moves the hour on or back by a number of hours.
    let step: (Int) -> Void
    /// A number was typed for the hour.
    let typed: (Int) -> Void

    /// Hours already stepped through in the drag under way.
    @State private var dragged = 0
    @State private var isTyping = false
    @State private var digits = ""
    @FocusState private var isFocused: Bool
    /// How far a finger travels for each hour.
    private static let perHour: CGFloat = 24

    var body: some View {
        if isTyping {
            field
        } else {
            word
        }
    }

    private var word: some View {
        Text(WorkHours.name(ofHour: hour))
            .foregroundStyle(.ink)
            // Pencil dots under a word that can be changed, as on the first page.
            .underline(pattern: .dot, color: .inkFaded)
            .contentTransition(.numericText(value: Double(hour)))
            .animation(.quick, value: hour)
            .padding(.vertical, 6)
            .contentShape(Rectangle().inset(by: -6))
            .onTapGesture {
                digits = ""
                isTyping = true
                isFocused = true
                HourEntry.shared.begin(which)
            }
            .onHorizontalDrag { value in
                let wanted = Int((value.translation.width / Self.perHour).rounded(.towardZero))
                if wanted != dragged {
                    step(wanted - dragged)
                    dragged = wanted
                }
            } onEnded: { _ in
                dragged = 0
            }
            .haptic(.selection, trigger: hour)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(name)
            .accessibilityValue(WorkHours.name(ofHour: hour))
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Tap to type the hour")
            .accessibilityAdjustableAction { direction in
                step(direction == .increment ? 1 : -1)
            }
    }

    /// The hour being typed: one or two digits. It is kept as soon as it can
    /// only be one hour, so most hours take a single key.
    private var field: some View {
        TextField("", text: $digits, prompt: Text(WorkHours.name(ofHour: hour)).foregroundStyle(.inkFaded))
            #if os(iOS)
            .keyboardType(.numberPad)
            #endif
            .foregroundStyle(.ink)
            .fixedSize()
            .padding(.vertical, 6)
            .focused($isFocused)
            .accessibilityLabel(name)
            .onChange(of: digits) { _, new in
                let clean = String(new.filter(\.isNumber).prefix(2))
                if clean != new { digits = clean }
                guard let number = Int(clean) else { return }
                // "1" and "2" may be the start of 10 to 23. Anything else is whole.
                if clean.count == 2 || number > 2 {
                    keep()
                } else {
                    let waited = clean
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.5))
                        if isTyping, digits == waited { keep() }
                    }
                }
            }
            .onChange(of: isFocused) { _, focused in if !focused { keep() } }
            // "done", above the keys.
            .onChange(of: HourEntry.shared.dones) { _, _ in keep() }
            .onDisappear {
                if let number = Int(digits) { typed(number) }
                HourEntry.shared.end(which)
            }
    }

    private func keep() {
        guard isTyping else { return }
        let number = Int(digits)
        isTyping = false
        isFocused = false
        digits = ""
        if let number { typed(number) }
        HourEntry.shared.end(which)
    }
}

/// The hour being typed, if one is. The words above the keys read it: they
/// stand at the bottom of the page, apart from the settings lines.
@MainActor
@Observable
final class HourEntry {
    static let shared = HourEntry()

    enum Which { case start, end }

    private(set) var typing: Which?
    /// The half of the day asked for with AM or PM while typing this hour.
    var afternoon: Bool?
    /// Counts presses of "done".
    var dones = 0
    /// Something else that is not a line of the page is being typed, such as
    /// the user's name on the share lines. The page leaves the keys with it.
    var isWritingElsewhere = false

    func begin(_ which: Which) {
        typing = which
        afternoon = nil
    }

    func end(_ which: Which) {
        guard typing == which else { return }
        typing = nil
        afternoon = nil
    }
}

/// Above the number keys while an hour is typed: AM and PM to say which half
/// of the day is meant, and "done". On a twenty-four-hour clock, only "done".
struct HourEntryWords: View {
    let which: HourEntry.Which

    @AppStorage(WorkHours.startKey) private var start = WorkHours.standard.start
    @AppStorage(WorkHours.endKey) private var end = WorkHours.standard.end

    private var hours: WorkHours { WorkHours(start: start, end: end) }
    private var isAfternoon: Bool { (which == .start ? hours.start : hours.end) >= 12 }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 28) {
            if WorkHours.clockIsTwelveHour {
                half(Calendar.current.amSymbol, afternoon: false)
                half(Calendar.current.pmSymbol, afternoon: true)
            }
            Spacer(minLength: 0)
            BottomWord(word: "done") { HourEntry.shared.dones += 1 }
        }
        .haptic(.selection, trigger: isAfternoon)
    }

    private func half(_ word: String, afternoon: Bool) -> some View {
        BottomWord(word: word, isFaded: isAfternoon != afternoon) {
            HourEntry.shared.afternoon = afternoon
            let new = which == .start ? hours.start(afternoon: afternoon) : hours.end(afternoon: afternoon)
            start = new.start
            end = new.end
        }
        .accessibilityAddTraits(isAfternoon == afternoon ? .isSelected : [])
    }
}
