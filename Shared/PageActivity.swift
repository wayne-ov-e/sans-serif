#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

/// One list on the Lock Screen and in the Dynamic Island: the live view.
struct PageActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var list: PageSnapshot.List
    }

    /// When the system will take it down: eight hours after it was put up.
    var ends: Date

    /// Lines the Lock Screen has room for.
    static let lines = 3
}
#endif
