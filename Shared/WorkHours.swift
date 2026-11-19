import Foundation

/// The hours of a working day during which the page stays on the Lock Screen
/// as a Live Activity. Monday to Friday, from `start` to `end` o'clock.
struct WorkHours: Equatable, Sendable {
    /// The hour it begins, 0 to 22.
    var start: Int
    /// The hour it ends, after `start`, up to 23.
    var end: Int

    static let standard = WorkHours(start: 9, end: 17)
    /// The system keeps a Live Activity for eight hours and no longer, so the hours are never longer.
    static let longest = 8

    static let startKey = "workHoursStart"
    static let endKey = "workHoursEnd"
    /// The list the Live Activity shows, by its identity. Empty for the list
    /// that is open in the app, whichever that is.
    static let listKey = "workHoursList"

    /// The list chosen for the Live Activity, or nothing for the open one.
    static func chosenList(defaults: UserDefaults = .standard) -> UUID? {
        defaults.string(forKey: listKey).flatMap(UUID.init(uuidString:))
    }

    /// The next choice after `current`, for a tap on the word in settings:
    /// the open list, then each list in the order of their names, then the
    /// open list again. A choice that is no longer among the lists counts as
    /// the open list.
    static func nextList(after current: UUID?, in lists: [UUID]) -> UUID? {
        guard let current, let index = lists.firstIndex(of: current) else { return lists.first }
        return index + 1 < lists.count ? lists[index + 1] : nil
    }

    init(start: Int, end: Int) {
        let start = min(max(start, 0), 22)
        self.start = start
        // After the start, within the day, and no more than eight hours on:
        // the system takes a Live Activity down after that, whatever is asked.
        self.end = min(max(end, start + 1), min(23, start + Self.longest))
    }

    /// The hours kept in settings.
    init(defaults: UserDefaults = .standard) {
        self.init(
            start: defaults.object(forKey: Self.startKey) as? Int ?? Self.standard.start,
            end: defaults.object(forKey: Self.endKey) as? Int ?? Self.standard.end
        )
    }

    var length: Int { end - start }

    /// The next hour for the start: an hour later, and round to midnight
    /// rather than past the end.
    func steppingStart(by step: Int) -> WorkHours {
        WorkHours(start: Self.wrap(start + step, in: 0...(end - 1)), end: end)
    }

    func steppingEnd(by step: Int) -> WorkHours {
        movingEnd(to: Self.wrap(end + step, in: (start + 1)...23))
    }

    /// The end moved to an hour. Past eight hours, the start comes along behind it.
    private func movingEnd(to hour: Int) -> WorkHours {
        let end = min(max(hour, start + 1), 23)
        return WorkHours(start: max(start, end - Self.longest), end: end)
    }

    /// A number typed for the start. On a twelve-hour clock, 1 to 12 keep the
    /// half of the day the start is in now, or go to the half that was asked
    /// for; 13 and up are taken as written. The hours keep their length where
    /// the day has room for it.
    func typingStart(
        _ number: Int, afternoon: Bool? = nil, twelveHour: Bool = WorkHours.clockIsTwelveHour
    ) -> WorkHours {
        movingStart(to: Self.hour(number, twelveHour: twelveHour, afternoon: afternoon ?? (start >= 12)))
    }

    /// A number typed for the end. On a twelve-hour clock, 1 to 12 mean the
    /// first such hour after the start: with a start of 9 AM, 5 is 5 PM.
    /// When a half of the day was asked for, it is that half.
    func typingEnd(
        _ number: Int, afternoon: Bool? = nil, twelveHour: Bool = WorkHours.clockIsTwelveHour
    ) -> WorkHours {
        guard twelveHour, (1...12).contains(number) else {
            return movingEnd(to: min(max(number, 0), 23))
        }
        let morning = number % 12
        if let afternoon {
            return movingEnd(to: morning + (afternoon ? 12 : 0))
        }
        return movingEnd(to: morning > start ? morning : morning + 12)
    }

    /// The same hour in the other half of the day: 9 AM to 9 PM and back.
    func start(afternoon: Bool) -> WorkHours {
        movingStart(to: start % 12 + (afternoon ? 12 : 0))
    }

    func end(afternoon: Bool) -> WorkHours {
        movingEnd(to: end % 12 + (afternoon ? 12 : 0))
    }

    private func movingStart(to hour: Int) -> WorkHours {
        WorkHours(start: hour, end: hour >= end ? hour + length : end)
    }

    private static func hour(_ number: Int, twelveHour: Bool, afternoon: Bool) -> Int {
        guard twelveHour, (1...12).contains(number) else { return min(max(number, 0), 23) }
        return number % 12 + (afternoon ? 12 : 0)
    }

    /// Whether the user's clock counts to twelve twice a day.
    static var clockIsTwelveHour: Bool {
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    private static func wrap(_ value: Int, in range: ClosedRange<Int>) -> Int {
        let count = range.count
        return range.lowerBound + ((value - range.lowerBound) % count + count) % count
    }

    /// Today's working hours, if `date` is a working day.
    func hours(on date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard !calendar.isDateInWeekend(date) else { return nil }
        let day = calendar.startOfDay(for: date)
        guard let from = calendar.date(bySettingHour: start, minute: 0, second: 0, of: day),
              let to = calendar.date(bySettingHour: end, minute: 0, second: 0, of: day)
        else { return nil }
        return DateInterval(start: from, end: to)
    }

    /// The working hours `date` falls in, if it does.
    func current(at date: Date, calendar: Calendar = .current) -> DateInterval? {
        guard let hours = hours(on: date, calendar: calendar), hours.start <= date, date < hours.end else { return nil }
        return hours
    }

    /// The working hours that begin next after `date`.
    func next(after date: Date, calendar: Calendar = .current) -> DateInterval? {
        var day = date
        for _ in 0..<8 {
            if let hours = hours(on: day, calendar: calendar), hours.start > date { return hours }
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) else { break }
            day = tomorrow
        }
        return nil
    }

    /// An hour as the user's clock writes it: "9 AM", or "09".
    static func name(ofHour hour: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: hour % 24, minute: 0, second: 0, of: .now) ?? .now
        return date.formatted(.dateTime.hour())
    }
}
