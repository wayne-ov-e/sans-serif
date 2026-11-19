import Foundation
import Testing

@testable import SansSerif

/// Working hours pushed as far as they go: every hour stepped and typed,
/// settings that hold nonsense, the first and last moments of the day, the
/// weekend, and the night the clocks change.
@Suite("Working hours at the edges")
struct HoursEdgeTests {
    private func calendar(_ zone: String = "UTC") -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        return calendar
    }

    /// 18 November 2026 is a Wednesday.
    private func date(
        _ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Int = 0, month: Int = 11, in zone: String = "UTC"
    ) -> Date {
        calendar(zone).date(from: DateComponents(
            year: 2026, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    /// What must always be true of the hours, whatever was asked for.
    private func holds(_ hours: WorkHours) -> Bool {
        (0...22).contains(hours.start) && hours.start < hours.end && hours.end <= 23
            && hours.length >= 1 && hours.length <= WorkHours.longest
    }

    private var every: [WorkHours] {
        (0...22).flatMap { start in ((start + 1)...23).map { WorkHours(start: start, end: $0) } }
    }

    // MARK: Making them

    @Test(arguments: [
        (-5, 99, 0, 8), (30, 0, 22, 23), (9, 9, 9, 10), (9, 3, 9, 10), (20, 23, 20, 23),
        (22, 23, 22, 23), (0, 23, 0, 8), (16, 23, 16, 23), (15, 23, 15, 23), (14, 23, 14, 22),
        (Int.min / 2, Int.max / 2, 0, 8),
    ])
    func hoursAskedForAreBroughtInsideTheDay(asked: (Int, Int, Int, Int)) {
        let hours = WorkHours(start: asked.0, end: asked.1)
        #expect(hours.start == asked.2)
        #expect(hours.end == asked.3)
        #expect(holds(hours))
    }

    @Test func settingsThatHoldNonsenseGiveNineToFive() throws {
        let defaults = try #require(UserDefaults(suiteName: "hours-edge-\(UUID().uuidString)"))
        #expect(WorkHours(defaults: defaults) == .standard)
        defaults.set("nine", forKey: WorkHours.startKey)
        defaults.set(Data([1, 2, 3]), forKey: WorkHours.endKey)
        #expect(WorkHours(defaults: defaults) == .standard)
        defaults.set(-40, forKey: WorkHours.startKey)
        defaults.set(400, forKey: WorkHours.endKey)
        #expect(holds(WorkHours(defaults: defaults)))
        #expect(WorkHours(defaults: defaults) == WorkHours(start: 0, end: 8))
    }

    @Test func oneEndKeptInSettingsIsReadWithTheOtherAsUsual() throws {
        let defaults = try #require(UserDefaults(suiteName: "hours-edge-\(UUID().uuidString)"))
        defaults.set(13, forKey: WorkHours.startKey)
        #expect(WorkHours(defaults: defaults) == WorkHours(start: 13, end: 17))
        defaults.removeObject(forKey: WorkHours.startKey)
        defaults.set(12, forKey: WorkHours.endKey)
        #expect(WorkHours(defaults: defaults) == WorkHours(start: 9, end: 12))
    }

    // MARK: Stepping and typing, everywhere

    @Test func steppingFromAnyHoursByAnyNumberGivesHoursThatHold() {
        for hours in every {
            for step in -30...30 {
                #expect(holds(hours.steppingStart(by: step)), "start of \(hours) by \(step)")
                #expect(holds(hours.steppingEnd(by: step)), "end of \(hours) by \(step)")
            }
        }
    }

    @Test func steppingByNothingOrAllTheWayRoundChangesNothing() {
        for hours in every {
            #expect(hours.steppingStart(by: 0) == hours)
            #expect(hours.steppingEnd(by: 0) == hours)
            #expect(hours.steppingStart(by: hours.end) == hours, "the start has \(hours.end) hours to go round")
            #expect(hours.steppingEnd(by: 23 - hours.start) == hours)
        }
    }

    @Test func aStepForwardIsUndoneByAStepBackWhereNothingWasPushed() {
        for hours in every {
            let later = hours.steppingEnd(by: 1)
            // Not when the end went round to the start, or pushed the start along.
            if later.start == hours.start, later.end == hours.end + 1 {
                #expect(later.steppingEnd(by: -1) == hours)
            }
        }
    }

    @Test func anyNumberTypedInEitherClockGivesHoursThatHold() {
        for hours in every {
            for number in -3...40 {
                for twelveHour in [true, false] {
                    for afternoon in [nil, true, false] as [Bool?] {
                        let start = hours.typingStart(number, afternoon: afternoon, twelveHour: twelveHour)
                        let end = hours.typingEnd(number, afternoon: afternoon, twelveHour: twelveHour)
                        #expect(holds(start), "start \(number) on \(hours)")
                        #expect(holds(end), "end \(number) on \(hours)")
                    }
                }
            }
        }
    }

    @Test func movingEitherEndToTheOtherHalfOfTheDayGivesHoursThatHold() {
        for hours in every {
            for afternoon in [true, false] {
                #expect(holds(hours.start(afternoon: afternoon)))
                #expect(holds(hours.end(afternoon: afternoon)))
            }
            // Asking for the half it is already in changes nothing.
            #expect(hours.start(afternoon: hours.start >= 12) == hours)
            #expect(hours.end(afternoon: hours.end >= 12) == hours)
        }
    }

    @Test func twelveIsNoonOrMidnight() {
        let hours = WorkHours.standard
        #expect(hours.typingStart(12, afternoon: true, twelveHour: true).start == 12)
        #expect(hours.typingStart(12, afternoon: false, twelveHour: true).start == 0)
        #expect(hours.typingStart(12, twelveHour: true).start == 0, "9 AM is in the morning, so 12 is 12 AM")
        #expect(hours.typingStart(12, twelveHour: false).start == 12)
        #expect(hours.typingEnd(12, twelveHour: true).end == 12, "the first 12 after 9 AM is noon")
        #expect(hours.typingEnd(12, afternoon: true, twelveHour: true).end == 12)
    }

    @Test func numbersNoClockHasAreTakenAsTheNearestHour() {
        let hours = WorkHours.standard
        #expect(hours.typingStart(0, twelveHour: true).start == 0)
        #expect(hours.typingStart(24, twelveHour: true) == WorkHours(start: 22, end: 23))
        #expect(hours.typingStart(99, twelveHour: false) == WorkHours(start: 22, end: 23))
        #expect(hours.typingStart(-1, twelveHour: false).start == 0)
        #expect(hours.typingEnd(0, twelveHour: false).end == 10, "an end before the start is the hour after it")
        #expect(hours.typingEnd(99, twelveHour: false).end == 23)
        #expect(hours.typingEnd(99, twelveHour: false).start == 15, "and the start follows, eight hours behind")
    }

    @Test func aStartTypedPastTheEndKeepsTheLengthWhereTheDayHasRoom() {
        let hours = WorkHours(start: 9, end: 12)
        #expect(hours.typingStart(14, twelveHour: false) == WorkHours(start: 14, end: 17))
        #expect(hours.typingStart(21, twelveHour: false) == WorkHours(start: 21, end: 23), "no room for three hours")
        #expect(hours.typingStart(12, twelveHour: false) == WorkHours(start: 12, end: 15), "a start at the end moves it too")
    }

    // MARK: The day

    @Test func theHoursBeginOnTheStrokeAndEndJustBeforeIt() {
        let hours = WorkHours.standard
        let utc = calendar()
        #expect(hours.current(at: date(18, 8, 59, 59), calendar: utc) == nil)
        #expect(hours.current(at: date(18, 9, 0, 0), calendar: utc) != nil)
        #expect(hours.current(at: date(18, 16, 59, 59), calendar: utc) != nil)
        #expect(hours.current(at: date(18, 17, 0, 0), calendar: utc) == nil)
    }

    @Test func onTheStrokeOfTheStartTheNextHoursAreTomorrows() {
        let hours = WorkHours.standard
        let utc = calendar()
        #expect(hours.next(after: date(18, 9, 0, 0), calendar: utc)?.start == date(19, 9))
        #expect(hours.next(after: date(18, 8, 59, 59), calendar: utc)?.start == date(18, 9))
        #expect(hours.next(after: date(18, 0, 0, 0), calendar: utc)?.start == date(18, 9))
    }

    @Test func fromFridayEveningAndAllWeekendTheNextHoursAreMondays() {
        let hours = WorkHours.standard
        let utc = calendar()
        // 20 November 2026 is a Friday, the 23rd a Monday.
        for moment in [date(20, 9, 0, 1), date(20, 18), date(21, 0), date(21, 12), date(22, 23, 59, 59)] {
            #expect(hours.next(after: moment, calendar: utc)?.start == date(23, 9))
        }
        #expect(hours.hours(on: date(21, 12), calendar: utc) == nil)
        #expect(hours.hours(on: date(22, 12), calendar: utc) == nil)
        #expect(hours.current(at: date(21, 10), calendar: utc) == nil)
    }

    @Test func theNextHoursCrossTheEndOfTheYear() {
        let utc = calendar()
        // 31 December 2026 is a Thursday, 1 January 2027 a Friday.
        let hours = WorkHours.standard.next(after: date(31, 18, month: 12), calendar: utc)
        #expect(hours.map { utc.dateComponents([.year, .month, .day, .hour], from: $0.start) }
            == DateComponents(year: 2027, month: 1, day: 1, hour: 9))
    }

    @Test func theDayIsTheOneOnTheUsersOwnClock() {
        let hours = WorkHours.standard
        let tokyo = calendar("Asia/Tokyo")
        // Ten at night on Friday in UTC is seven on Saturday morning in Tokyo.
        let moment = date(20, 22)
        #expect(hours.hours(on: moment, calendar: calendar()) != nil)
        #expect(hours.hours(on: moment, calendar: tokyo) == nil)
        // One in the morning on Wednesday in UTC is ten on Wednesday in Tokyo: in hours there.
        #expect(hours.current(at: date(18, 1), calendar: tokyo) != nil)
        #expect(hours.current(at: date(18, 1), calendar: calendar()) == nil)
    }

    @Test func nineIsStillNineAfterTheClocksChange() {
        let hours = WorkHours.standard
        let pacific = calendar("America/Los_Angeles")
        // The clocks go forward on Sunday 8 March 2026 and back on Sunday 1 November.
        for (friday, monday) in [((3, 6), (3, 9)), ((10, 30), (11, 2))] {
            let evening = date(friday.1, 18, month: friday.0, in: "America/Los_Angeles")
            let next = hours.next(after: evening, calendar: pacific)
            #expect(next.map { pacific.dateComponents([.month, .day, .hour, .minute], from: $0.start) }
                == DateComponents(month: monday.0, day: monday.1, hour: 9, minute: 0))
            #expect(next.map { pacific.component(.hour, from: $0.end) } == 17)
            #expect(next?.duration == 28800.0)
        }
    }

    @Test func theShortestAndTheLastHoursOfTheDay() {
        let utc = calendar()
        let last = WorkHours(start: 22, end: 23)
        #expect(last.length == 1)
        #expect(last.current(at: date(18, 22, 30), calendar: utc)?.duration == 3600)
        #expect(last.current(at: date(18, 23), calendar: utc) == nil)
        let first = WorkHours(start: 0, end: 1)
        #expect(first.current(at: date(18, 0, 0, 0), calendar: utc) != nil)
        #expect(first.next(after: date(18, 0, 0, 0), calendar: utc)?.start == date(19, 0))
    }

    // MARK: Names

    @Test func everyHourHasANameAndMidnightIsTheSameEitherWay() {
        let names = (0...23).map { WorkHours.name(ofHour: $0) }
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == 24, "no two hours of the day read the same")
        #expect(WorkHours.name(ofHour: 24) == WorkHours.name(ofHour: 0))
    }
}

@Suite("The list the Live Activity shows")
struct ActivityListTests {
    @Test func aTapGoesFromTheOpenListThroughEachListAndBack() {
        let lists = [UUID(), UUID(), UUID()]
        var choice: UUID?
        var seen: [UUID?] = []
        for _ in 0..<8 {
            choice = WorkHours.nextList(after: choice, in: lists)
            seen.append(choice)
        }
        #expect(seen == [lists[0], lists[1], lists[2], nil, lists[0], lists[1], lists[2], nil])
    }

    @Test func aChoiceThatIsGoneOrNoListsAtAllCountsAsTheOpenList() {
        let lists = [UUID(), UUID()]
        #expect(WorkHours.nextList(after: UUID(), in: lists) == lists[0])
        #expect(WorkHours.nextList(after: nil, in: []) == nil)
        #expect(WorkHours.nextList(after: UUID(), in: []) == nil)
        #expect(WorkHours.nextList(after: lists[0], in: [lists[0]]) == nil)
    }

    @Test func theChoiceIsKeptInSettingsAndNonsenseReadsAsTheOpenList() throws {
        let defaults = try #require(UserDefaults(suiteName: "activity-list-\(UUID().uuidString)"))
        #expect(WorkHours.chosenList(defaults: defaults) == nil)
        let id = UUID()
        defaults.set(id.uuidString, forKey: WorkHours.listKey)
        #expect(WorkHours.chosenList(defaults: defaults) == id)
        for nonsense in ["", "work", "1234"] {
            defaults.set(nonsense, forKey: WorkHours.listKey)
            #expect(WorkHours.chosenList(defaults: defaults) == nil)
        }
        defaults.set(42, forKey: WorkHours.listKey)
        #expect(WorkHours.chosenList(defaults: defaults) == nil)
    }

    @Test func theSnapshotGivesTheChosenListOrFallsBackToTheOpenOne() {
        let lists = ["life", "work"].map { PageSnapshot.List(id: UUID(), name: $0, lines: [], left: 0) }
        let snapshot = PageSnapshot(lists: lists, current: lists[0].id)
        #expect(snapshot.list(lists[1].id)?.name == "work")
        // Chosen, then deleted: the open list is shown.
        #expect(snapshot.list(UUID())?.name == "life")
    }
}
