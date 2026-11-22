import SwiftUI
import QuartzCore

/// The sheet of paper: a single column of text on the paper background.
///
/// On narrow windows the column fills the width inside the margins. On wide
/// windows it stops growing at a reading width and sits centred, with empty
/// paper on both sides. The footer (the list names) sits at the bottom of the
/// column, on its left edge.
///
/// The content scrolls when it is taller than the page, and runs on underneath
/// the list names, where lines marked `fadesUnderListNames()` blur and fade.
/// A page that fits does not move.
struct PageColumn<Header: View, Content: View, Archive: View, Footer: View>: View {
    /// Which page this is. A new page starts at its top and fades in over the old one.
    var pageID: AnyHashable = 0
    /// Hidden while the keyboard is up.
    var showsFooter = true
    /// The archive is showing instead of the page.
    var showsArchive = false
    /// The header (settings) is showing above the page, and the page has receded.
    var showsHeader = false
    /// A menu is open on the list names, or on a task: the other part of the page recedes.
    var contentReceded = false
    var footerReceded = false
    /// The footer holds words for what is being typed in the header, and stays in reach.
    var footerStaysClear = false
    /// The page holds still while a line is being carried.
    var scrollDisabled = false
    /// Something else has the page: a line being written, a menu, tasks
    /// picked out. Settings and the archive stay where they are meanwhile.
    var sheetsHeld = false
    /// A tap on the paper that no line of text claimed, beside the column included.
    var onTapPaper: (() -> Void)?
    /// How far the page has been turned, as a fraction of its width: -1 is
    /// fully off to the left, 1 fully off to the right.
    var turn: CGFloat = 0
    /// The other lists' pages, standing beside this one in a row. They are
    /// always there, off the edge of the paper, so a turn has nothing to wait for.
    var strip: [StripPage] = []
    /// A turn has landed: the page turned to lies exactly where the real one
    /// is about to be, and covers it until it has been laid out.
    var stripCovers = false
    /// Where this page is told to keep note of how far it has turned, frame by
    /// frame, so that a finger can catch the row of pages while it is moving.
    var flight: TurnFlight?
    /// A sideways drag turns the page wherever it starts. Off, only one that
    /// starts at the bottom of the page does.
    var turnsAnywhere = false
    /// A sideways drag that no task claimed, as a fraction of the page width.
    var onTurnChanged: ((CGFloat) -> Void)?
    /// The drag was let go: how far it went, and its speed in page widths per second.
    var onTurnEnded: ((CGFloat, CGFloat) -> Void)?
    /// A new task is being written at the end of the page: the page keeps
    /// that line just above the list names' place, where it is best seen
    /// (Wayne, Nov 19, 2026).
    var followsEnd = false
    /// Changes whenever the end of the page moves while it is followed: a
    /// task was added, or the line being written grew or shrank.
    var endKey = 0
    /// The page was dragged up past its end.
    var onPullPastEnd: (() -> Void)?
    /// The archive was dragged down past its top.
    var onPullPastTop: (() -> Void)?
    /// A drag up (true) or down made while the page was turning, when neither
    /// sheet is there to be pulled. See `turnPull`.
    var onPullWhileTurning: ((Bool) -> Void)?
    /// The page has been scrolled down from its top, or is back at it.
    var onScrolled: ((Bool) -> Void)?
    /// Lines that come down from the top edge and push the page down.
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    /// What is done. It lies below the page: it comes up from the bottom edge.
    @ViewBuilder var archive: Archive
    @ViewBuilder var footer: Footer

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var footerHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    /// The archive is laid out, on the page or off its bottom edge.
    @State private var archiveMounted = false
    /// Settings are on the paper, showing or out of sight above it. They are
    /// at first, to be measured, and then only while they are wanted.
    @State private var headerMounted = true
    @State private var headerRests = 0
    /// Where the paper is, or is going: settings at -1, the page at 0, the
    /// archive at 1. See `Deck`.
    ///
    /// It is kept apart from this view's own state, and read only by the
    /// three things it places (`DeckPlaced`): under a finger it changes on
    /// every frame, and as state of this view each change had the whole
    /// column, the page's lines and all, looked over again.
    @State private var paper = DeckPaper()
    /// Where it was last sent.
    @State private var heading: CGFloat = 0
    /// Where the paper is seen while it moves by itself, for a finger to take it from.
    @State private var deckFlight = DeckFlight()
    /// Where it was when the finger now on it came down. Nothing, with no finger on it.
    @State private var grabbed: CGFloat?
    /// That finger caught it on its way somewhere.
    @State private var grabbedInFlight = false
    /// The places that finger may take it to.
    @State private var deckLow: CGFloat = 0
    @State private var deckHigh: CGFloat = 0
    /// How far the finger had gone when it was first heard of, which is not counted.
    @State private var deckSlip: CGFloat = 0
    /// Where the drag began that was last looked at, taken or not: once each.
    @State private var deckStart: CGPoint?
    /// A finger is down in a drag. Up again without a word, the drag was
    /// taken away by something else, and the paper is sent to its place.
    @GestureState private var deckTouching = false
    /// The page stands at its top, at its end: both, when all of it is in view.
    @State private var pageEdges = SheetEdges()
    @State private var archiveEdges = SheetEdges()
    /// Where the drag began that was last counted as a pull during a turn: once each.
    @State private var turnPullStart: CGPoint?
    /// Counts the times the page was asked to follow its end, so that only the last is carried out.
    @State private var followings = 0

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets
            let metrics = PageMetrics.resolve(
                width: proxy.size.width + insets.leading + insets.trailing,
                horizontalSizeClass: horizontalSizeClass,
                verticalSizeClass: verticalSizeClass
            )
            let bottomInset = metrics.bottomInset(safeArea: insets.bottom)
            // The strip at the bottom of the page that belongs to the list names.
            let footerZone = bottomInset + (showsFooter ? footerHeight : 0)
            let deck = Deck(
                settingsHeight: headerHeight + metrics.settingsToPageGap,
                height: Deck.travel(screen: proxy.size.height + insets.top + insets.bottom)
            )

            ZStack(alignment: .bottom) {
                GeometryReader { viewport in
                    // The sheet fills the page and no more, so a page that fits does not
                    // scroll. The scroll view reaches up under the status bar and insets
                    // its content by that much, which is taken off here.
                    let minHeight = viewport.size.height - viewport.safeAreaInsets.bottom - scrollTopInset(insets)
                    let width = viewport.size.width
                    let height = viewport.size.height
                    ZStack(alignment: .top) {
                        // The page is always here, and settings above it and the
                        // archive below: nothing is put in or taken out as they
                        // come and go, so each only ever moves. One number places
                        // all three: see `Deck`.
                        ScrollViewReader { scroll in
                        sheet(
                            content
                                .receded(contentReceded)
                                // Under settings the page is out of reach: a tap on it puts them away.
                                .allowsHitTesting(!showsHeader)
                                .accessibilityHidden(showsHeader),
                            metrics: metrics, footerZone: footerZone, minHeight: minHeight, edges: $pageEdges
                        )
                            .scrollDismissesKeyboard(.interactively)
                            // With a finger moving the paper between its places, the
                            // page's own scrolling keeps out of it.
                            .scrollDisabled(scrollDisabled || grabbed != nil)
                            .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y + $0.contentInsets.top > 1 } action: { _, scrolled in
                                onScrolled?(scrolled)
                            }
                            .id(pageID)
                            .transition(.opacity)
                            .modifier(DeckPlaced(
                                part: .page, paper: paper, deck: deck, reduceMotion: reduceMotion,
                                reduceTransparency: reduceTransparency, flight: deckFlight
                            ))
                            .allowsHitTesting(!showsArchive)
                            .accessibilityHidden(showsArchive)
                            // The line being written is brought to the best place: when
                            // the pen is put to it, when the keyboard has changed how much
                            // of the page shows, and each time the end of the page moves.
                            .onChange(of: EndInView(follows: followsEnd, key: endKey, height: height)) { old, new in
                                guard new.follows, !showsHeader, !showsArchive else { return }
                                // Several of these come at once: a task is added, the
                                // keyboard's bar of suggestions comes and goes with every
                                // line. The page is moved once, when they have passed, so
                                // that the keys being typed meanwhile are not kept waiting.
                                followings += 1
                                let mine = followings
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(60))
                                    guard mine == followings, followsEnd else { return }
                                    withAnimation(reduceMotion ? nil : .quick) { scroll.scrollTo(Self.endID, anchor: .bottom) }
                                }
                            }
                        }

                        // Settings, above the page, on the same left edge. They are
                        // only on the paper while they show or are on their way: left
                        // there out of sight they were still read out by VoiceOver,
                        // whatever was said about hiding them.
                        if headerMounted || showsHeader {
                            column(header, metrics: metrics)
                                .fixedSize(horizontal: false, vertical: true)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                                    headerHeight = $0
                                    restHeader()
                                }
                                .padding(.top, metrics.topInset)
                                .modifier(DeckPlaced(part: .settings, paper: paper, deck: deck, reduceMotion: reduceMotion))
                                .allowsHitTesting(showsHeader)
                        }

                        // The archive is laid out a moment before it is wanted and kept
                        // until it has gone, so it too only ever moves.
                        if archiveMounted {
                            sheet(
                                archive.there(showsArchive), metrics: metrics, footerZone: footerZone, minHeight: minHeight,
                                edges: $archiveEdges
                            )
                                .scrollDisabled(grabbed != nil)
                                .id(pageID)
                                .modifier(DeckPlaced(part: .archive, paper: paper, deck: deck, reduceMotion: reduceMotion))
                                .allowsHitTesting(showsArchive)
                        }
                    }
                    // The page follows the finger and pales as it leaves.
                    .modifier(TurnedPage(x: turn, width: width, isCovered: stripCovers, flight: flight))
                    // Each other page darkens to full ink as it comes to the middle.
                    ForEach(strip) { page in
                        sheet(page.view, metrics: metrics, footerZone: footerZone, minHeight: minHeight)
                            .scrollDisabled(true)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .modifier(TurnedPage(x: page.x, width: width))
                    }
                }
                // The page runs to the bottom edge, underneath the list names.
                .ignoresSafeArea(.container, edges: .bottom)

                if showsFooter {
                    column(footer, metrics: metrics)
                        .receded((showsHeader || footerReceded) && !footerStaysClear)
                        .animation(.sheet, value: showsHeader)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                        .padding(.bottom, bottomInset)
                        .transition(.opacity)
                }
            }
            // A sideways drag turns to the next list only when it starts at the
            // bottom of the page, on the list names or the paper around them.
            // Higher up, a sideways drag belongs to the lines: it strikes.
            .contentShape(Rectangle())
            .onHorizontalDrag(followsScroll: true) { value in
                guard turnsAnywhere || value.startLocation.y >= proxy.size.height - footerZone - Self.turnZoneSlack else { return }
                // Once the page is turning it follows the finger, wherever the finger wanders.
                onTurnChanged?(value.translation.width / max(proxy.size.width, 1))
            } onEnded: { value in
                guard turnsAnywhere || value.startLocation.y >= proxy.size.height - footerZone - Self.turnZoneSlack else { return }
                let width = max(proxy.size.width, 1)
                onTurnEnded?(value.translation.width / width, value.velocity.width / width)
            }
            // Given only while a turn is on its way. Not judged by where the
            // row stands: with the real page sliding in, the row is already
            // counted as arrived, and only its picture is still moving.
            .simultaneousGesture(turnPull, including: onPullWhileTurning != nil ? .all : .subviews)
            #if os(macOS)
            // A two-finger swipe to the side turns the page the same way.
            .onSidewaysScroll { distance in
                onTurnChanged?(distance / max(proxy.size.width, 1))
            } onEnded: { distance, speed in
                let width = max(proxy.size.width, 1)
                onTurnEnded?(distance / width, speed / width)
            }
            #endif
            .coordinateSpace(.named(PageSpace.name))
            .environment(\.pageMetrics, metrics)
            .environment(\.listNamesTop, showsFooter ? proxy.size.height - footerZone : nil)
            .animation(.quick, value: showsFooter)
            // A finger moves the paper between its three places.
            .simultaneousGesture(deckDrag(deck))
            .onChange(of: deckTouching) { _, touching in
                // The drag was taken away without ending: the paper goes to the nearest place.
                if !touching, let grabbed {
                    self.grabbed = nil
                    settle(deck.target(now: paper.place, grabbed: grabbed, heading: heading, inFlight: false, speed: 0), deck: deck)
                }
            }
            // A pen has gone to a line, or a menu has opened, with the paper
            // already under the finger: it is let go, back to where it was.
            .onChange(of: sheetsHeld) { _, held in
                guard held, grabbed != nil else { return }
                grabbed = nil
                place(heading, animation: deck.spring(from: paper.place, to: heading))
            }
            // Settings or the archive asked for or put away by something other
            // than the finger: a menu, a tap on the page, a turn to another list.
            .onChange(of: wanted, initial: true) { old, new in
                guard new != heading || paper.place != new else { return }
                heading = new
                restHeader()
                // Put away by a turn to another list: that list's page is
                // simply there, under the one that slid in. Brought down from
                // above like a page coming back from its own archive, it was
                // still pale and on its way when the cover came off, and the
                // text blinked (Wayne, Nov 20, 2026).
                let still = old == Deck.archive && (stripCovers || turn != 0)
                if still || reduceMotion && old == new {
                    place(new, animation: nil)
                } else if (new == Deck.archive && !archiveMounted) || (new == Deck.settings && !headerMounted) {
                    // Laid out off the page first, then brought on from there.
                    if new == Deck.archive { archiveMounted = true } else { headerMounted = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(16))
                        if heading == new { place(new, animation: deck.spring(from: paper.place, to: new)) }
                    }
                } else {
                    place(new, animation: deck.spring(from: deckFlight.place, to: new))
                }
            }
            // Another list's page: it stands where this one was asked to.
            // Its archive is not laid out in the middle of the turn: that
            // comes when the page has been still for a moment.
            .onChange(of: pageID) {
                heading = wanted
                place(wanted, animation: nil)
                restHeader()
                if wanted != Deck.archive { archiveMounted = false }
                layArchiveOutWhenStill()
            }
            .onAppear { layArchiveOutWhenStill() }
        }
        #if os(macOS)
        // The title bar is hidden; the page runs to the top of the window.
        .ignoresSafeArea(.container, edges: .top)
        #endif
        .background(Color.paper.ignoresSafeArea())
    }

    private func scrollTopInset(_ insets: EdgeInsets) -> CGFloat {
        #if os(iOS)
        insets.top
        #else
        0
        #endif
    }

    private static var endID: String { "end of the page" }

    /// The archive is laid out ahead of being wanted, off the bottom of the
    /// page, once the page has been still for half a second. Laid out when
    /// a finger first set off for it, the paper waited some 50 ms for it at
    /// the very moment it should have moved (measured on Wayne's phone, Nov
    /// 22, 2026: one to three late frames in every second of swiping).
    private func layArchiveOutWhenStill() {
        let page = pageID
        Task { @MainActor in
            while !archiveMounted, page == pageID {
                try? await Task.sleep(for: .milliseconds(500))
                guard page == pageID else { return }
                // Not under a finger, and not while a turn is on its way.
                if grabbed == nil, turn == 0, !stripCovers, onPullWhileTurning == nil { archiveMounted = true }
            }
        }
    }

    /// Settings are taken off the paper once they have been away from it,
    /// and nothing has moved, for a moment.
    private func restHeader() {
        headerRests += 1
        let mine = headerRests
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            // Not by what the page view said when this was asked: that is out of date by now.
            guard mine == headerRests, headerHeight > 0, grabbed == nil, heading >= 0 else { return }
            headerMounted = false
        }
    }

    /// Where the page view wants the paper: on settings, on the archive, or on the page.
    private var wanted: CGFloat {
        showsArchive ? Deck.archive : (showsHeader ? Deck.settings : Deck.page)
    }

    /// Puts the paper somewhere, at once or with a spring.
    private func place(_ new: CGFloat, animation: Animation?) {
        FullRate.shared.hold(for: 1)
        if new > 0 { archiveMounted = true }
        if let animation, !reduceMotion {
            withAnimation(animation) { paper.place = new }
        } else if animation != nil {
            // With Reduce Motion the sheets fade from one to the next.
            withAnimation(.ink) { paper.place = new }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { paper.place = new }
        }
    }

    /// The finger has let go: the paper is sent to its place, and the page
    /// view is told which, in the words it has always been told in.
    private func settle(_ target: CGFloat, speed: CGFloat = 0, deck: Deck) {
        heading = target
        restHeader()
        if showsArchive, target != Deck.archive { onPullPastTop?() }
        if showsHeader, target != Deck.settings { onPullPastEnd?() }
        if target == Deck.settings, !showsHeader { onPullPastTop?() }
        if target == Deck.archive, !showsArchive { onPullPastEnd?() }
        place(target, animation: deck.spring(from: paper.place, to: target, speed: speed))
    }

    /// A drag up or down that moves the paper between its places. It is
    /// taken only where there is somewhere to go: from the page, down when
    /// it stands at its top and up when it stands at its end; from settings,
    /// either way; from the archive, down when it stands at its top. A long
    /// page or a long archive scrolls as any list does the rest of the time.
    private func deckDrag(_ deck: Deck) -> some Gesture {
        DragGesture(minimumDistance: Deck.reluctance)
            .updating($deckTouching) { _, touching, _ in touching = true }
            .onChanged { value in
                if deckStart != value.startLocation {
                    deckStart = value.startLocation
                    take(value)
                }
                guard let grabbed else { return }
                FullRate.shared.hold(for: 1)
                let moved = value.translation.height - deckSlip
                place(deck.dragged(from: grabbed, by: moved, low: deckLow, high: deckHigh), animation: nil)
            }
            .onEnded { value in
                deckStart = nil
                guard let grabbed else { return }
                self.grabbed = nil
                FrameTrace.mark("release")
                let speed = -value.velocity.height
                let target = deck.target(
                    now: paper.place, grabbed: grabbed, heading: heading, inFlight: grabbedInFlight, speed: speed,
                    low: deckLow, high: deckHigh
                )
                settle(target, speed: speed, deck: deck)
            }
    }

    /// A finger has begun to drag: whether the paper goes with it, and how far it may.
    private func take(_ value: DragGesture.Value) {
        grabbed = nil
        // A turn to another list is on its way, a line is being carried or
        // written, a menu is open: the sheets stay where they are.
        guard onPullWhileTurning == nil, !scrollDisabled, !sheetsHeld else { return }
        let moved = value.translation
        // Plainly up or down, not a slant: a loop drawn round a line sets off
        // on a slant as often as not, and was taken for a swipe (Wayne, Nov
        // 22, 2026: the circle "sometimes fight with the swipe actions").
        guard abs(moved.height) > abs(moved.width) * Deck.steepness else { return }
        let down = moved.height > 0
        // Taken from where it is seen, on its way or at rest.
        let now = deckFlight.place
        let inFlight = abs(now - heading) > 0.02
        if inFlight {
            deckLow = min(now.rounded(.down), heading)
            deckHigh = max(now.rounded(.up), heading)
            // Sent on the same way, it may go one place further.
            if heading >= now { deckHigh = min(heading + 1, Deck.archive) }
            if heading <= now { deckLow = max(heading - 1, Deck.settings) }
        } else if heading < 0 {
            deckLow = Deck.settings
            deckHigh = Deck.page
        } else if heading > 0 {
            guard down, archiveEdges.atTop else { return }
            deckLow = Deck.page
            deckHigh = Deck.archive
        } else {
            guard down ? pageEdges.atTop : pageEdges.atEnd else { return }
            deckLow = pageEdges.atTop ? Deck.settings : Deck.page
            deckHigh = pageEdges.atEnd ? Deck.archive : Deck.page
        }
        if deckHigh > 0 { archiveMounted = true }
        if deckLow < 0 { headerMounted = true }
        FrameTrace.mark("grab")
        grabbedInFlight = inFlight
        deckSlip = moved.height
        grabbed = now
        // Whatever was carrying it lets go.
        place(now, animation: nil)
    }

    /// While the page turns, and for a moment after it arrives, the sheet
    /// under the finger is not the one that will be there: a pull up or down
    /// made then moved nothing, and the page seemed locked for a bit after a
    /// turn (Wayne, Nov 21, 2026). So a drag up or down in that time is taken
    /// here, off the paper itself, and told to the page, which acts on it
    /// when the turn has landed. Only while a turn is on its way.
    private var turnPull: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                guard onPullWhileTurning != nil, turnPullStart != value.startLocation else { return }
                let moved = value.translation
                guard abs(moved.height) >= 40, abs(moved.height) > abs(moved.width) * 1.5 else { return }
                turnPullStart = value.startLocation
                onPullWhileTurning?(moved.height < 0)
            }
    }

    /// Paper above the list names that still counts as the bottom of the page.
    private static var turnZoneSlack: CGFloat { 28 }

    /// A sheet of the column. It scrolls when it is longer than the screen,
    /// and says whether it stands at its top and at its end.
    private func sheet(
        _ view: some View, metrics: PageMetrics, footerZone: CGFloat, minHeight: CGFloat,
        edges: Binding<SheetEdges>? = nil
    ) -> some View {
        ScrollView {
            VStack(spacing: 0) {
            column(view, metrics: metrics)
                .padding(.top, metrics.topInset)
                // The last line can always be scrolled clear of the list names.
                .padding(.bottom, footerZone)
                .frame(minHeight: minHeight, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { onTapPaper?() }
            // The very end of the paper, below the room left for the list names.
            Color.clear.frame(height: 0).id(Self.endID)
            }
        }
        .scrollIndicators(.hidden)
        // A sheet that is all in view does not move under the finger: a drag
        // on it moves the paper between its places. A longer one scrolls, and
        // goes a little past its ends and comes back, as any list does
        // (Wayne, Nov 22, 2026: "Bring the bouncy for the archive page so if
        // there's a long list it can scroll past naturally").
        .scrollBounceBehavior(.basedOnSize)
        .onScrollGeometryChange(for: SheetEdges.self) { geometry in
            let top = -geometry.contentInsets.top
            // Where its last line stands at the bottom of the screen. The room
            // the scrolling says it keeps below the sheet is not counted: on
            // iOS 18 that is still the keyboard's height after the keyboard has
            // gone, the page was never "at its end" again, and a swipe up for
            // the archive did nothing once anything had been written.
            let end = max(geometry.contentSize.height - geometry.containerSize.height, top)
            return SheetEdges(atTop: geometry.contentOffset.y <= top + 1, atEnd: geometry.contentOffset.y >= end - 1)
        } action: { _, new in
            edges?.wrappedValue = new
        }
    }

    /// Places a view on the column's left edge, with the column centred in the window.
    private func column(_ view: some View, metrics: PageMetrics) -> some View {
        view
            .frame(maxWidth: metrics.columnCap ?? .infinity, alignment: .leading)
            .padding(.horizontal, metrics.sideMargin)
            .frame(maxWidth: .infinity)
    }
}

/// How far the open page has turned at this moment, in pages: the only place
/// the row's position can be read while it is moving by itself.
@MainActor final class TurnFlight {
    var x: CGFloat = 0
}

/// A page in the row, `x` pages from the middle of the paper: moved aside by
/// that much and paler the further it is, up to one page away. Worked out
/// afresh for every frame of a turn. Left to SwiftUI, only the two ends of
/// the turn were worked out and the ink faded evenly between them, so in a
/// turn across two lists the page in between went by pale from edge to edge
/// and the page left behind took the whole way to fade.
private struct TurnedPage: ViewModifier, Animatable {
    var x: CGFloat
    var width: CGFloat
    /// The page that slid in lies over this one for a moment.
    var isCovered = false
    var flight: TurnFlight?

    nonisolated var animatableData: CGFloat {
        get { x }
        set { x = newValue }
    }

    func body(content: Content) -> some View {
        flight?.x = x
        return content
            .offset(x: x * width)
            .opacity(isCovered ? 0 : Self.ink(at: x))
    }

    /// Full ink in the middle of the paper, 35 percent a page away or more.
    nonisolated static func ink(at x: CGFloat) -> Double {
        1 - 0.65 * min(abs(x), 1)
    }
}

/// What decides where a page that follows its end should stand.
private struct EndInView: Equatable {
    var follows: Bool
    var key: Int
    var height: CGFloat
}

/// The coordinate space of the whole page, inside the safe area.
enum PageSpace {
    static let name = "page"
}

private struct ListNamesTopKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    /// Where the list names begin, in the page's coordinate space. `nil` while they are hidden.
    var listNamesTop: CGFloat? {
        get { self[ListNamesTopKey.self] }
        set { self[ListNamesTopKey.self] = newValue }
    }
}

extension View {
    /// Blurs and fades a line of the page as it scrolls under the list names,
    /// the same way the page looks behind settings or a menu.
    func fadesUnderListNames() -> some View {
        modifier(FadeUnderListNames())
    }
}

private struct FadeUnderListNames: ViewModifier {
    @Environment(\.listNamesTop) private var top
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The page behind settings or a menu is blurred and faded to about 60 percent.
    nonisolated static let blurRadius: CGFloat = 6
    nonisolated static let fadedOpacity = 0.6
    /// The distance over which a line goes from clear to fully blurred.
    nonisolated static let distance: CGFloat = 26

    func body(content: Content) -> some View {
        content.visualEffect { [top, reduceTransparency] view, geometry in
            var depth: CGFloat = 0
            if let top {
                // Measured from the middle of the line's last row of text, so a
                // wrapped task starts to blur when its last line goes under.
                let frame = geometry.frame(in: .named(PageSpace.name))
                let lastLine = frame.maxY - min(frame.height, 32) / 2
                depth = min(max((lastLine - (top - 2)) / Self.distance, 0), 1)
            }
            return view
                // With Reduce Transparency the blur becomes a flat dim.
                .blur(radius: reduceTransparency ? 0 : Self.blurRadius * depth)
                .opacity(1 - (1 - Self.fadedOpacity) * depth)
        }
    }
}

/// Whether a sheet stands at its top, and at its end. Both, when all of it is in view.
struct SheetEdges: Equatable {
    var atTop = true
    var atEnd = true
}

extension View {
    /// Whether what is on a sheet is there for VoiceOver: said outright, by
    /// what is showing, since nothing is ever at no ink at all (`DeckPart.seen`).
    func there(_ isThere: Bool) -> some View {
        // Away, the whole of it is one thing, and that thing is left out. On
        // iOS 18 lines that were only marked as left out stayed so when the
        // sheet came back; made of its parts again, it is read afresh.
        accessibilityElement(children: isThere ? .contain : .ignore)
            .accessibilityHidden(!isThere)
    }

    /// The page behind settings or a menu: blurred, faded to about 60 percent, and out of reach.
    func receded(_ isReceded: Bool) -> some View {
        modifier(Receded(isReceded: isReceded))
    }
}

private struct Receded: ViewModifier {
    let isReceded: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            // With Reduce Transparency the blur becomes a flat dim.
            .blur(radius: isReceded && !reduceTransparency ? 4.5 : 0)
            .opacity(isReceded ? 0.6 : 1)
            .allowsHitTesting(!isReceded)
            .accessibilityHidden(isReceded)
    }
}

/// Another list's page in the row of pages.
struct StripPage: Identifiable {
    let id: AnyHashable
    /// Where it stands, in page widths from the middle of the paper.
    let x: CGFloat
    let view: AnyView
}
