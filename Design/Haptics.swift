import SwiftUI

extension View {
    /// Plays a haptic when `trigger` changes, unless Haptics is struck in settings.
    /// `when` can hold it back for some changes, such as a value going back to `nil`.
    func haptic<Trigger: Equatable>(
        _ feedback: SensoryFeedback,
        trigger: Trigger,
        when condition: @escaping (Trigger) -> Bool = { _ in true }
    ) -> some View {
        modifier(Haptic(feedback: feedback, trigger: trigger, condition: condition))
    }
}

extension SensoryFeedback {
    /// The pen landing: a strike, a setting, a menu opening.
    static let pen = SensoryFeedback.impact(weight: .light)
    /// A line lifting off again: an undone strike, a page settling.
    static let lift = SensoryFeedback.impact(weight: .light, intensity: 0.7)
    /// A line picked up off the page.
    static let pickUp = SensoryFeedback.impact(weight: .light)
    /// A line put down, or something removed.
    static let putDown = SensoryFeedback.impact(weight: .light, intensity: 0.8)
    /// The pen dragging across paper: felt as it lands and again and again along
    /// the line, where the continuous pen cannot be played.
    static let drag = SensoryFeedback.impact(weight: .light, intensity: 0.6)
    /// The pen leaving the paper at the end of a drag. The drag was the event; this is quiet.
    static let release = SensoryFeedback.impact(weight: .light, intensity: 0.4)
    /// A sheet set moving, where the crisp haptic cannot be played: one tap as it goes.
    static let detent = SensoryFeedback.impact(weight: .light)
    /// A page set turning, where the crisp haptic cannot be played: one tap as it goes.
    static let turn = SensoryFeedback.impact(weight: .light)
    /// The edge of the paper: there is no page further that way.
    static let edge = SensoryFeedback.impact(weight: .light, intensity: 0.7)
}

/// Counts the moments of a drag that should be felt: the landing, and each
/// stretch of the line the pen passes, in either direction.
struct DragTicks: Equatable {
    private(set) var count = 0
    private var stretch = 0

    /// How many times a full line is felt, the landing aside.
    static let perLine = 6

    mutating func land() {
        stretch = 0
        count += 1
    }

    /// `fraction` is how far along the line the pen is, from 0 to 1.
    mutating func move(to fraction: Double) {
        let now = Int(fraction * Double(Self.perLine))
        if now != stretch {
            stretch = now
            count += 1
        }
    }
}

extension View {
    /// A sheet that comes or goes is felt once, at the instant the pull counts:
    /// short and crisp, as the sheet starts to move.
    /// `quietly`: the sheet is put away by something that is felt already, a
    /// turn to another list, and says nothing of its own.
    func sheetHaptics(_ isShowing: Bool, quietly: Bool = false) -> some View {
        modifier(SheetHaptics(isShowing: isShowing, quietly: quietly))
    }
}

private struct SheetHaptics: ViewModifier {
    let isShowing: Bool
    var quietly = false
    /// Counted where the crisp haptic cannot be played, for one plain tap instead.
    @State private var taps = 0

    func body(content: Content) -> some View {
        content
            .haptic(.detent, trigger: taps)
            .onChange(of: isShowing) {
                guard !quietly else { return }
                if !PenHaptics.shared.snap() { taps += 1 }
            }
    }
}

private struct Haptic<Trigger: Equatable>: ViewModifier {
    let feedback: SensoryFeedback
    let trigger: Trigger
    let condition: (Trigger) -> Bool

    @AppStorage(Setting.haptics.key) private var isOn = Setting.haptics.defaultValue

    func body(content: Content) -> some View {
        content.sensoryFeedback(trigger: trigger) { _, new in
            isOn && condition(new) ? feedback : nil
        }
    }
}
