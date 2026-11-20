import SwiftUI

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
    /// Lines that come down from the top edge and push the page down.
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    /// What is done. It lies below the page: it comes up from the bottom edge.
    @ViewBuilder var archive: Archive
    @ViewBuilder var footer: Footer

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var footerHeight: CGFloat = 0
    @State private var headerHeight: CGFloat = 0
    /// The archive is wanted: the value of `showsArchive`, where a later moment can read it.
    @State private var wantsArchive = false
    /// The archive is laid out, on the page or off its bottom edge.
    @State private var archiveMounted = false
    /// The archive is up, and the page has gone above.
    @State private var archiveShown = false
    /// Where the paper is held while the scrolling lets go of it for a moment
    /// under the finger. Nothing, almost always. See `PullTracker.held`.
    @State private var held: CGFloat = 0
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

            ZStack(alignment: .bottom) {
                GeometryReader { viewport in
                    // The sheet fills the page and no more, so a page that fits does not
                    // scroll. The scroll view reaches up under the status bar and insets
                    // its content by that much, which is taken off here.
                    let minHeight = viewport.size.height - viewport.safeAreaInsets.bottom - scrollTopInset(insets)
                    let width = viewport.size.width
                    let height = viewport.size.height
                    ZStack {
                        // The page is always here. Settings stand above it, in the same
                        // sheet, and take room as they come: nothing is put in or taken
                        // out, so going back and forth only ever moves what is there.
                        ScrollViewReader { scroll in
                        sheet(
                            VStack(alignment: .leading, spacing: 0) {
                                header
                                    .fixedSize(horizontal: false, vertical: true)
                                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                                    .opacity(showsHeader ? 1 : 0)
                                    // They come down from above the page by their own height, as they always did.
                                    .offset(y: showsHeader || reduceMotion ? 0 : -(headerHeight + metrics.settingsToPageGap))
                                    .allowsHitTesting(showsHeader)
                                    .accessibilityHidden(!showsHeader)
                                    .frame(
                                        height: showsHeader ? headerHeight + metrics.settingsToPageGap : 0,
                                        alignment: .top
                                    )
                                content.receded(showsHeader || contentReceded)
                            },
                            metrics: metrics, footerZone: footerZone, minHeight: minHeight, handsOver: true
                        )
                            .scrollDismissesKeyboard(.interactively)
                            .scrollDisabled(scrollDisabled)
                            // With settings down, any drag up puts them away again.
                            .onPull(.bottom, isEnabled: !showsHeader, held: hold) { pulled($0, then: onPullPastEnd) }
                            .onPull(.awayFromTop, isEnabled: showsHeader, held: hold) { pulled($0, then: onPullPastEnd) }
                            .onPull(.top, isEnabled: !showsHeader, held: hold) { pulled($0, then: onPullPastTop) }
                            .id(pageID)
                            .transition(.opacity)
                            // The page goes up and out as the archive comes up from below.
                            .offset(y: archiveShown && !reduceMotion ? -height : 0)
                            .opacity(archiveShown ? 0 : 1)
                            .allowsHitTesting(!archiveShown)
                            .accessibilityHidden(archiveShown)
                            // The line being written is brought to the best place: when
                            // the pen is put to it, when the keyboard has changed how much
                            // of the page shows, and each time the end of the page moves.
                            .onChange(of: EndInView(follows: followsEnd, key: endKey, height: height)) { old, new in
                                guard new.follows, !showsHeader, !archiveShown else { return }
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

                        // The archive is laid out a moment before it is wanted and kept
                        // until it has gone, so it too only ever moves.
                        if archiveMounted {
                            sheet(archive, metrics: metrics, footerZone: footerZone, minHeight: minHeight, handsOver: true)
                                .onPull(.top, held: hold) { pulled($0, then: onPullPastTop) }
                                .id(pageID)
                                .offset(y: archiveShown || reduceMotion ? 0 : height)
                                .opacity(archiveShown ? 1 : 0)
                                .allowsHitTesting(archiveShown)
                                .accessibilityHidden(!archiveShown)
                        }
                    }
                    .animation(.sheet, value: archiveShown)
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
            .animation(.sheet, value: showsHeader)
            .onChange(of: showsArchive, initial: true) { _, shows in
                wantsArchive = shows
                if shows {
                    // Laid out below the page first, then brought up from there.
                    archiveMounted = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(16))
                        if wantsArchive { archiveShown = true }
                    }
                } else {
                    archiveShown = false
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(700))
                        if !wantsArchive { archiveMounted = false }
                    }
                }
            }
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

    /// Paper above the list names that still counts as the bottom of the page.
    private static var turnZoneSlack: CGFloat { 28 }

    /// A sheet of the column that scrolls, and can be pulled a little way past either end.
    /// A pull has counted. The paper goes on following the finger, as it
    /// always did: that is what makes it feel like a page being pulled.
    private func pulled(_ pull: Pull, then action: (() -> Void)?) {
        action?()
    }

    /// The paper is held this far from its edge, or let go again.
    private func hold(_ shift: CGFloat, settling: Bool) {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-logPulls") { NSLog("PULL held %.0f settling %d", shift, settling ? 1 : 0) }
        #endif
        if settling, !reduceMotion {
            withAnimation(.sheet) { held = shift }
        } else {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { held = shift }
        }
    }

    private func sheet(
        _ view: some View, metrics: PageMetrics, footerZone: CGFloat, minHeight: CGFloat, handsOver: Bool = false
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
                // The paper inside is what is held, not the scrolling sheet itself:
                // moving that changes how much of it lies under the status bar,
                // which changes what the scrolling reports, which moved it again,
                // without end.
                .offset(y: handsOver ? held : 0)
            // The very end of the paper, below the room left for the list names.
            Color.clear.frame(height: 0).id(Self.endID)
            }
        }
        .scrollIndicators(.hidden)
        // The pull past the end is how the archive opens, so even a short page gives.
        .scrollBounceBehavior(.always)
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

/// A pull at the moment it counts.
struct Pull {
    /// How far past the edge the sheet has been dragged.
    var past: CGFloat
    /// The same as a movement of the sheet on the page: down is positive.
    var shift: CGFloat
}

/// An end of a scrolling sheet, or the way off its top.
enum PullEdge {
    /// Dragged down past the top.
    case top
    /// Dragged up past the end.
    case bottom
    /// Dragged up at all, whether the sheet scrolls or only gives.
    case awayFromTop
}

extension View {
    /// Calls `action` once when a finger drags the sheet past one of its ends.
    /// It is told how far past the edge the sheet was at that moment. `held`
    /// is told when the paper has to be held somewhere for a moment, and
    /// when it is let go again: see `PullTracker.held`.
    func onPull(
        _ edge: PullEdge, isEnabled: Bool = true, held: @escaping (CGFloat, Bool) -> Void = { _, _ in },
        perform action: @escaping (Pull) -> Void
    ) -> some View {
        modifier(PullPastEdge(edge: edge, isEnabled: isEnabled, held: held, action: action))
    }
}

/// Decides when a drag on a sheet has pulled it past an edge. It is plain data,
/// apart from the views, so that it can be tested.
struct PullTracker {
    let edge: PullEdge

    /// How far the sheet must be dragged while the finger is still down.
    var distance: CGFloat { edge == .awayFromTop ? 20 : 40 }
    /// A quick drag that is let go early counts from here, if it began at the edge.
    var flickDistance: CGFloat { edge == .awayFromTop ? 8 : 14 }

    private(set) var isDragging = false
    /// How far past the edge the sheet is now.
    private(set) var past: CGFloat = 0
    private var offset: CGFloat = 0

    /// The pull as it stands.
    var pull: Pull {
        let past = max(past, 0)
        return Pull(past: past, shift: edge == .top ? past : -past)
    }

    /// A pull has counted and the sheet has not yet come back to its edge.
    private var isHandedOver = false
    /// How far past the edge the sheet last really was.
    private var lastPast: CGFloat = 0
    /// The paper is being held where the finger had it.
    private(set) var isHolding = false

    /// When a pull counts, what is on the sheet changes size under the finger:
    /// settings arrive, or go. For a few frames the scrolling then puts the
    /// sheet back at its edge, and at the finger's next movement it is under
    /// the finger again. That flicker was the stutter in every pull.
    ///
    /// So when the sheet is suddenly at its edge with the finger still down,
    /// this gives the distance it had been pulled, to hold the paper there.
    /// It gives 0 when the scrolling has it again, and nothing the rest of
    /// the time: the paper follows the finger by the scrolling alone.
    mutating func held() -> CGFloat? {
        guard isHandedOver else { return nil }
        if isDragging, past <= 0, lastPast > 8 {
            isHolding = true
            return edge == .top ? lastPast : -lastPast
        }
        lastPast = max(past, 0)
        if !isDragging, past <= 0 { isHandedOver = false }
        guard isHolding else { return nil }
        isHolding = false
        return 0
    }

    /// The finger lifted while the paper was being held. True if it was, so
    /// that it can be let down to its edge.
    mutating func letGo() -> Bool {
        guard isHolding else { return false }
        isHolding = false
        isHandedOver = false
        return true
    }

    /// Where the sheet was when the finger came down.
    private var startOffset: CGFloat = 0
    private var beganAtEdge = false
    private var fired = false
    /// Whether this pull was on offer when the finger came down. One drag does
    /// one thing: a drag that puts settings away cannot go on to open the
    /// archive, because the archive was not on offer when that drag began.
    private var armed = false

    init(edge: PullEdge) {
        self.edge = edge
    }

    /// How far a sheet is past the edge. Negative while it is short of it.
    static func past(
        _ edge: PullEdge, offset: CGFloat, topInset: CGFloat, bottomInset: CGFloat,
        contentHeight: CGFloat, containerHeight: CGFloat
    ) -> CGFloat {
        let top = -topInset
        switch edge {
        case .top: return top - offset
        case .awayFromTop: return offset - top
        case .bottom: return offset - max(contentHeight + bottomInset - containerHeight, top)
        }
    }

    /// How far this drag has moved the sheet toward the edge. A sheet's insets
    /// shift while it comes or goes, and for a moment it can look past an edge
    /// it was never dragged to. Only a drag that went that way counts.
    private var moved: CGFloat {
        edge == .top ? startOffset - offset : offset - startOffset
    }

    /// A finger came down on the sheet. `isEnabled` is whether this pull is on offer now.
    mutating func began(past: CGFloat, offset: CGFloat, isEnabled: Bool = true) {
        isDragging = true
        armed = isEnabled
        beganAtEdge = past >= -1
        startOffset = offset
        self.offset = offset
        self.past = past
        fired = false
    }

    /// The sheet moved. True, once, when a drag has pulled it far enough.
    mutating func changed(past: CGFloat, offset: CGFloat) -> Bool {
        self.past = past
        self.offset = offset
        // A flick that bounces past the end does not count: only a drag.
        guard armed, isDragging, past >= distance, moved >= distance / 2 else { return false }
        return fire()
    }

    /// The finger lifted. True when it was a quick pull that began at the edge:
    /// let go before it had gone far, but not a scroll that ran on.
    mutating func released() -> Bool {
        guard isDragging else { return false }
        isDragging = false
        guard armed, beganAtEdge, past >= flickDistance, moved >= flickDistance else { return false }
        return fire()
    }

    private mutating func fire() -> Bool {
        guard !fired else { return false }
        fired = true
        isHandedOver = true
        lastPast = max(past, 0)
        return true
    }
}

private struct PullPastEdge: ViewModifier {
    let edge: PullEdge
    let isEnabled: Bool
    let held: (CGFloat, Bool) -> Void
    let action: (Pull) -> Void

    /// Kept out of the view's state: it changes on every frame of a drag.
    private final class Box {
        var tracker: PullTracker
        init(_ edge: PullEdge) { tracker = PullTracker(edge: edge) }
    }

    @State private var box: Box

    init(edge: PullEdge, isEnabled: Bool, held: @escaping (CGFloat, Bool) -> Void, action: @escaping (Pull) -> Void) {
        self.edge = edge
        self.isEnabled = isEnabled
        self.held = held
        self.action = action
        _box = State(initialValue: Box(edge))
    }

    private func past(_ geometry: ScrollGeometry) -> CGFloat {
        PullTracker.past(
            edge, offset: geometry.contentOffset.y,
            topInset: geometry.contentInsets.top, bottomInset: geometry.contentInsets.bottom,
            contentHeight: geometry.contentSize.height, containerHeight: geometry.containerSize.height
        )
    }

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { old, new, context in
                let wasDragging = old == .interacting || old == .tracking
                let dragging = new == .interacting || new == .tracking
                if dragging, !wasDragging {
                    box.tracker.began(
                        past: past(context.geometry), offset: context.geometry.contentOffset.y, isEnabled: isEnabled
                    )
                }
                if wasDragging, !dragging {
                    if box.tracker.released(), isEnabled { action(box.tracker.pull) }
                    // Lifted while the paper was held: it settles to its edge.
                    if box.tracker.letGo() { held(0, true) }
                }
            }
            .onScrollGeometryChange(for: CGPoint.self) { geometry in
                CGPoint(x: past(geometry).rounded(), y: geometry.contentOffset.y.rounded())
            } action: { _, new in
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-logPulls"), edge == .top {
                    NSLog("PULL offset %.0f past %.0f at %.3f", new.y, new.x, CACurrentMediaTime())
                }
                #endif
                if box.tracker.changed(past: new.x, offset: new.y), isEnabled { action(box.tracker.pull) }
                if let shift = box.tracker.held() { held(shift, false) }
            }
    }
}

extension View {
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
