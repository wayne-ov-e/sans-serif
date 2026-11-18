import AppIntents
import Foundation
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// A tap on a task in a widget or in the Live Activity. It strikes the task
/// without opening the app, and a second tap before the line leaves undoes it.
struct StrikeTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Strike task"
    static let description = IntentDescription("Strikes a task, or undoes the strike.")
    static let isDiscoverable = false

    @Parameter(title: "Task")
    var task: String

    init() {}

    init(task: UUID) {
        self.task = task.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: task) {
            SharedPage.shared.toggle(task: id)
        }
        // In the app, the change goes into the store and to the Live Activity
        // now. In the widget's own process it waits for the app.
        await OutsideChanges.handler?()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

#if canImport(ActivityKit) && os(iOS)
// A button in a Live Activity runs its intent in the app, not in the widget.
extension StrikeTaskIntent: LiveActivityIntent {}
#endif

/// What the app does when something was struck outside it. Empty in the widget.
enum OutsideChanges {
    @MainActor static var handler: (@MainActor () async -> Void)?
}
