import SwiftUI

/// How things move. Everything is quick to start, and paper and lines settle
/// the way a real sheet does: a short spring, never a slow ease. The pen itself
/// is not here: a strike is drawn at the speed of the hand (see `TaskLine`).
extension Animation {
    /// A whole sheet coming or going: the archive, settings. It has some weight
    /// and comes to rest without going past. Damping was 0.84, then 0.92;
    /// Wayne found it still sprang too much (Nov 21, 2026), so now none.
    static let sheet = Animation.spring(response: sheetResponse, dampingFraction: 1)
    static let sheetResponse: Double = {
        #if DEBUG
        // To watch two sheets move at once, by hand, in the simulator.
        if ProcessInfo.processInfo.arguments.contains("-slowSheets") { return 1.9 }
        #endif
        return 0.38
    }()
    /// The page turning to another list. Quick, and it stops dead: no bounce
    /// when the next page arrives.
    static let turn = Animation.spring(response: 0.32, dampingFraction: 1)
    /// A turn across more than one list takes a little longer, so the pages in
    /// between are not rushed past: 0.32 s for one page, 0.38 s for two or more.
    static func turn(across pages: CGFloat) -> Animation {
        .spring(response: turnTime(across: pages), dampingFraction: 1)
    }

    /// The same turn, set off by a finger that was already moving the page:
    /// it goes on at the finger's speed. `speed` is in pages a second, towards
    /// the page turned to; `pages` is how far there is still to go.
    static func turn(across pages: CGFloat, atSpeed speed: CGFloat) -> Animation {
        guard pages > 0.02 else { return turn(across: pages) }
        // The spring counts speed in whole journeys a second. Never backwards,
        // and never so fast that the page is thrown past its place.
        let journeys = min(max(speed / pages, 0), 14)
        return .interpolatingSpring(duration: turnTime(across: pages), bounce: 0, initialVelocity: journeys)
    }

    static func turnTime(across pages: CGFloat) -> Double {
        0.32 + 0.06 * Double(min(max(pages - 1, 0), 1))
    }

    /// Ink changing, and one whole view giving way to another: a short spring
    /// with no bounce, in place of the plain eases these once were.
    static let ink = Animation.smooth(duration: 0.25)
    /// Something let go that falls back into place: a page not turned, a line put down.
    static let settle = Animation.spring(response: 0.28, dampingFraction: 0.74)
    /// Lines making room or closing up after one leaves.
    static let shuffle = Animation.spring(response: 0.3, dampingFraction: 0.86)
    /// Small things that should simply be there: a menu, ink changing on a name.
    static let quick = Animation.snappy(duration: 0.18)
}

#if os(iOS)
import QuartzCore

/// Asks the display for its full rate while something on the page is moving.
///
/// An iPhone with a 120 Hz display runs most of the time at 60 and only goes
/// faster when asked. Measured on Wayne's iPhone 18 Pro with Instruments
/// (build 29, Nov 22, 2026): the page turning and the sheets moved at 60
/// frames a second, with the display at 120 for three half-second bursts in
/// nine seconds of use. A display link that prefers 120 is how an app asks;
/// it does no drawing of its own, and it is taken down a moment after the
/// last thing that moved, so the display can rest again.
@MainActor
final class FullRate: NSObject {
    static let shared = FullRate()

    private var link: CADisplayLink?
    private var until: CFTimeInterval = 0

    /// Something has begun to move, or is still moving: hold the full rate
    /// for this long from now.
    func hold(for seconds: Double = 0.9) {
        until = max(until, CACurrentMediaTime() + seconds)
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        FrameTrace.began()
    }

    @objc private func tick() {
        if let link { FrameTrace.note(link.timestamp) }
        guard CACurrentMediaTime() > until else { return }
        link?.invalidate()
        link = nil
    }
}
#else
/// The Mac's display keeps its own rate.
@MainActor
final class FullRate {
    static let shared = FullRate()
    func hold(for seconds: Double = 0.9) {}
}
#endif

/// With `-traceFrames` in a development build on a phone, the moments the
/// display was refreshed while something moved are written to
/// `Documents/frames.log`: a line a second with how many frames there were
/// and the longest wait between two, and a line for each late frame saying
/// what had last happened and how long before. For reading off a phone what
/// the simulator cannot show, which runs at 60.
@MainActor enum FrameTrace {
    #if DEBUG && os(iOS)
    private static let isOn = ProcessInfo.processInfo.arguments.contains("-traceFrames")
    private static var last: CFTimeInterval = 0
    private static var second = 0
    private static var frames = 0
    private static var longest = 0.0
    private static var late = 0
    private static var marked = ""
    private static var markedAt: CFTimeInterval = 0
    #endif

    /// Something happened that a late frame might be put down to.
    static func mark(_ name: String) {
        #if DEBUG && os(iOS)
        guard isOn else { return }
        marked = name
        markedAt = CACurrentMediaTime()
        #endif
    }

    /// The display is asked for its full rate again after a rest: the wait
    /// since the last frame was the rest, not a late frame.
    static func began() {
        #if DEBUG && os(iOS)
        last = 0
        #endif
    }

    static func note(_ time: CFTimeInterval) {
        #if DEBUG && os(iOS)
        guard isOn else { return }
        let gap = time - last
        if Int(time) != second {
            if frames > 0 { write("\(second) frames \(frames) longest \(String(format: "%.1f", longest * 1000)) ms over12ms \(late)") }
            second = Int(time)
            frames = 0
            longest = 0
            late = 0
        }
        if last > 0, gap < 0.5 {
            longest = max(longest, gap)
            if gap > 0.012 {
                late += 1
                write(String(format: "  late %.1f ms, %.0f ms after %@", gap * 1000, (last - markedAt) * 1000, marked))
            }
        }
        frames += 1
        last = time
        #endif
    }

    #if DEBUG && os(iOS)
    private static func write(_ line: String) {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("frames.log")
        let data = (line + "\n").data(using: .utf8)!
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url)
        }
    }
    #endif
}
