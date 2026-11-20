import SwiftUI

extension View {
    /// Hold a line to pick it up, then drag it. `onChanged` reports how far the
    /// finger has moved since the line was picked up, in window coordinates, so
    /// it stays true while the line itself moves.
    func onLiftDrag(
        isEnabled: Bool = true,
        onBegan: @escaping () -> Void,
        onChanged: @escaping (CGSize) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        #if os(iOS)
        gesture(LiftPress(isEnabled: isEnabled, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded))
        #else
        modifier(LiftDragModifier(isEnabled: isEnabled, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded))
        #endif
    }

    /// A hold that is known while the finger is still down: what it opens is
    /// there the moment the time is up, never only once the finger lifts
    /// (Wayne, Nov 20, 2026).
    func onHold(after seconds: Double = Lift.holdDuration, perform: @escaping () -> Void) -> some View {
        #if os(iOS)
        gesture(LiftPress(isEnabled: true, seconds: seconds, onBegan: perform, onChanged: { _ in }, onEnded: {}))
        #else
        onLongPressGesture(minimumDuration: seconds, perform: perform)
        #endif
    }
}

/// How long a line is held before it lifts.
enum Lift {
    static let holdDuration = 0.35
}

#if os(iOS)
/// A long press that goes on reporting the finger after it has been recognised.
/// Being a UIKit recognizer, it leaves the page free to scroll until it begins.
private struct LiftPress: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    var seconds = Lift.holdDuration
    let onBegan: () -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = seconds
        recognizer.isEnabled = isEnabled
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let point = recognizer.location(in: nil)
        switch recognizer.state {
        case .began:
            context.coordinator.start = point
            onBegan()
        case .changed:
            let start = context.coordinator.start
            onChanged(CGSize(width: point.x - start.x, height: point.y - start.y))
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    final class Coordinator {
        var start: CGPoint = .zero
    }
}
#else
private struct LiftDragModifier: ViewModifier {
    let isEnabled: Bool
    let onBegan: () -> Void
    let onChanged: (CGSize) -> Void
    let onEnded: () -> Void

    @State private var hasBegun = false

    func body(content: Content) -> some View {
        content.gesture(
            LongPressGesture(minimumDuration: Lift.holdDuration)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                .onChanged { value in
                    guard case .second(true, let drag) = value else { return }
                    if !hasBegun {
                        hasBegun = true
                        onBegan()
                    }
                    if let drag { onChanged(drag.translation) }
                }
                .onEnded { _ in
                    if hasBegun { onEnded() }
                    hasBegun = false
                },
            isEnabled: isEnabled
        )
    }
}
#endif
