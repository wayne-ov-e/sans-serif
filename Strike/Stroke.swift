import Foundation

/// One pass of the pen through one line of text.
///
/// A stroke is stored as a handful of numbers, not as points, so the same line
/// can be redrawn at any text size, in the archive, and on other devices.
/// A task keeps one stroke per line of text.
struct Stroke: Codable, Hashable, Sendable {
    /// Drives the small irregularities that make no two strikes alike.
    var seed: UInt64
    /// How far the line starts before the text, in points.
    var leadIn: Double
    /// How far the line runs past the text, in points.
    var leadOut: Double
    /// How much the line climbs from start to end, as a fraction of the x-height.
    /// Negative falls.
    var rise: Double
    /// How much the middle of the line droops, as a fraction of the x-height.
    var sag: Double
    /// How far the line sits above the middle of the lowercase letters, as a
    /// fraction of the x-height.
    var lift: Double
    /// Thickness as a multiple of the nominal pen width.
    var weight: Double
}

extension Stroke {
    /// The brief asks for 4 to 13 pt of overshoot on each side.
    static let overshoot = 4.0...13.0
    static let riseLimit = 0.3
    static let liftLimit = 0.16
    static let weightRange = 0.85...1.25
    /// An Apple Pencil can press much lighter and much harder than a finger's speed suggests.
    static let pencilWeightRange = 0.7...1.8

    /// The thickness of a line drawn with an Apple Pencil, from how hard it
    /// pressed, 0 to 1. Ordinary writing presses at about a quarter of the most
    /// the Pencil can report, and gives a line a little over the nominal width.
    static func weight(forPressure pressure: Double) -> Double {
        (0.6 + pressure * 2.2).clamped(to: pencilWeightRange)
    }

    /// A line from a seeded random variation of tilt, weight and overshoot.
    /// Used for strikes made by keyboard, VoiceOver and widgets.
    static func generated(seed: UInt64) -> Stroke {
        var random = SplitMix64(seed: seed)
        return Stroke(
            seed: seed,
            leadIn: .random(in: 4...9, using: &random),
            leadOut: .random(in: 5...13, using: &random),
            rise: .random(in: -0.2...0.2, using: &random),
            sag: .random(in: -0.06...0.12, using: &random),
            lift: .random(in: -0.07...0.07, using: &random),
            weight: .random(in: 0.9...1.18, using: &random)
        )
    }

    /// A line that takes its height, tilt and weight from the drag that made it.
    ///
    /// - Parameters:
    ///   - lift: where the finger landed, above the middle of the lowercase, in x-heights.
    ///   - slope: how steeply the finger set off, as rise over run.
    ///   - speed: how fast it set off, in points per second. A slow pen leaves more ink.
    static func drawn(seed: UInt64, lift: Double, slope: Double, speed: Double) -> Stroke {
        var stroke = generated(seed: seed)
        stroke.lift = lift.clamped(to: -liftLimit...liftLimit)
        // A finger wanders far more than a pen does, so only part of its slope is kept.
        stroke.rise = (stroke.rise * 0.5 + slope * 2).clamped(to: -riseLimit...riseLimit)
        stroke.weight = (1.3 - speed / 2200).clamped(to: weightRange)
        return stroke
    }

    /// One stroke per line of a task, each its own pass of the pen.
    static func generated(lines: Int, seed: UInt64) -> [Stroke] {
        (0..<max(lines, 0)).map { generated(seed: lineSeed(seed, line: $0)) }
    }

    /// The seed for a later line of the same task.
    static func lineSeed(_ seed: UInt64, line: Int) -> UInt64 {
        seed &+ UInt64(line) &* 0x9E37_79B9_7F4A_7C15
    }

    static func encode(_ strokes: [Stroke]) -> Data? {
        try? JSONEncoder().encode(strokes)
    }

    static func decode(_ data: Data?) -> [Stroke] {
        guard let data else { return [] }
        return (try? JSONDecoder().decode([Stroke].self, from: data)) ?? []
    }
}

extension TaskItem {
    /// The pen lines stored with a struck task, one per line of text.
    var strokes: [Stroke] { Stroke.decode(strokeData) }

    /// Strokes for the number of lines the task wraps to here. Text can wrap
    /// differently from the device that struck it, so missing lines are made
    /// up from the task's own identity and always come out the same.
    func strokes(forLines count: Int) -> [Stroke] {
        let stored = strokes
        let seed = stored.first?.seed ?? UInt64(truncatingIfNeeded: id.hashValueStable)
        return (0..<count).map { line in
            line < stored.count ? stored[line] : .generated(seed: Stroke.lineSeed(seed, line: line + 7))
        }
    }
}

private extension UUID {
    /// A hash that is the same on every launch and every device.
    var hashValueStable: UInt64 {
        withUnsafeBytes(of: uuid) { bytes in
            bytes.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// A small seeded generator, so a seed always gives the same line.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
