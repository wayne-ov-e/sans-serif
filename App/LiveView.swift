import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// The live view: one list, chosen in that list's own menu, on the Lock
/// Screen and in the Dynamic Island as a Live Activity. It took the place of
/// the working hours, with their hours, days and choice of list (Wayne,
/// Nov 21, 2026: "Delete work hours feature, change it to so that you can
/// toggle on and off for a list").
///
/// The system only lets an app start a Live Activity while it is open, and
/// takes one down after eight hours whatever is asked. So it starts when a
/// list is chosen, and is started again the next time the app is used after
/// the system has taken it down. Nothing can keep it up for days on end
/// without the app being opened.
@MainActor
enum LiveView {
    /// The list shown, by its identity. Empty for none.
    nonisolated static let listKey = "liveList"
    /// The longest the system keeps a Live Activity.
    static let longest: TimeInterval = 8 * 60 * 60

    /// Off in the UI tests, where nothing outside the app should appear.
    static var isAllowed = true

    /// Whether the system will show one at all: off in Settings, it will not.
    static var canStart: Bool {
        #if canImport(ActivityKit) && os(iOS)
        ActivityAuthorizationInfo().areActivitiesEnabled
        #else
        false
        #endif
    }

    /// The list chosen, or nothing.
    nonisolated static func chosenList(defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: listKey).flatMap(UUID.init(uuidString:))
    }

    static func sync(_ snapshot: PageSnapshot, now: Date = .now) {
        #if canImport(ActivityKit) && os(iOS)
        let activities = Activity<PageActivityAttributes>.activities
        guard isAllowed, ActivityAuthorizationInfo().areActivitiesEnabled,
              let chosen = chosenList(), var list = snapshot.list(chosen)
        else {
            // None chosen, or the list chosen is gone.
            activities.forEach(end)
            return
        }
        list.lines = list.lines(PageActivityAttributes.lines)
        let state = PageActivityAttributes.ContentState(list: list)

        // One is kept, brought up to date; any other is ended.
        var kept = false
        for activity in activities {
            let isOver = activity.activityState != .active || activity.attributes.ends <= now
            if !kept, !isOver {
                kept = true
                if activity.content.state != state {
                    let id = activity.id
                    let ends = activity.attributes.ends
                    Task { await update(id, to: state, until: ends) }
                }
            } else {
                end(activity)
            }
        }
        guard !kept else { return }
        let ends = now.addingTimeInterval(longest)
        _ = try? Activity.request(
            attributes: PageActivityAttributes(ends: ends),
            content: ActivityContent(state: state, staleDate: ends), pushType: nil
        )
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    private static func end(_ activity: Activity<PageActivityAttributes>) {
        let id = activity.id
        Task { await end(id) }
    }

    // The system's own calls are made off the main actor, on an activity found again by its id.
    private nonisolated static func end(_ id: String) async {
        for activity in Activity<PageActivityAttributes>.activities where activity.id == id {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private nonisolated static func update(
        _ id: String, to state: PageActivityAttributes.ContentState, until end: Date
    ) async {
        for activity in Activity<PageActivityAttributes>.activities where activity.id == id {
            await activity.update(ActivityContent(state: state, staleDate: end))
        }
    }
    #endif
}
