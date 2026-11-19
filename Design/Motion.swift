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
    /// Something let go that falls back into place: a page not turned, a line put down.
    static let settle = Animation.spring(response: 0.28, dampingFraction: 0.74)
    /// Lines making room or closing up after one leaves.
    static let shuffle = Animation.spring(response: 0.3, dampingFraction: 0.86)
    /// Small things that should simply be there: a menu, ink changing on a name.
    static let quick = Animation.snappy(duration: 0.18)
}
