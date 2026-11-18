import SwiftUI

/// Everything about the page that changes with the space it is given.
/// Resolved from available width and size class, never from the device name
/// (brief: Layout by device).
struct PageMetrics: Equatable {
    /// Widest the text column may grow. `nil` fills the width inside the margins.
    var columnCap: CGFloat?
    /// Smallest space between the column and the window edge, on top of the safe area.
    var sideMargin: CGFloat
    /// Distance from the top safe area to the first line.
    var topInset: CGFloat
    /// Distance from the bottom edge of the window to the bottom of the list names.
    var bottomEdgeDistance: CGFloat
    /// Smallest space kept between the list names and the bottom safe area.
    var minBottomInset: CGFloat

    var taskSize: CGFloat
    var listNameSize: CGFloat
    var countSize: CGFloat = 12
    var monthLabelSize: CGFloat = 16

    var taskGap: CGFloat
    var listNameGap: CGFloat
    /// Space between a list name and its raised count.
    var countGap: CGFloat = 4
    /// Archive: between struck tasks, around an open month, and between folded months.
    var archiveTaskGap: CGFloat = 22
    var monthGap: CGFloat = 36
    var foldedMonthGap: CGFloat = 24
    /// Settings: between the lines, and between them and the page below.
    var settingsGap: CGFloat = 20
    var settingsToPageGap: CGFloat = 72
    /// Touch height for list names and menu options.
    var minTouchHeight: CGFloat = 44

    /// Bottom padding inside the safe area for a given bottom inset.
    func bottomInset(safeArea: CGFloat) -> CGFloat {
        max(bottomEdgeDistance - safeArea, minBottomInset)
    }
}

extension PageMetrics {
    /// Frame 01 Page, 402 x 874. Content starts 96 pt down with a 62 pt safe area;
    /// list names sit 48 pt from the bottom edge with a 34 pt safe area.
    static let phone = PageMetrics(
        columnCap: nil, sideMargin: 32,
        topInset: 34, bottomEdgeDistance: 48, minBottomInset: 14,
        taskSize: 25, listNameSize: 20, taskGap: 26, listNameGap: 24
    )

    /// iPhone landscape: no frame yet. Column capped at 560 pt, centred.
    static let phoneLandscape = PageMetrics(
        columnCap: 560, sideMargin: 32,
        topInset: 34, bottomEdgeDistance: 48, minBottomInset: 14,
        taskSize: 25, listNameSize: 20, taskGap: 26, listNameGap: 24
    )

    /// iPad, wide: no frame yet. Column capped at 600 pt, margins at least 64 pt, 28 pt tasks.
    static let pad = PageMetrics(
        columnCap: 600, sideMargin: 64,
        topInset: 34, bottomEdgeDistance: 48, minBottomInset: 14,
        taskSize: 28, listNameSize: 20, taskGap: 26, listNameGap: 24
    )

    /// Frame 06 Mac window, 560 x 640. The title bar is hidden, so the top inset
    /// is measured from the window edge: 18 + 12 pt of window controls + 40.
    static let mac = PageMetrics(
        columnCap: 560, sideMargin: 44,
        topInset: 70, bottomEdgeDistance: 28, minBottomInset: 28,
        taskSize: 21, listNameSize: 20, taskGap: 20, listNameGap: 22
    )

    /// Below this width an iPad window lays out like an iPhone.
    static let narrowWidth: CGFloat = 500

    /// - Parameter width: full width of the window, including safe areas.
    static func resolve(
        width: CGFloat,
        horizontalSizeClass: UserInterfaceSizeClass?,
        verticalSizeClass: UserInterfaceSizeClass?
    ) -> PageMetrics {
        #if os(macOS)
        return .mac
        #else
        if width < narrowWidth { return .phone }
        // A wide window that is short is an iPhone on its side.
        if verticalSizeClass == .compact { return .phoneLandscape }
        if horizontalSizeClass == .regular { return .pad }
        return .phoneLandscape
        #endif
    }
}

private struct PageMetricsKey: EnvironmentKey {
    static let defaultValue: PageMetrics = {
        #if os(macOS)
        .mac
        #else
        .phone
        #endif
    }()
}

extension EnvironmentValues {
    var pageMetrics: PageMetrics {
        get { self[PageMetricsKey.self] }
        set { self[PageMetricsKey.self] = newValue }
    }
}
