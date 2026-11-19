import SwiftUI
#if os(iOS)
import UIKit.UIGestureRecognizerSubclass
#endif

/// A drag that set off sideways.
struct HorizontalDragValue {
    var startLocation: CGPoint
    var location: CGPoint
    var translation: CGSize
    /// Points per second.
    var velocity: CGSize
    /// How hard an Apple Pencil has pressed so far, from 0 to 1. `nil` for a finger or a pointer.
    var pressure: Double?
}

extension View {
    /// Follows drags that start out more sideways than up or down, and leaves
    /// vertical drags to the page's scrolling.
    ///
    /// - Parameter followsScroll: also follow a two-finger swipe on a trackpad.
    func onHorizontalDrag(
        followsScroll: Bool = false,
        onChanged: @escaping (HorizontalDragValue) -> Void,
        onEnded: @escaping (HorizontalDragValue) -> Void
    ) -> some View {
        #if os(iOS)
        gesture(HorizontalPan(followsScroll: followsScroll, onChanged: onChanged, onEnded: onEnded))
        #else
        gesture(
            DragGesture(minimumDistance: 6)
                .onChanged { onChanged(HorizontalDragValue($0)) }
                .onEnded { onEnded(HorizontalDragValue($0)) }
        )
        #endif
    }
}

#if os(iOS)
/// A pan that only begins when the finger sets off sideways, so it can sit
/// inside a scroll view without stealing the scroll.
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let followsScroll: Bool
    let onChanged: (HorizontalDragValue) -> Void
    let onEnded: (HorizontalDragValue) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> PenPan {
        let recognizer = PenPan()
        recognizer.delegate = context.coordinator
        recognizer.allowedScrollTypesMask = followsScroll ? .continuous : []
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: PenPan, context: Context) {
        let location = context.converter.localLocation
        // How far and how fast, from the recogniser itself. The converter's
        // own figures cannot be trusted on iOS 18: as a drag begins there it
        // reports a movement to the left for a finger moving right, and a
        // strike was taken for the start of a loop and never drawn.
        let translation = recognizer.translation(in: recognizer.view)
        let velocity = recognizer.velocity(in: recognizer.view)
        let value = HorizontalDragValue(
            startLocation: CGPoint(x: location.x - translation.x, y: location.y - translation.y),
            location: location,
            translation: CGSize(width: translation.x, height: translation.y),
            velocity: CGSize(width: velocity.x, height: velocity.y),
            pressure: recognizer.pressure
        )
        switch recognizer.state {
        case .began, .changed: onChanged(value)
        case .ended, .cancelled, .failed: onEnded(value)
        default: break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            // By the time a pan may begin the finger has already moved a little.
            // Which way it went decides whose drag this is.
            let moved = pan.translation(in: pan.view)
            let velocity = pan.velocity(in: pan.view)
            let dx = moved.x != 0 || moved.y != 0 ? moved.x : velocity.x
            let dy = moved.x != 0 || moved.y != 0 ? moved.y : velocity.y
            return abs(dx) > abs(dy)
        }
    }
}

/// A pan that also notes how hard an Apple Pencil is pressing.
final class PenPan: UIPanGestureRecognizer {
    /// The mean pressure of the drag so far, from 0 to 1. `nil` unless a Pencil is drawing.
    private(set) var pressure: Double?
    private var sum = 0.0
    private var samples = 0

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        sample(touches)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        sample(touches)
    }

    override func reset() {
        super.reset()
        pressure = nil
        sum = 0
        samples = 0
    }

    private func sample(_ touches: Set<UITouch>) {
        guard let touch = touches.first, touch.type == .pencil, touch.maximumPossibleForce > 0 else { return }
        sum += touch.force / touch.maximumPossibleForce
        samples += 1
        pressure = sum / Double(samples)
    }
}
#else
private extension HorizontalDragValue {
    init(_ value: DragGesture.Value) {
        self.init(
            startLocation: value.startLocation,
            location: value.location,
            translation: value.translation,
            velocity: value.velocity
        )
    }
}
#endif
