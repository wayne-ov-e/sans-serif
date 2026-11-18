import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// The Live Activity of the working hours: the open list, on the Lock Screen
/// and in the Dynamic Island, from the first working hour to the last.
///
/// The system only lets an app start a Live Activity while it is open. So it
/// starts when the app is used during working hours, and from iOS 26 the app
/// also books the next working day's ahead of time, each time it is used.
/// Nothing can end it at the stroke of the hour without the app running: it
/// is marked stale then, the system takes it down after eight hours at most,
/// and the app ends it the next time it runs.
@MainActor
enum WorkHoursActivity {
    /// Off in the UI tests, where nothing outside the app should appear.
    static var isAllowed = true

    static func sync(_ snapshot: PageSnapshot, now: Date = .now) {
        #if canImport(ActivityKit) && os(iOS)
        let defaults = UserDefaults.standard
        let isOn = defaults.object(forKey: Setting.workHours.key) as? Bool ?? Setting.workHours.defaultValue
        let activities = Activity<PageActivityAttributes>.activities
        guard isAllowed, isOn, ActivityAuthorizationInfo().areActivitiesEnabled,
              var list = snapshot.list(snapshot.current)
        else {
            activities.forEach(end)
            return
        }
        list.lines = list.lines(PageActivityAttributes.lines)
        let state = PageActivityAttributes.ContentState(list: list)
        let hours = WorkHours(defaults: defaults)

        // The hours it should be showing for: these, or the next.
        let running = hours.current(at: now)
        guard let wanted = running ?? hours.next(after: now) else {
            activities.forEach(end)
            return
        }
        let attributes = PageActivityAttributes(ends: wanted.end)
        let content = ActivityContent(state: state, staleDate: wanted.end)

        var kept = false
        for activity in activities {
            let isOver = activity.activityState == .ended || activity.activityState == .dismissed
            if !kept, !isOver, activity.attributes.ends == wanted.end, booked(activity) == wanted.start {
                kept = true
                if activity.content.state != state {
                    let id = activity.id
                    Task { await update(id, to: state, until: wanted.end) }
                }
            } else {
                end(activity)
            }
        }
        guard !kept else { return }

        if running != nil {
            if let activity = try? Activity.request(attributes: attributes, content: content, pushType: nil) {
                book(activity, for: wanted.start)
            }
        } else if #available(iOS 26.0, *) {
            // Booked for the first working hour. It arrives with the list name and what is next.
            let alert = AlertConfiguration(
                title: LocalizedStringResource(stringLiteral: list.name),
                body: LocalizedStringResource(stringLiteral: list.next?.text ?? "Nothing left"),
                sound: .default
            )
            if let activity = try? Activity.request(
                attributes: attributes, content: content, pushType: nil,
                style: .standard, alertConfiguration: alert, start: wanted.start
            ) {
                book(activity, for: wanted.start)
            }
        }
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    private static let bookedKey = "workHoursBooked"

    /// The start each activity was made for, so that one made for other hours is replaced.
    private static func booked(_ activity: Activity<PageActivityAttributes>) -> Date? {
        let all = UserDefaults.standard.dictionary(forKey: bookedKey) as? [String: Date]
        return all?[activity.id]
    }

    private static func book(_ activity: Activity<PageActivityAttributes>, for start: Date) {
        // Only the newest is kept: the others are being ended.
        UserDefaults.standard.set([activity.id: start], forKey: bookedKey)
    }

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
