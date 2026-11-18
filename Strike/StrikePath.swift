import SwiftUI

/// Where one line of text sits, as far as the pen is concerned.
struct StrikeLine: Hashable, Sendable {
    /// Left edge of the text.
    var minX: CGFloat
    /// Right edge of the text.
    var maxX: CGFloat
    /// The middle of the lowercase letters.
    var midY: CGFloat
    var xHeight: CGFloat
    /// Half the nominal pen width for this text size.
    var halfWidth: CGFloat

    func offsetBy(dx: CGFloat, dy: CGFloat) -> StrikeLine {
        var line = self
        line.minX += dx
        line.maxX += dx
        line.midY += dy
        return line
    }
}

/// Turns a stroke into the filled shape of a pen line: a small rounded start,
/// a swell just after landing, a thinner middle, and a taper to a point on the lift.
enum StrikePath {
    static func startX(_ stroke: Stroke, on line: StrikeLine) -> CGFloat {
        line.minX - stroke.leadIn
    }

    static func endX(_ stroke: Stroke, on line: StrikeLine) -> CGFloat {
        line.maxX + stroke.leadOut
    }

    /// The centre of the pen at `t`, from 0 at the landing to 1 at the lift.
    static func centre(_ stroke: Stroke, on line: StrikeLine, at t: CGFloat) -> CGPoint {
        let start = startX(stroke, on: line)
        let x = start + (endX(stroke, on: line) - start) * t
        let phase = phase(stroke, 1)
        let wobble = 0.022 * sin(t * 6.5 + phase) + 0.012 * sin(t * 15 + phase * 1.7)
        let y = line.midY
            - line.xHeight * stroke.lift
            - line.xHeight * stroke.rise * (t - 0.5)
            + line.xHeight * stroke.sag * 4 * t * (1 - t)
            + line.xHeight * wobble
        return CGPoint(x: x, y: y)
    }

    /// Half the thickness of the line at `t`.
    static func halfWidth(_ stroke: Stroke, on line: StrikeLine, at t: CGFloat) -> CGFloat {
        let landing = 0.8 + 0.2 * smoothstep(0, 0.035, t)
        let swell = 0.3 * exp(-pow((t - 0.08) / 0.06, 2))
        let middle = -0.14 * exp(-pow((t - 0.56) / 0.26, 2))
        let taper = t < 0.76 ? 1 : pow(max(0, (1 - t) / 0.24), 0.8)
        let grain = 1 + 0.05 * sin(t * 21 + phase(stroke, 2))
        return line.halfWidth * stroke.weight * (landing + swell + middle) * taper * grain
    }

    /// The filled outline of the line, drawn from the landing as far as `progress` (0 to 1).
    static func path(_ stroke: Stroke, on line: StrikeLine, progress: CGFloat = 1) -> Path {
        let progress = min(max(progress, 0), 1)
        guard progress > 0 else { return Path() }

        let length = (endX(stroke, on: line) - startX(stroke, on: line)) * progress
        let steps = max(6, Int(length / 2.5))
        var upper: [CGPoint] = []
        var lower: [CGPoint] = []
        for step in 0...steps {
            let t = progress * CGFloat(step) / CGFloat(steps)
            let centre = centre(stroke, on: line, at: t)
            let half = halfWidth(stroke, on: line, at: t)
            upper.append(CGPoint(x: centre.x, y: centre.y - half))
            lower.append(CGPoint(x: centre.x, y: centre.y + half))
        }

        var path = Path()
        path.move(to: upper[0])
        upper.dropFirst().forEach { path.addLine(to: $0) }
        // While the pen is still down the end is round. At the lift the taper
        // has already brought it to a point.
        addCap(to: &path, around: centre(stroke, on: line, at: progress),
               radius: halfWidth(stroke, on: line, at: progress), facing: 1)
        lower.reversed().forEach { path.addLine(to: $0) }
        addCap(to: &path, around: centre(stroke, on: line, at: 0),
               radius: halfWidth(stroke, on: line, at: 0), facing: -1)
        path.closeSubpath()
        return path
    }

    /// A half circle, from the upper edge round to the lower (facing 1, the end)
    /// or the lower round to the upper (facing -1, the start).
    private static func addCap(to path: inout Path, around centre: CGPoint, radius: CGFloat, facing: CGFloat) {
        guard radius > 0.05 else { return }
        let steps = 6
        for step in 1..<steps {
            let angle = -CGFloat.pi / 2 + CGFloat.pi * CGFloat(step) / CGFloat(steps)
            path.addLine(to: CGPoint(
                x: centre.x + facing * radius * cos(angle),
                y: centre.y + facing * radius * sin(angle)
            ))
        }
    }

    private static func phase(_ stroke: Stroke, _ salt: UInt64) -> CGFloat {
        var random = SplitMix64(seed: stroke.seed ^ (salt &* 0xD1B5_4A32_D192_ED03))
        return .random(in: 0...(2 * .pi), using: &random)
    }

    private static func smoothstep(_ a: CGFloat, _ b: CGFloat, _ x: CGFloat) -> CGFloat {
        let t = min(max((x - a) / (b - a), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
