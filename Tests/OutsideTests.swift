import Foundation
import SwiftData
import Testing

@testable import SansSerif

@Suite("Working hours")
struct WorkHoursTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 18 November 2026 is a Wednesday.
    func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    @Test func nineToFiveHoldsTheWorkingDayAndNothingElse() {
        let hours = WorkHours.standard
        #expect(hours.current(at: date(day: 18, hour: 8, minute: 59), calendar: calendar) == nil)
        #expect(hours.current(at: date(day: 18, hour: 9), calendar: calendar) != nil)
        #expect(hours.current(at: date(day: 18, hour: 16, minute: 59), calendar: calendar)?.end == date(day: 18, hour: 17))
        #expect(hours.current(at: date(day: 18, hour: 17), calendar: calendar) == nil)
    }

    @Test func theWeekendIsNotWorked() {
        let hours = WorkHours.standard
        // Saturday the 21st.
        #expect(hours.current(at: date(day: 21, hour: 10), calendar: calendar) == nil)
    }

    @Test func theNextHoursAreLaterTodayOrTheNextWorkingDay() {
        let hours = WorkHours.standard
        #expect(hours.next(after: date(day: 18, hour: 7), calendar: calendar)?.start == date(day: 18, hour: 9))
        #expect(hours.next(after: date(day: 18, hour: 12), calendar: calendar)?.start == date(day: 19, hour: 9))
        // From Friday evening, over the weekend, to Monday.
        #expect(hours.next(after: date(day: 20, hour: 18), calendar: calendar)?.start == date(day: 23, hour: 9))
    }

    @Test func theEndAlwaysComesAfterTheStart() {
        #expect(WorkHours(start: 14, end: 9) == WorkHours(start: 14, end: 15))
        #expect(WorkHours(start: 40, end: 40) == WorkHours(start: 22, end: 23))
        #expect(WorkHours(start: -3, end: 5) == WorkHours(start: 0, end: 5))
    }

    @Test func steppingAnHourStaysOnTheRightSideOfTheOther() {
        let hours = WorkHours(start: 9, end: 17)
        #expect(hours.steppingStart(by: 1) == WorkHours(start: 10, end: 17))
        #expect(hours.steppingStart(by: -1) == WorkHours(start: 8, end: 17))
        // Past the end, the start comes round to midnight.
        #expect(WorkHours(start: 16, end: 17).steppingStart(by: 1) == WorkHours(start: 0, end: 17))
        #expect(hours.steppingEnd(by: -8) == WorkHours(start: 9, end: 23))
        #expect(WorkHours(start: 9, end: 23).steppingEnd(by: 1) == WorkHours(start: 9, end: 10))
    }

    @Test func aTypedNumberIsReadAsTheClockWouldSayIt() {
        let hours = WorkHours(start: 9, end: 17)
        // The end: the first such hour after the start.
        #expect(hours.typingEnd(6, twelveHour: true) == WorkHours(start: 9, end: 18))
        #expect(hours.typingEnd(11, twelveHour: true) == WorkHours(start: 9, end: 11))
        #expect(hours.typingEnd(12, twelveHour: true) == WorkHours(start: 9, end: 12))
        #expect(hours.typingEnd(9, twelveHour: true) == WorkHours(start: 9, end: 21))
        #expect(hours.typingEnd(18, twelveHour: true) == WorkHours(start: 9, end: 18))
        #expect(hours.typingEnd(6, twelveHour: false) == WorkHours(start: 9, end: 10))
        #expect(hours.typingEnd(18, twelveHour: false) == WorkHours(start: 9, end: 18))
        // The start keeps its half of the day.
        #expect(hours.typingStart(8, twelveHour: true) == WorkHours(start: 8, end: 17))
        #expect(hours.typingStart(12, twelveHour: true) == WorkHours(start: 0, end: 17))
        #expect(hours.typingStart(13, twelveHour: true) == WorkHours(start: 13, end: 17))
        #expect(WorkHours(start: 13, end: 17).typingStart(2, twelveHour: true) == WorkHours(start: 14, end: 17))
        // A start typed past the end takes the end along.
        #expect(hours.typingStart(18, twelveHour: false) == WorkHours(start: 18, end: 23))
        #expect(hours.typingStart(99, twelveHour: false) == WorkHours(start: 22, end: 23))
    }

    @Test func settingsKeepTheHours() throws {
        let defaults = try #require(UserDefaults(suiteName: "work-hours-test"))
        defaults.removePersistentDomain(forName: "work-hours-test")
        #expect(WorkHours(defaults: defaults) == .standard)
        defaults.set(7, forKey: WorkHours.startKey)
        defaults.set(15, forKey: WorkHours.endKey)
        #expect(WorkHours(defaults: defaults) == WorkHours(start: 7, end: 15))
    }
}

@MainActor
@Suite("Widgets and the Live Activity")
struct OutsideTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let page: SharedPage

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
        let name = "outside-test-\(UUID().uuidString)"
        page = SharedPage(defaults: try #require(UserDefaults(suiteName: name)))
    }

    @Test func theSnapshotShowsLiveTasksInPageOrder() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        context.addTask("Two", to: list)
        context.strike(one, at: .now.addingTimeInterval(-60))
        let snapshot = try context.pageSnapshot(current: list.id)
        #expect(snapshot.lists.map(\.name) == ["work"])
        #expect(snapshot.lists[0].lines.map(\.text) == ["Two"])
        #expect(snapshot.lists[0].left == 1)
        #expect(snapshot.list(nil)?.id == list.id)
    }

    @Test func aTaskStruckAMomentAgoStillShowsStruck() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        context.strike(one, at: .now)
        let lines = try context.pageSnapshot(current: nil).lists[0].lines
        #expect(lines.map(\.isLive) == [false])
    }

    @Test func longListsAreCutToWhatAWidgetCanShow() throws {
        let list = try #require(try context.addList(named: "work"))
        for number in 1...12 { context.addTask("Task \(number)", to: list) }
        let snapshot = try context.pageSnapshot(current: nil)
        #expect(snapshot.lists[0].lines.count == PageSnapshot.linesPerList)
        #expect(snapshot.lists[0].left == 12)
    }

    @Test func aTapOutsideStrikesAndTheAppTakesItIn() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        context.addTask("Two", to: list)
        page.snapshot = try context.pageSnapshot(current: list.id)

        #expect(page.toggle(task: one.id))
        // At once, where it shows.
        #expect(page.snapshot.lists[0].lines.map(\.isLive) == [false, true])
        #expect(page.snapshot.lists[0].left == 1)
        #expect(one.isLive)

        try context.apply(page.takePending())
        #expect(!one.isLive)
        #expect(list.liveTasks.map(\.text) == ["Two"])
        #expect(page.pending.isEmpty)
    }

    @Test func aSecondTapUndoesTheStrike() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        page.snapshot = try context.pageSnapshot(current: list.id)
        page.toggle(task: one.id)
        page.toggle(task: one.id)
        #expect(page.snapshot.lists[0].lines.map(\.isLive) == [true])
        #expect(page.snapshot.lists[0].left == 1)
        try context.apply(page.takePending())
        #expect(one.isLive)
    }

    @Test func aTapOnATaskThatIsGoneDoesNothing() throws {
        let list = try #require(try context.addList(named: "work"))
        context.addTask("One", to: list)
        page.snapshot = try context.pageSnapshot(current: list.id)
        #expect(!page.toggle(task: UUID()))
        #expect(page.pending.isEmpty)
        // A change for a task deleted meanwhile is let go.
        try context.apply([PendingChange(task: UUID(), struck: true, date: .now)])
        #expect(list.liveCount == 1)
    }
}
