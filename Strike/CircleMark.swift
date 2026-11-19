import SwiftUI

/// A loop drawn round a task by hand: this is the one that matters.
///
/// Like a strike, it is never quite the same twice. The pen sets off above the
/// words, goes once round them, and runs a little past where it began, so the
/// ends cross instead of meeting. The seed makes a task's loop the same every time.
struct CircleLoop: Shape {
    /// The words it goes round.
    var words: CGRect
    var seed: UInt64

    nonisolated func path(in rect: CGRect) -> Path {
        var random = SplitMix64(seed: seed)
        let start = Double.random(in: -2.5 ... -1.9, using: &random)
        let overlap = Double.random(in: 0.35...0.6, using: &random)
        let lean = Double.random(in: -0.035...0.035, using: &random)
        let phase = Double.random(in: 0...(2 * .pi), using: &random)
        let drift = Double.random(in: 0.08...0.13, using: &random)
        let radiusX = words.width / 2 + 11
        let radiusY = words.height / 2 + 5
        let steps = 96
        var path = Path()
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let angle = start + t * (2 * .pi + overlap)
            // The hand wanders, and the loop opens as it goes, so the end passes outside the start.
            let wobble = 1 + 0.045 * sin(2 * angle + phase) + 0.02 * sin(3 * angle - phase) + drift * (t - 0.5)
            let x = radiusX * wobble * cos(angle)
            let y = radiusY * wobble * sin(angle)
            let point = CGPoint(
                x: words.midX + x - y * lean,
                y: words.midY + y + x * lean
            )
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// The loop round a task, drawn or lifted as `progress` goes between 0 and 1.
struct CircleMark: View {
    var lines: [StrikeLine]
    var seed: UInt64
    var progress: Double
    var color: Color = .ink

    @Environment(\.colorScheme) private var colorScheme

    /// The box the words stand in, from the top of the first line's tall letters to below the last.
    static func words(_ lines: [StrikeLine]) -> CGRect? {
        guard let first = lines.first, let last = lines.last else { return nil }
        let minX = lines.map(\.minX).min() ?? first.minX
        let maxX = lines.map(\.maxX).max() ?? first.maxX
        let top = first.midY - first.xHeight * 1.25
        let bottom = last.midY + last.xHeight * 1.05
        return CGRect(x: minX, y: top, width: maxX - minX, height: bottom - top)
    }

    var body: some View {
        if let words = Self.words(lines), progress > 0 {
            CircleLoop(words: words, seed: seed)
                .trim(from: 0, to: progress)
                .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                .blendMode(colorScheme == .dark ? .screen : .multiply)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
