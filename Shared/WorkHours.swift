import Foundation

/// The hours of a working day during which the page stays on the Lock Screen
/// as a Live Activity. Monday to Friday, from `start` to `end` o'clock.
struct WorkHours: Equatable, Sendable {
    /// The hour it begins, 0 to 22.
    var start: Int
    /// The hour it ends, after `start`, up to 23.
    var end: Int

    static let standard = WorkHours(start: 9, end: 17)
    /// The system keeps a Live Activity for eight hours and no longer.
    static let longest = 8

    static let startKey = "workHoursStart"
    static let endKey = "workHoursEnd"

    init(start: Int, end: Int) {
        let start = min(max(start, 0), 22)
        self.start = start
        self.end = min(max(end, start + 1), 23)
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
        WorkHours(start: start, end: Self.wrap(end + step, in: (start + 1)...23))
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
