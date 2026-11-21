import SwiftUI

/// Pencil, not ink: a small faded dot where the finger lands and a dotted path
/// to follow (brief: First run, The guide marks). The dot pulses once and the
/// path draws itself once, then both rest. After five seconds they play again.
struct GuidePath: View {
    /// Where the finger lands, and where it goes, in the view's own space.
    let from: CGPoint
    let to: CGPoint

    static let dotSize: CGFloat = 8
    static let style = StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [0.01, 6.5])

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: from)
                path.addLine(to: to)
            }
            .trim(from: 0, to: drawn)
            .stroke(Color.inkFaded, style: Self.style)

            Circle()
                .fill(Color.inkFaded)
                .frame(width: Self.dotSize, height: Self.dotSize)
                .scaleEffect(pulse ? 1.7 : 1)
                .position(from)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .guidePlayback(reduceMotion: reduceMotion, drawn: $drawn, pulse: $pulse)
    }
}

/// A dotted ring: tap here, or hold here.
struct GuideRing: View {
    var diameter: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drawn: CGFloat = 0
    @State private var pulse = false

    var body: some View {
        Circle()
            .trim(from: 0, to: drawn)
            .stroke(Color.inkFaded, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [2.5, 3.5]))
            .rotationEffect(.degrees(-90))
            .frame(width: diameter, height: diameter)
            .scaleEffect(pulse ? 1.25 : 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .guidePlayback(reduceMotion: reduceMotion, drawn: $drawn, pulse: $pulse)
    }
}

private extension View {
    /// Plays a guide once, and again every five seconds while it is on the page.
    /// With Reduce Motion the guide is simply there.
    func guidePlayback(reduceMotion: Bool, drawn: Binding<CGFloat>, pulse: Binding<Bool>) -> some View {
        task {
            guard !reduceMotion else {
                drawn.wrappedValue = 1
                return
            }
            while !Task.isCancelled {
                drawn.wrappedValue = 0
                withAnimation(.easeOut(duration: 0.18)) { pulse.wrappedValue = true }
                try? await Task.sleep(for: .seconds(0.18))
                withAnimation(.settle) { pulse.wrappedValue = false }
                withAnimation(.easeInOut(duration: 0.7)) { drawn.wrappedValue = 1 }
                try? await Task.sleep(for: .seconds(5.7))
            }
        }
    }
}

/// The guide for a gesture made on the empty paper: a swipe to the side, a pull
/// up, a pull down. It stands in the paper below the lines.
struct GuideGesture: View {
    enum Kind { case sideways, up, down }
    let kind: Kind
    /// How long this one's dotted path is. Shorter where the page is nearly full.
    var length: CGFloat = GuideGesture.length

    /// How long the dotted path is, as in Figma frame 10 First run: Pull up.
    static let length: CGFloat = 150

    var body: some View {
        GeometryReader { proxy in
            let middle = proxy.size.width / 2
            let half = GuidePath.dotSize / 2
            switch kind {
            case .sideways:
                // Right to left: the next list is to the right, and the page is pulled over.
                GuidePath(
                    from: CGPoint(x: middle + Self.length / 2, y: proxy.size.height / 2),
                    to: CGPoint(x: middle - Self.length / 2, y: proxy.size.height / 2)
                )
            case .up:
                GuidePath(
                    from: CGPoint(x: middle, y: length - half),
                    to: CGPoint(x: middle, y: half)
                )
            case .down:
                GuidePath(
                    from: CGPoint(x: middle, y: half),
                    to: CGPoint(x: middle, y: length - half)
                )
            }
        }
        .frame(height: kind == .sideways ? 44 : length)
        .transition(.opacity)
    }
}
