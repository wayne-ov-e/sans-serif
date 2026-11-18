import SwiftUI

/// The pen lines over a task, one per line of text.
///
/// `progress` counts lines: 0 is clean paper, 1 is the first line fully struck,
/// 1.5 is half way through the second. Animating it draws the lines one after
/// another, top to bottom, and lifts them in reverse.
struct StrikeMarks: View, @preconcurrency Animatable {
    var lines: [StrikeLine]
    var strokes: [Stroke]
    var progress: Double
    /// Ink on the live page, faded ink in the archive.
    var color: Color = .ink

    @Environment(\.colorScheme) private var colorScheme

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    /// Room around the text for the overshoot and the soft edge.
    private static let margin: CGFloat = 20

    var body: some View {
        Canvas { context, _ in
            for (index, line) in lines.enumerated() where index < strokes.count {
                let drawn = min(max(progress - Double(index), 0), 1)
                guard drawn > 0 else { continue }
                let stroke = strokes[index]
                let line = line.offsetBy(dx: Self.margin, dy: Self.margin)
                let path = StrikePath.path(stroke, on: line, progress: drawn)

                // The soft edge where ink bleeds into paper.
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 0.9))
                    layer.opacity = 0.5
                    layer.fill(path, with: .color(color))
                }
                context.fill(path, with: .color(color.opacity(0.9)))

                // The darker pool where the pen landed.
                let landing = StrikePath.centre(stroke, on: line, at: 0.012)
                let radius = StrikePath.halfWidth(stroke, on: line, at: 0.03) * 1.15
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 0.5))
                    layer.fill(
                        Path(ellipseIn: CGRect(
                            x: landing.x - radius * 1.3, y: landing.y - radius,
                            width: radius * 2.6, height: radius * 2
                        )),
                        with: .color(color)
                    )
                }
            }
        }
        .padding(-Self.margin)
        // Wet ink darkens where it crosses the letters. On dark paper the ink
        // is the light colour, so it lightens them instead.
        .blendMode(colorScheme == .dark ? .screen : .multiply)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension StrikeLine {
    /// The lines of a laid-out `Text`, in the coordinate space of `proxy`.
    static func measure(_ layouts: Text.LayoutKey.Value, in proxy: GeometryProxy) -> [StrikeLine] {
        layouts.flatMap { anchored in
            let origin = proxy[anchored.origin]
            return anchored.layout.map { line in
                let bounds = line.typographicBounds
                let height = bounds.ascent + bounds.descent
                let xHeight = height * SerifFont.xHeightRatio
                let minX = origin.x + bounds.origin.x
                return StrikeLine(
                    minX: minX,
                    maxX: minX + bounds.width,
                    midY: origin.y + bounds.origin.y - xHeight / 2,
                    xHeight: xHeight,
                    halfWidth: height * 0.036
                )
            }
        }
    }
}

#if DEBUG
/// The strike on its own, for tuning the pen without the rest of the app.
private struct StrikeGallery: View {
    @State private var progress = 3.0
    @State private var seed: UInt64 = 1

    private let samples = [
        "Call the framer", "Renew passport", "Water the fig tree",
        "Pick up the dry cleaning before the shop closes on Saturday afternoon",
        "Fix", "Write to Grandma",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Array(samples.enumerated()), id: \.offset) { index, sample in
                Text(sample)
                    .typeStyle(.task)
                    .foregroundStyle(.inkFaded)
                    .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                        GeometryReader { proxy in
                            let lines = StrikeLine.measure(layouts, in: proxy)
                            StrikeMarks(
                                lines: lines,
                                strokes: Stroke.generated(lines: lines.count, seed: seed &+ UInt64(index) &* 977),
                                progress: progress
                            )
                        }
                    }
            }
            Spacer()
            Slider(value: $progress, in: 0...3)
            Button("New strokes") { seed = .random(in: 0...UInt64.max) }
        }
        .padding(32)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.paper)
    }
}

#Preview("Strikes") {
    StrikeGallery()
}
#endif
