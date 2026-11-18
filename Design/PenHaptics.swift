import Foundation
#if os(iOS)
import CoreHaptics
#endif

/// The feel of a pen crossing paper, for a drag across a line.
///
/// A strike is one continuous texture, not a row of taps: a firm landing, a
/// rumble that follows the speed of the hand and thins toward the end of the
/// line, one crisp click where letting go will count, and a light flick on the
/// lift. A drag that is let go too early ends with a small soft tap instead.
///
/// Only iPhone can play this. Every method returns `false` where it cannot,
/// or when Haptics is struck in settings, so the caller can fall back to the
/// plain taps in `Haptics.swift` or stay quiet.
@MainActor
final class PenHaptics {
    static let shared = PenHaptics()

    /// Haptics is on in settings.
    private var isOn: Bool {
        UserDefaults.standard.object(forKey: Setting.haptics.key) as? Bool ?? Setting.haptics.defaultValue
    }

    #if os(iOS)
    private let isSupported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var texture: CHHapticAdvancedPatternPlayer?

    /// Whether the continuous pen can be played here and now.
    var isAvailable: Bool { isSupported && isOn }

    private func ready() -> CHHapticEngine? {
        guard isAvailable else { return nil }
        if engine == nil {
            guard let made = try? CHHapticEngine() else { return nil }
            made.playsHapticsOnly = true
            made.isAutoShutdownEnabled = true
            Self.watch(made, for: self)
            engine = made
        }
        do {
            try engine?.start()
            return engine
        } catch {
            return nil
        }
    }

    /// The system can stop or reset the engine at any time, and it says so on a
    /// thread of its own. These handlers must not belong to the main actor:
    /// written inside a main-actor method they would, and the app would be
    /// stopped the first time the engine went idle (the crash in build 5).
    /// They only hop to the main actor to do their work.
    private nonisolated static func watch(_ engine: CHHapticEngine, for owner: PenHaptics) {
        engine.stoppedHandler = { @Sendable [weak owner] _ in
            Task { @MainActor in owner?.engineStopped() }
        }
        engine.resetHandler = { @Sendable [weak owner] in
            Task { @MainActor in owner?.engineReset() }
        }
    }

    private func engineStopped() {
        texture = nil
    }

    private func engineReset() {
        texture = nil
        try? engine?.start()
    }

    private func tap(intensity: Float, sharpness: Float, after delay: TimeInterval = 0) -> Bool {
        guard let engine = ready() else { return false }
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: delay
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern)
        else { return false }
        return (try? player.start(atTime: CHHapticTimeImmediate)) != nil
    }

    /// The pen meets the paper, and the texture begins under it.
    @discardableResult
    func land() -> Bool {
        guard let engine = ready() else { return false }
        _ = tap(intensity: 0.7, sharpness: 0.45)
        stopTexture()
        let rumble = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.35),
            ],
            relativeTime: 0.02,
            duration: 30
        )
        if let pattern = try? CHHapticPattern(events: [rumble], parameters: []),
           let player = try? engine.makeAdvancedPlayer(with: pattern) {
            texture = player
            // Still until the pen moves.
            shape(intensity: 0, sharpness: 0)
            try? player.start(atTime: CHHapticTimeImmediate)
        }
        return true
    }

    /// The pen moves. `speed` is in points per second; `along` is how far
    /// along the line it is, from 0 to 1.
    @discardableResult
    func move(speed: Double, along: Double) -> Bool {
        guard isAvailable, texture != nil else { return false }
        // The drag itself is the faintest part of a strike: a whisper under the
        // finger for a slow line, a little more for a quick one.
        let intensity = speed < 4 ? 0 : min(max(0.12 + speed / 2600, 0.12), 0.42)
        // Grainier where the pen lands, smoother as the ink runs out.
        let sharpness = 0.1 - 0.3 * min(max(along, 0), 1)
        shape(intensity: Float(intensity), sharpness: Float(sharpness))
        return true
    }

    private func shape(intensity: Float, sharpness: Float) {
        try? texture?.sendParameters([
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: intensity, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .hapticSharpnessControl, value: sharpness, relativeTime: 0),
        ], atTime: CHHapticTimeImmediate)
    }

    /// The point of no return was passed (`armed`), or the pen came back under it.
    @discardableResult
    func click(armed: Bool) -> Bool {
        armed ? tap(intensity: 0.8, sharpness: 0.85) : tap(intensity: 0.35, sharpness: 0.2)
    }

    /// The pen lifts at the end of a line that counted. A quick line flicks off harder.
    /// `extraLines` are the further lines of a long task, drawn for the user one after another.
    @discardableResult
    func lift(speed: Double, extraLines: Int = 0, every interval: TimeInterval = 0.16) -> Bool {
        stopTexture()
        let flick = Float(min(max(0.25 + speed / 2800, 0.25), 0.6))
        guard tap(intensity: flick, sharpness: 0.6) else { return false }
        for line in 0..<max(extraLines, 0) {
            _ = tap(intensity: 0.3, sharpness: 0.5, after: interval * Double(line + 1))
        }
        return true
    }

    /// The pen was lifted too early, and the line draws back: this did not count.
    @discardableResult
    func retract() -> Bool {
        stopTexture()
        return tap(intensity: 0.3, sharpness: 0.05)
    }

    /// The drag ended some other way. Nothing more is felt.
    func stop() {
        stopTexture()
    }

    /// A change of view: one short, crisp haptic at the instant the change is
    /// asked for, so the hand feels it as the page starts to move. A tap with a
    /// very short tail, over in about a tenth of a second. Nothing follows it.
    @discardableResult
    func snap() -> Bool {
        guard let engine = ready() else { return false }
        let hit = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6),
            ],
            relativeTime: 0
        )
        let tail = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3),
                CHHapticEventParameter(parameterID: .attackTime, value: 0),
                CHHapticEventParameter(parameterID: .decayTime, value: 0.09),
                CHHapticEventParameter(parameterID: .sustained, value: 0),
            ],
            relativeTime: 0.008,
            duration: 0.09
        )
        guard let pattern = try? CHHapticPattern(events: [hit, tail], parameters: []),
              let player = try? engine.makePlayer(with: pattern)
        else { return false }
        return (try? player.start(atTime: CHHapticTimeImmediate)) != nil
    }

    private func stopTexture() {
        try? texture?.stop(atTime: CHHapticTimeImmediate)
        texture = nil
    }
    #else
    var isAvailable: Bool { false }
    @discardableResult func land() -> Bool { false }
    @discardableResult func move(speed: Double, along: Double) -> Bool { false }
    @discardableResult func click(armed: Bool) -> Bool { false }
    @discardableResult func lift(speed: Double, extraLines: Int = 0, every interval: TimeInterval = 0.16) -> Bool { false }
    @discardableResult func retract() -> Bool { false }
    func stop() {}
    @discardableResult func snap() -> Bool { false }
    #endif
}
