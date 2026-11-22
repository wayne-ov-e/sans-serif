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

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsGap) {
            SettingLine(name: "Show counts", setting: Setting.showCounts, seed: 11)
            SettingLine(name: "iCloud sync", setting: Setting.iCloudSync, seed: 23)
            SettingLine(name: "Haptics", setting: Setting.haptics, seed: 37)
            SettingLine(name: "Dark paper", setting: Setting.darkPaper, seed: 41)
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
            .animation(.ink, value: isOn)
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

/// Something that is not a line of the page is being typed, such as the
/// user's name on the share lines. The page leaves the keys with it, and its
/// "done" is told here.
@MainActor
@Observable
final class KeysElsewhere {
    static let shared = KeysElsewhere()

    /// Counts presses of "done".
    var dones = 0
    var isWritingElsewhere = false
}

/// Privacy and Contact, small and faded in the bottom left corner while
/// settings are down: there for whoever looks, and out of the way of the
/// settings themselves (Wayne, Nov 21, 2026: "in small texts. inconspicuous").
struct SettingsFootnotes: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.pageMetrics) private var metrics

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            ForEach(AppLinks.shown, id: \.word) { link in
                Button {
                    Tap.word()
                    openURL(link.url)
                } label: {
                    Text(link.word)
                        .typeStyle(.count)
                        .foregroundStyle(.inkFaded)
                        .frame(minHeight: metrics.minTouchHeight, alignment: .bottom)
                        .contentShape(Rectangle().inset(by: -9))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens in the browser")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
