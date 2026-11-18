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
struct PageColumn<Header: View, Content: View, Archive: View, Incoming: View, Footer: View>: View {
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
    /// The page holds still while a line is being carried.
    var scrollDisabled = false
    /// A tap on the paper that no line of text claimed, beside the column included.
    var onTapPaper: (() -> Void)?
    /// How far the page has been turned, as a fraction of its width: -1 is
    /// fully off to the left, 1 fully off to the right.
    var turn: CGFloat = 0
    /// The side the incoming page waits on: 1 for the right, -1 for the left, 0 for none.
    var incomingSide = 0
    /// The turn has landed: the incoming page lies exactly where the real one
    /// is about to be, and covers it until it has been laid out.
    var incomingCovers = false
    /// A sideways drag that no task claimed, as a fraction of the page width.
    var onTurnChanged: ((CGFloat) -> Void)?
    /// The drag was let go: how far it went, and its speed in page widths per second.
    var onTurnEnded: ((CGFloat, CGFloat) -> Void)?
    /// The page was dragged up past its end.
    var onPullPastEnd: (() -> Void)?
    /// The archive was dragged down past its top.
    var onPullPastTop: (() -> Void)?
    /// Lines that come down from the top edge and push the page down.
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content
    /// What is done. It lies below the page: it comes up from the bottom edge.
    @ViewBuilder var archive: Archive
    /// The page being turned to, beside this one while it turns.
    @ViewBuilder var incoming: Incoming
    @ViewBuilder var footer: Footer

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var footerHeight: CGFloat = 0

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
                    if incomingSide != 0 {
                        sheet(incoming, metrics: metrics, footerZone: footerZone, minHeight: minHeight)
                            .scrollDisabled(true)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                            .offset(x: incomingCovers ? 0 : (turn + CGFloat(incomingSide)) * width)
                            // The page coming in darkens to full ink as it arrives.
                            .opacity(incomingCovers ? 1 : 0.35 + 0.65 * min(abs(turn), 1))
                    }
                    ZStack {
                    if showsArchive {
                        sheet(archive, metrics: metrics, footerZone: footerZone, minHeight: minHeight)
                            .onPull(.top) { onPullPastTop?() }
                            .id(pageID)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    } else {
                        ZStack {
                            sheet(
                                VStack(alignment: .leading, spacing: metrics.settingsToPageGap) {
                                    if showsHeader {
                                        header.transition(
                                            reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity)
                                        )
                                    }
                                    content.receded(showsHeader || contentReceded)
                                },
                                metrics: metrics, footerZone: footerZone, minHeight: minHeight
                            )
                                .scrollDismissesKeyboard(.interactively)
                                .scrollDisabled(scrollDisabled)
                                // With settings down, any drag up puts them away again.
                                .onPull(.bottom, isEnabled: !showsHeader) { onPullPastEnd?() }
                                .onPull(.awayFromTop, isEnabled: showsHeader) { onPullPastEnd?() }
                                .onPull(.top, isEnabled: !showsHeader) { onPullPastTop?() }
                                .id(pageID)
                                .transition(.opacity)
                        }
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    }
                    }
                    // The page follows the finger and pales as it leaves.
                    .offset(x: turn * width)
                    .opacity(incomingCovers ? 0 : 1 - 0.65 * min(abs(turn), 1))
                }
                // The page runs to the bottom edge, underneath the list names.
                .ignoresSafeArea(.container, edges: .bottom)

                if showsFooter {
                    column(footer, metrics: metrics)
                        .receded(showsHeader || footerReceded)
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
                guard value.startLocation.y >= proxy.size.height - footerZone - Self.turnZoneSlack else { return }
                // Once the page is turning it follows the finger, wherever the finger wanders.
                onTurnChanged?(value.translation.width / max(proxy.size.width, 1))
            } onEnded: { value in
                guard value.startLocation.y >= proxy.size.height - footerZone - Self.turnZoneSlack else { return }
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
            .animation(.sheet, value: showsArchive)
            .animation(.sheet, value: showsHeader)
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

    /// Paper above the list names that still counts as the bottom of the page.
    private static var turnZoneSlack: CGFloat { 28 }

    /// A sheet of the column that scrolls, and can be pulled a little way past either end.
    private func sheet(_ view: some View, metrics: PageMetrics, footerZone: CGFloat, minHeight: CGFloat) -> some View {
        ScrollView {
            column(view, metrics: metrics)
                .padding(.top, metrics.topInset)
                // The last line can always be scrolled clear of the list names.
                .padding(.bottom, footerZone)
                .frame(minHeight: minHeight, alignment: .top)
                .contentShape(Rectangle())
                .onTapGesture { onTapPaper?() }
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
    func onPull(_ edge: PullEdge, isEnabled: Bool = true, perform action: @escaping () -> Void) -> some View {
        modifier(PullPastEdge(edge: edge, isEnabled: isEnabled, action: action))
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
    private var past: CGFloat = 0
    private var offset: CGFloat = 0
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
        return true
    }
}

private struct PullPastEdge: ViewModifier {
    let edge: PullEdge
    let isEnabled: Bool
    let action: () -> Void

    /// Kept out of the view's state: it changes on every frame of a drag.
    private final class Box {
        var tracker: PullTracker
        init(_ edge: PullEdge) { tracker = PullTracker(edge: edge) }
    }

    @State private var box: Box

    init(edge: PullEdge, isEnabled: Bool, action: @escaping () -> Void) {
        self.edge = edge
        self.isEnabled = isEnabled
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
                if wasDragging, !dragging, box.tracker.released(), isEnabled { action() }
            }
            .onScrollGeometryChange(for: CGPoint.self) { geometry in
                CGPoint(x: past(geometry).rounded(), y: geometry.contentOffset.y.rounded())
            } action: { _, new in
                if box.tracker.changed(past: new.x, offset: new.y), isEnabled { action() }
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
