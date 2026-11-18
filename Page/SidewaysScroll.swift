#if os(macOS)
import SwiftUI

extension View {
    /// Follows a two-finger swipe to the side on a trackpad, the way a drag is
    /// followed on iPhone. Distances are in points, speed in points per second.
    func onSidewaysScroll(
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping (CGFloat, CGFloat) -> Void
    ) -> some View {
        background(SidewaysScrollWatcher(onChanged: onChanged, onEnded: onEnded))
    }
}

private struct SidewaysScrollWatcher: NSViewRepresentable {
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat, CGFloat) -> Void

    func makeNSView(context: Context) -> Watcher {
        let view = Watcher()
        view.onChanged = onChanged
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ view: Watcher, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
    }

    /// Watches the scroll events of its own window. A swipe that sets off
    /// sideways is taken from the page; one that sets off up or down is left
    /// to the page's scrolling.
    final class Watcher: NSView {
        var onChanged: ((CGFloat) -> Void)?
        var onEnded: ((CGFloat, CGFloat) -> Void)?

        private var monitor: Any?
        /// Which way the swipe in progress set off. `nil` until it has moved.
        private var isSideways: Bool?
        private var total: CGFloat = 0
        private var speed: CGFloat = 0
        private var lastTime: TimeInterval = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, self.take(event) else { return event }
                return nil
            }
        }

        /// True when the event belonged to a sideways swipe and has been used.
        private func take(_ event: NSEvent) -> Bool {
            // Only a trackpad swipe has phases. A mouse wheel has none, and neither does momentum.
            guard event.window === window, !event.phase.isEmpty else { return false }

            if event.phase.contains(.began) {
                isSideways = nil
                total = 0
                speed = 0
                lastTime = event.timestamp
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                let wasSideways = isSideways == true
                isSideways = nil
                if wasSideways { onEnded?(total, speed) }
                return wasSideways
            }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            if isSideways == nil, dx != 0 || dy != 0 {
                isSideways = abs(dx) > abs(dy)
            }
            guard isSideways == true else { return false }

            total += dx
            let elapsed = max(event.timestamp - lastTime, 1.0 / 240)
            // Smoothed a little, so one late event does not decide a flick.
            speed = speed * 0.4 + (dx / elapsed) * 0.6
            lastTime = event.timestamp
            onChanged?(total)
            return true
        }
    }
}
#endif
