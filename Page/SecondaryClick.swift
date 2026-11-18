import SwiftUI

extension View {
    /// A right click, or a click with two fingers on a trackpad. It opens the
    /// same menu a long press does (brief: Interaction model).
    func onSecondaryClick(perform action: @escaping () -> Void) -> some View {
        #if os(iOS)
        gesture(SecondaryTap(action: action))
        #else
        overlay(SecondaryClickCatcher(action: action))
        #endif
    }
}

#if os(iOS)
/// The secondary button of a mouse or trackpad on iPad. Fingers never trigger it.
private struct SecondaryTap: UIGestureRecognizerRepresentable {
    let action: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UITapGestureRecognizer {
        let recognizer = UITapGestureRecognizer()
        recognizer.buttonMaskRequired = .secondary
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UITapGestureRecognizer, context: Context) {
        if recognizer.state == .ended { action() }
    }
}
#else
/// A view that lies over a line and is only there for a right click, or a
/// click with Control held. Every other click passes through it.
private struct SecondaryClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> Catcher {
        let view = Catcher()
        view.action = action
        return view
    }

    func updateNSView(_ view: Catcher, context: Context) {
        view.action = action
    }

    final class Catcher: NSView {
        var action: (() -> Void)?

        private func isSecondary(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            return event.type == .rightMouseDown
                || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            isSecondary(NSApp.currentEvent) ? super.hitTest(point) : nil
        }

        override func rightMouseDown(with event: NSEvent) {
            action?()
        }

        override func mouseDown(with event: NSEvent) {
            if isSecondary(event) { action?() } else { super.mouseDown(with: event) }
        }
    }
}
#endif
