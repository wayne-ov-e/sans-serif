import SwiftUI

/// How things move. Everything is quick to start, and paper and lines settle
/// the way a real sheet does: a short spring, never a slow ease. The pen itself
/// is not here: a strike is drawn at the speed of the hand (see `TaskLine`).
extension Animation {
    /// A whole sheet coming or going: the archive, settings. It has some weight
    /// and settles once at the end. Damping was 0.84; Wayne asked for slightly
    /// less bounce (Nov 19, 2026). At 1 there would be none at all.
    static let sheet = Animation.spring(response: 0.38, dampingFraction: 0.92)
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
