#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// The page on the Lock Screen and in the Dynamic Island during working hours.
struct PageActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var list: PageSnapshot.List
    }

    /// When the working hours end.
    var ends: Date

    /// Lines the Lock Screen has room for.
    static let lines = 3
}
#endif
