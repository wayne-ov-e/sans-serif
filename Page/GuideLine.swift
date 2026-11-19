import SwiftUI

/// One line of the first page. It is written in when it appears, and struck
/// when what it says has been done.
struct GuideLine: View {
    let text: String
    let isStruck: Bool
    /// The same pen line every time.
    let seed: UInt64
    /// "Cross me off.": the line is struck by dragging across it, with a dotted path to follow.
    var strikesByDrag = false
    /// A dotted ring on the line: hold here.
    var showsRing = false
    /// "Circle what matters.": a loop drawn round the line circles it, with a dotted loop to follow.
    var circlesByDrag = false
    var isCircled = false
    var strikeColor: Color = .ink
    /// Lines in the archive are simply there.
    var writesIn = true
    var onStruckByDrag: () -> Void = {}
    var onCircled: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lines: [StrikeLine] = []
    /// Lines struck so far. See `StrikeMarks`.
    @State private var progress = 0.0
    @State private var isDragging = false
    /// How much of the line has been written in, from 0 to 1.
    @State private var written: CGFloat = 0
    @State private var ticks = DragTicks()
    @State private var isArmed = false
    /// Where the finger has been while it draws a loop.
    @State private var loop: [CGPoint] = []
    /// How much of the loop round the line is drawn, from 0 to 1.
    @State private var circled = 0.0

    private var strokes: [Stroke] { Stroke.generated(lines: max(lines.count, 1), seed: seed) }

    var body: some View {
        Text(text)
            .typeStyle(.task)
            .foregroundStyle(isStruck ? .inkFaded : .ink)
            .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                GeometryReader { proxy in
                    let measured = StrikeLine.measure(layouts, in: proxy)
                    StrikeMarks(lines: measured, strokes: strokes, progress: progress, color: strikeColor)
                        .onChange(of: measured, initial: true) { _, new in
                            lines = new
                            if isStruck, !isDragging { progress = Double(new.count) }
                        }
                    CircleMark(lines: measured, seed: seed &+ 5, progress: circled)
                    if circlesByDrag, !isCircled, let words = CircleMark.words(measured) {
                        // Pencil, not ink: the way round.
                        CircleLoop(words: words, seed: seed &+ 5)
                            .stroke(Color.inkFaded, style: GuidePath.style)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                    if let line = measured.first, !isStruck {
                        if strikesByDrag {
                            // When the finger starts across, the guide fades and ink takes over.
                            GuidePath(
                                from: CGPoint(x: line.minX - 14, y: line.midY),
                                to: CGPoint(x: line.maxX + 26, y: line.midY)
                            )
                            .opacity(progress > 0 ? 0 : 1)
                            .animation(.quick, value: progress > 0)
                        }
                        if showsRing {
                            GuideRing(diameter: 30)
                                .position(x: line.minX + 26, y: line.midY)
                        }
                    }
                }
            }
            // Written in from the left, as if by hand.
            .mask {
                Rectangle()
                    .padding(-28)
                    .scaleEffect(x: written, anchor: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onHorizontalDrag(onChanged: dragChanged, onEnded: dragEnded)
            .haptic(.drag, trigger: ticks)
            .animation(.easeOut(duration: 0.25), value: isStruck)
            .onAppear {
                guard writesIn, !reduceMotion else {
                    written = 1
                    return
                }
                withAnimation(.easeOut(duration: 0.45).delay(0.12)) { written = 1 }
            }
            .onChange(of: isCircled, initial: true) { old, new in
                withAnimation(old != new && !reduceMotion ? .easeOut(duration: 0.42) : nil) { circled = new ? 1 : 0 }
            }
            // Struck for the user, when the step was done somewhere else on the page.
            .onChange(of: isStruck) { _, struck in
                if struck, !isDragging { draw(to: Double(max(lines.count, 1))) }
                // Done is done: the circle goes with the strike.
                if struck { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { circled = 0 } }
            }
    }

    private func dragChanged(_ value: HorizontalDragValue) {
        if circlesByDrag, !isCircled {
            if loop.isEmpty { loop = [value.startLocation] }
            loop.append(value.location)
            return
        }
        guard strikesByDrag, !isStruck, let line = lines.first, let stroke = strokes.first,
              value.translation.width > 2 || isDragging
        else { return }
        if !isDragging, !PenHaptics.shared.land() { ticks.land() }
        isDragging = true
        let start = StrikePath.startX(stroke, on: line)
        let end = StrikePath.endX(stroke, on: line)
        let reach = ((value.location.x - start) / (end - start)).clamped(to: 0...1)
        progress = reach * (value.translation.width / 28).clamped(to: 0...1)
        let farEnough = value.translation.width >= min((line.maxX - line.minX) * 0.4, 90)
        let armed = progress >= 0.6 && farEnough
        if !PenHaptics.shared.move(speed: abs(value.velocity.width), along: progress) { ticks.move(to: progress) }
        if armed != isArmed {
            isArmed = armed
            PenHaptics.shared.click(armed: armed)
        }
    }

    private func dragEnded(_ value: HorizontalDragValue) {
        if circlesByDrag, !isCircled {
            if TaskLine.closes(loop + [value.location]) { onCircled() }
            loop = []
            return
        }
        guard isDragging, let line = lines.first else { return }
        let farEnough = value.translation.width >= min((line.maxX - line.minX) * 0.4, 90)
        isArmed = false
        if progress >= 0.6, farEnough {
            PenHaptics.shared.lift(speed: abs(value.velocity.width))
            draw(to: Double(max(lines.count, 1)))
            onStruckByDrag()
        } else {
            PenHaptics.shared.retract()
            draw(to: 0)
        }
        // The line is struck a moment later; until then it is still this drag's.
        Task { @MainActor in isDragging = false }
    }

    private func draw(to target: Double) {
        let duration = abs(target - progress) * TaskLine.secondsPerLine
        withAnimation(reduceMotion || duration == 0 ? nil : .easeOut(duration: duration)) {
            progress = target
        }
    }
}
