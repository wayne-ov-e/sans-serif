import SwiftUI

/// The three places the paper rests, and how it goes between them.
///
/// Settings, the page and the archive stand at -1, 0 and 1, and one number
/// says where the paper is between them. A finger moves that number directly,
/// point for point; let go, one spring carries it to the next place, starting
/// at the finger's own speed and never passing where it is going. A finger
/// that comes down while it is still moving takes it from where it is.
///
/// Before, a pull was read off the scrolling as it went past an edge, and the
/// paper was held, countered and pinned to cover what the scrolling did
/// meanwhile. That grew patch on patch (Wayne, Nov 22, 2026: "Rethink how
/// this is implemented completely, my goal is to implement glitch free
/// fluidity with the animation, where it feels analogue. This is getting
/// overly complex and clumsy now"). Here there is no scrolling to listen to
/// between the places, so nothing to detect and nothing to correct.
///
/// It is plain data, apart from the views, so that it can be tested.
struct Deck: Equatable {
    static let settings: CGFloat = -1
    static let page: CGFloat = 0
    static let archive: CGFloat = 1
    static let stops: [CGFloat] = [settings, page, archive]

    /// How briskly the paper comes to its place: the spring's response, in
    /// seconds. 0.38 at first; then 0.28 ("a bit more stronger snap feeling",
    /// Wayne, Nov 22, 2026); then eased by 15 percent ("15% less strong snap
    /// for the animation to add a bit more cushioning for up and down swiping").
    /// With the archive brought nearer that was "a bit too snappy now, still
    /// need the natural feeling", so: 0.38 again, over the shorter way.
    static var response: Double { 0.38 }
    /// A finger let go faster than this, in points a second, has flicked.
    /// 150 and 60 at first; raised when Wayne asked to "make swipe a bit
    /// more harder to trigger" (Nov 22, 2026).
    static let flick: CGFloat = 220
    /// Let go slowly, the paper still goes on if it was moved this far.
    static let carry: CGFloat = 80
    /// How far a finger must go before the paper goes with it, and how much
    /// more up or down than sideways it must be going. 10 points and any
    /// drag steeper than a diagonal at first.
    static let reluctance: CGFloat = 18
    static let steepness: CGFloat = 1.6
    /// Past settings or past the archive the paper gives, less and less the
    /// further it is asked: at first about this much of what the finger
    /// asks, and never more than `reach` however far the finger goes. The
    /// curve is the one a list's own edge follows under a finger.
    static let give: CGFloat = 0.55
    static let reach: CGFloat = 140
    /// However hard the flick, the paper takes at least this long a spring to arrive.
    static var quickest: Double { 0.28 }

    /// How far the page moves down for settings, and how far up for the archive.
    var settingsHeight: CGFloat
    var height: CGFloat

    /// How far the paper travels between the page and the archive, on a
    /// screen this tall. Not the whole screen, as it was at first: that was
    /// three times as far as settings come, and took the snap out of it
    /// (Wayne, Nov 22, 2026: "archive coming up feels like a long distance
    /// to travel which takes away the snapiness"). The page goes up this far
    /// and pales away as it goes; the archive comes up this far, out of nothing.
    /// A third of the screen at first, which with the spring of the time was
    /// too abrupt; a little under half now.
    static func travel(screen: CGFloat) -> CGFloat {
        min(max(screen * 0.45, 260), 420)
    }

    /// How much of its ink the page has left, and the archive has yet, with
    /// the archive `up` of the way: the page is gone a little before the
    /// archive is whole, so the two are never both strong on the same paper.
    static func pageInk(up: CGFloat) -> Double {
        Double(1 - min(max(up / 0.5, 0), 1))
    }

    static func archiveInk(up: CGFloat) -> Double {
        Double(min(max((up - 0.35) / 0.65, 0), 1))
    }

    /// A place as a distance in points from the page, and back: a point of
    /// the finger is a point of the paper on either side of the page.
    func points(_ place: CGFloat) -> CGFloat {
        place < 0 ? place * max(settingsHeight, 1) : place * max(height, 1)
    }

    func place(points: CGFloat) -> CGFloat {
        points < 0 ? points / max(settingsHeight, 1) : points / max(height, 1)
    }

    /// Where the paper is under a finger that took it at `grabbed` and has
    /// moved `translation` points (down is positive). `low` and `high` are the
    /// places that finger may take it to: toward a side that is not open to
    /// it the paper does not move, and past settings or the archive it gives a little.
    func dragged(from grabbed: CGFloat, by translation: CGFloat, low: CGFloat, high: CGFloat) -> CGFloat {
        var to = points(grabbed) - translation
        let lowest = points(low), highest = points(high)
        if to < lowest { to = low < 0 ? lowest - Self.eased(lowest - to) : lowest }
        if to > highest { to = high > 0 ? highest + Self.eased(to - highest) : highest }
        return place(points: to)
    }

    /// How far the paper gives when asked to go `asked` points past its last place.
    static func eased(_ asked: CGFloat) -> CGFloat {
        (1 - 1 / (asked * give / reach + 1)) * reach
    }

    /// Where the paper goes when the finger lets go. A flick goes one place
    /// on, and so does a slow drag that moved it far enough; anything less
    /// goes back. Caught on its way somewhere and sent on the same way, it
    /// counts from where it was going, so two flicks go two places.
    /// `speed` is the finger's, in points a second, up being positive.
    func target(
        now: CGFloat, grabbed: CGFloat, heading: CGFloat, inFlight: Bool, speed: CGFloat,
        low: CGFloat = Deck.settings, high: CGFloat = Deck.archive
    ) -> CGFloat {
        let moved = points(now) - points(grabbed)
        let flicked = abs(speed) > Self.flick
        var target: CGFloat
        if flicked || abs(moved) > Self.carry {
            let up = flicked ? speed > 0 : moved > 0
            let onward = inFlight && (heading - grabbed) * (up ? 1 : -1) > 0
            let base = onward ? heading : now
            let slack: CGFloat = onward ? 0.02 : -0.02
            target = up
                ? (Self.stops.first { $0 > base + slack } ?? Self.archive)
                : (Self.stops.last { $0 < base - slack } ?? Self.settings)
        } else {
            target = now.rounded()
        }
        return min(max(target, low), high)
    }

    /// The spring that carries the paper from `now` to `target`. It is
    /// critically damped, so it eases in to its place and never passes it,
    /// and it starts at the finger's own speed, so nothing changes pace at
    /// the moment of letting go. A flick too fast for the usual spring to
    /// take up without passing its place gets a quicker spring, not a slower
    /// start: a harder flick arrives sooner, as a thing thrown harder does
    /// (Wayne, Nov 22, 2026: "run easing functions for the scroll, whatever
    /// feels more natural and fluid").
    func spring(from now: CGFloat, to target: CGFloat, speed: CGFloat = 0) -> Animation {
        let pace = Self.pace(from: points(now), to: points(target), speed: speed)
        let distance = points(target) - points(now)
        let start = abs(distance) > 1 ? max(Double(speed / distance), 0) : 0
        return .interpolatingSpring(mass: 1, stiffness: pace * pace, damping: 2 * pace, initialVelocity: min(start, pace * 0.98))
    }

    /// How quick a spring it takes: the usual one, or quicker for a flick
    /// that would carry the paper past its place, down to `quickest`.
    static func pace(from: CGFloat, to: CGFloat, speed: CGFloat) -> Double {
        let usual = 2 * Double.pi / response
        let distance = to - from
        guard abs(distance) > 1 else { return usual }
        // A critically damped spring passes its place when it starts faster than pace times the distance.
        let needed = Double(speed / distance) * 1.02
        return min(max(usual, needed), 2 * Double.pi / quickest)
    }
}

/// Where the paper is seen at this moment, while it moves by itself: the only
/// place that can be read by a finger that catches it on its way.
@MainActor final class DeckFlight {
    var place: CGFloat = 0
}

/// Where the paper is, or is going. Read by the three things it places and by
/// nothing else, so that moving it does not have the page looked over again.
@MainActor @Observable final class DeckPaper {
    var place: CGFloat = 0
}

/// Puts one of the three things on the paper where `DeckPaper` says.
struct DeckPlaced: ViewModifier {
    let part: DeckPart.Part
    let paper: DeckPaper
    let deck: Deck
    var reduceMotion = false
    var reduceTransparency = false
    var flight: DeckFlight?

    func body(content: Content) -> some View {
        content.modifier(DeckPart(
            part: part, place: paper.place, deck: deck, reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency, flight: flight
        ))
    }
}

/// One of the three things on the paper, put where the one number says.
struct DeckPart: ViewModifier, Animatable {
    enum Part { case settings, page, archive }

    let part: Part
    var place: CGFloat
    let deck: Deck
    var reduceMotion = false
    var reduceTransparency = false
    var flight: DeckFlight?

    nonisolated var animatableData: CGFloat {
        get { place }
        set { place = newValue }
    }

    /// Never quite nothing. What has no ink at all, or next to none, is left
    /// out of what VoiceOver is told, and on iOS 18 is not put back when the
    /// ink returns in the course of a movement: the archive, arrived, could
    /// not be found there. Whether each is there to be found is said
    /// outright, where it is placed, by what is showing. One part in a
    /// hundred is as little as iOS 18 takes for something: with a thousandth
    /// the archive was still not found. So that this trace of ink is never
    /// seen at rest, what is wholly away is also put far off the paper.
    nonisolated static let floor = 0.011
    nonisolated static let farOff: CGFloat = 4000
    /// As good as away: the last fiftieth of the way, which the spring takes
    /// some time over, and through which the trace of ink could just be made out.
    nonisolated static let nearly: CGFloat = 0.02

    nonisolated static func seen(_ ink: Double) -> Double {
        max(ink, floor)
    }

    /// How blurred and how pale the page is with settings all the way down.
    nonisolated static let blur: CGFloat = 4.5
    nonisolated static let paleness = 0.4

    func body(content: Content) -> some View {
        flight?.place = place
        // How far settings are down, and how far the archive is up.
        let down = max(-place, 0)
        let up = max(place, 0)
        return Group {
            switch part {
            case .settings:
                content
                    // They come down from above the page by their own height.
                    .offset(y: reduceMotion ? 0 : (down - 1) * deck.settingsHeight)
                    .opacity(Self.seen(Double(min(down, 1))))
            case .page:
                content
                    // The page pales and blurs by how far settings have come:
                    // there is no moment at which it switches. With Reduce
                    // Transparency the blur is left out and it only pales.
                    .blur(radius: reduceTransparency ? 0 : Self.blur * min(down, 1))
                    .opacity(Self.seen((1 - Self.paleness * min(down, 1)) * Deck.pageInk(up: up)))
                    // Settings push it down; the archive sends it up and out.
                    .offset(y: down * deck.settingsHeight - (reduceMotion ? 0 : up * deck.height) - (up > 1 - Self.nearly ? Self.farOff : 0))
            case .archive:
                content
                    .offset(y: (reduceMotion ? 0 : (1 - up) * deck.height) + (up < Self.nearly ? Self.farOff : 0))
                    .opacity(Self.seen(Deck.archiveInk(up: up)))
            }
        }
    }
}
