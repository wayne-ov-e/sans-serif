import CryptoKit
import Foundation
import SwiftData

// A task that repeats is still one line on the page. Struck, it goes to the
// archive like any other, and a fresh copy is made at once that waits, unseen,
// for its day (Wayne, Nov 20, 2026). Every copy of one repeat carries the same
// `series`. There is only ever one copy that is not struck.

/// When a task comes back.
struct Repeat: Equatable, Sendable {
    enum Every: Equatable, Sendable {
        case day
        /// Days of the week as the calendar counts them: 1 is Sunday, 7 Saturday.
        case week(Set<Int>)
        /// A day of the month, 1 to 31, or `Repeat.lastDay`.
        case month(Int)
        case year(month: Int, day: Int)
    }

    var every: Every

    /// Stands for the last day of a month, however long the month is.
    static let lastDay = 32

    init(_ every: Every) { self.every = every }

    /// As it is kept on the task and in iCloud: "daily", "weekly:2,4,6",
    /// "monthly:20", "monthly:last", "yearly:11-20".
    init?(_ written: String) {
        let parts = written.split(separator: ":", maxSplits: 1).map(String.init)
        let detail = parts.count > 1 ? parts[1] : ""
        switch parts.first {
        case "daily":
            every = .day
        case "weekly":
            let days = Set(detail.split(separator: ",").compactMap { Int($0) }.filter { (1...7).contains($0) })
            guard !days.isEmpty else { return nil }
            every = .week(days)
        case "monthly":
            if detail == "last" {
                every = .month(Self.lastDay)
            } else if let day = Int(detail), (1...31).contains(day) {
                every = .month(day)
            } else {
                return nil
            }
        case "yearly":
            let numbers = detail.split(separator: "-").compactMap { Int($0) }
            guard numbers.count == 2, (1...12).contains(numbers[0]), (1...31).contains(numbers[1]) else { return nil }
            every = .year(month: numbers[0], day: numbers[1])
        default:
            return nil
        }
    }

    var written: String {
        switch every {
        case .day: "daily"
        case .week(let days): "weekly:" + days.sorted().map(String.init).joined(separator: ",")
        case .month(let day): day >= Self.lastDay ? "monthly:last" : "monthly:\(day)"
        case .year(let month, let day): "yearly:\(month)-\(day)"
        }
    }

    /// Whether the task is due on this day. A day a month does not have falls
    /// on its last one: the 31st in April is the 30th, Feb 29 is Feb 28 most years.
    func falls(on date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        let length = calendar.range(of: .day, in: .month, for: date)?.count ?? 31
        switch every {
        case .day: return true
        case .week(let days): return days.contains(parts.weekday ?? 0)
        case .month(let day): return parts.day == min(day, length)
        case .year(let month, let day): return parts.month == month && parts.day == min(day, length)
        }
    }

    /// The first day it is due after this one. Never the same day: what is
    /// done today comes back tomorrow at the soonest.
    func next(after date: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: date)
        // Four years and a day: far enough to reach the next Feb 29.
        for step in 1...1462 {
            guard let day = calendar.date(byAdding: .day, value: step, to: start) else { break }
            if falls(on: day, calendar: calendar) { return day }
        }
        return calendar.date(byAdding: .day, value: 1, to: start) ?? date
    }

    static let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    static let monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// The days of the week in the order they are offered, Monday first.
    static let weekOrder = [2, 3, 4, 5, 6, 7, 1]

    /// The small word after the task on the page: "daily", "mon wed fri", "1st", "last", "nov 20".
    var mark: String {
        switch every {
        case .day:
            return "daily"
        case .week(let days):
            if days.count == 7 { return "daily" }
            return Self.weekOrder.filter(days.contains).map { Self.weekdayNames[$0 - 1].lowercased() }.joined(separator: " ")
        case .month(let day):
            return day >= Self.lastDay ? "last" : Self.ordinal(day)
        case .year(let month, let day):
            return "\(Self.monthNames[month - 1].lowercased()) \(day)"
        }
    }

    /// For VoiceOver: "Repeats daily".
    var spoken: String {
        switch every {
        case .day: return "Repeats daily"
        case .week(let days):
            if days.count == 7 { return "Repeats daily" }
            return "Repeats " + Self.weekOrder.filter(days.contains).map { Self.weekdayNames[$0 - 1] }.joined(separator: ", ")
        case .month(let day): return day >= Self.lastDay ? "Repeats on the last day of the month" : "Repeats on the \(Self.ordinal(day))"
        case .year(let month, let day): return "Repeats every \(Self.monthNames[month - 1]) \(day)"
        }
    }

    static func ordinal(_ day: Int) -> String {
        let ending: String = switch (day % 100, day % 10) {
        case (11...13, _): "th"
        case (_, 1): "st"
        case (_, 2): "nd"
        case (_, 3): "rd"
        default: "th"
        }
        return "\(day)\(ending)"
    }

    /// How many days the longest year gives a month: February has 29.
    static func days(in month: Int) -> Int {
        switch month {
        case 2: 29
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// A day as it is kept: "2026-11-20". A day of the calendar and not a
    /// moment, so that it begins for each person when their own day does.
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        PageSnapshot.day(date, calendar: calendar)
    }

    /// The identity of the copy of a repeat that is due on a day. Worked out,
    /// not made up: two devices that both see the strike make the same task,
    /// and iCloud holds one record, not two.
    static func copyID(series: String, day: String) -> UUID {
        let hash = Array(SHA256.hash(data: Data("\(series)|\(day)".utf8)))
        return UUID(uuid: (
            hash[0], hash[1], hash[2], hash[3], hash[4], hash[5], hash[6], hash[7],
            hash[8], hash[9], hash[10], hash[11], hash[12], hash[13], hash[14], hash[15]
        ))
    }
}

extension TaskItem {
    /// When the task comes back after it is struck. Empty for a task that does not repeat.
    var rule: Repeat? { repeats.flatMap { Repeat($0) } }

    /// Not struck, and its day has not come: it is kept, and not shown anywhere.
    func isWaiting(at now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard isLive, let dueDay else { return false }
        return dueDay > Repeat.day(now, calendar: calendar)
    }

    /// On the page: not struck, and not waiting for its day.
    var isOnPage: Bool { isLive && !isWaiting() }
}

extension ModelContext {
    /// Every copy of one repeat, struck or not, on whatever list.
    func copies(of series: String) -> [TaskItem] {
        let wanted: String? = series
        return (try? fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.series == wanted }))) ?? []
    }

    /// Makes a task repeat, changes when it does, or with `nil` stops it.
    func setRepeat(_ rule: Repeat?, on task: TaskItem) {
        guard let rule else {
            endRepeat(of: task)
            task.repeats = nil
            task.series = nil
            return
        }
        if task.repeats != rule.written { task.repeats = rule.written }
        if task.series == nil { task.series = UUID().uuidString }
    }

    /// The repeat is over: the task is to be deleted, or was told never to
    /// repeat. What was done stays in the archive but no longer says it
    /// repeats, so nothing brings the task back.
    func endRepeat(of task: TaskItem) {
        guard task.isLive, let series = task.series else { return }
        for copy in copies(of: series) where copy !== task {
            if copy.isLive {
                delete(copy)
            } else if copy.repeats != nil {
                copy.repeats = nil
            }
        }
    }

    /// The copy that comes back after this struck one. Nothing is made while
    /// another copy is still to be done: there is never a pile of them.
    @discardableResult
    func makeNext(after task: TaskItem, at date: Date = .now, calendar: Calendar = .current) -> TaskItem? {
        guard !task.isLive, let rule = task.rule, let series = task.series, let list = task.list else { return nil }
        let all = copies(of: series)
        guard !all.contains(where: { $0.isLive }) else { return nil }
        let day = Repeat.day(rule.next(after: date, calendar: calendar), calendar: calendar)
        let id = Repeat.copyID(series: series, day: day)
        guard !all.contains(where: { $0.id == id }) else { return nil }
        // It comes back where it was on the page.
        let next = TaskItem(text: task.text, order: task.order, list: list)
        next.id = id
        next.createdDate = date
        next.repeats = task.repeats
        next.series = series
        next.dueDay = day
        next.addedBy = task.addedBy
        insert(next)
        return next
    }

    /// A struck copy of a repeat is live again. The copy that waited for the
    /// next day is not needed. If one has already come back to the page, this
    /// one is an ordinary task from now on: there are never two of a repeat.
    func settleRepeat(restored task: TaskItem) {
        guard task.isLive, let series = task.series else { return }
        var another = false
        for copy in copies(of: series) where copy !== task && copy.isLive {
            if copy.isWaiting() { delete(copy) } else { another = true }
        }
        if another {
            task.repeats = nil
            task.series = nil
        }
    }

    /// Puts right what other devices leave: two copies of a repeat still to be
    /// done (two people struck it on different days, each offline), or none at
    /// all (it was struck on a build that knows nothing of repeats). The same
    /// on every device. Returns how many tasks were made or removed.
    @discardableResult
    func tidyRepeats(calendar: Calendar = .current) -> Int {
        let repeating = (try? fetch(FetchDescriptor<TaskItem>(predicate: #Predicate { $0.series != nil }))) ?? []
        var changed = 0
        for (_, copies) in Dictionary(grouping: repeating, by: { $0.series ?? "" }) {
            let live = copies.filter(\.isLive).sorted {
                ($0.dueDay ?? "", $0.id.uuidString) < ($1.dueDay ?? "", $1.id.uuidString)
            }
            if live.count > 1 {
                // The earliest stays.
                for extra in live.dropFirst() {
                    delete(extra)
                    changed += 1
                }
            } else if live.isEmpty,
                      let last = copies.max(by: { ($0.struckDate ?? .distantPast) < ($1.struckDate ?? .distantPast) }),
                      let struck = last.struckDate,
                      makeNext(after: last, at: struck, calendar: calendar) != nil {
                changed += 1
            }
        }
        return changed
    }
}
