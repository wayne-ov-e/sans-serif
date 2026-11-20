import AppIntents
import Foundation
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// A tap on a task in a widget. It strikes the task without opening the app,
/// and a second tap before the line leaves undoes it.
///
/// It runs in the widget itself and only writes to the shared drawer, so the
/// widget is drawn again at once. The app takes the change into its store, and
/// on to iCloud, the next time it runs.
struct StrikeTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Strike task"
    static let description = IntentDescription("Strikes a task, or undoes the strike.")
    static let isDiscoverable = false

    @Parameter(title: "Task")
    var task: String

    /// How the line looked when it was tapped. Empty for a tap from a widget
    /// drawn by an earlier version of the app.
    @Parameter(title: "Was live")
    var wasLive: Bool?

    init() {}

    init(task: UUID, wasLive: Bool? = nil) {
        self.task = task.uuidString
        self.wasLive = wasLive
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: task) {
            SharedPage.shared.toggle(task: id, expectingLive: wasLive)
        }
        // If this does run in the app, the change goes into the store now.
        await OutsideChanges.handler?()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// The same tap in the Live Activity. A button there runs its intent in the
/// app, so the store and the Live Activity change at once.
///
/// The widgets must not use this one. For an intent that may start a Live
/// Activity the system waits three seconds, in case one starts, before it
/// draws a widget again: a tapped task sat there unchanged for three seconds
/// and then was simply gone.
struct StrikeLiveTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Strike task in the Live Activity"
    static let description = IntentDescription("Strikes a task, or undoes the strike.")
    static let isDiscoverable = false

    @Parameter(title: "Task")
    var task: String

    /// How the line looked when it was tapped. Empty for a tap from a widget
    /// drawn by an earlier version of the app.
    @Parameter(title: "Was live")
    var wasLive: Bool?

    init() {}

    init(task: UUID, wasLive: Bool? = nil) {
        self.task = task.uuidString
        self.wasLive = wasLive
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: task) {
            SharedPage.shared.toggle(task: id, expectingLive: wasLive)
        }
        await OutsideChanges.handler?()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

#if canImport(ActivityKit) && os(iOS)
extension StrikeLiveTaskIntent: LiveActivityIntent {}
#endif

/// What the app does when something was struck outside it. Empty in the widget.
enum OutsideChanges {
    @MainActor static var handler: (@MainActor () async -> Void)?
}
