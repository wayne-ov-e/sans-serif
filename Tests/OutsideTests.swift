import CloudKit
import CoreGraphics
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
        // Before the start, the end comes round to the last hour of the day, and the start follows it.
        #expect(hours.steppingEnd(by: -8) == WorkHours(start: 15, end: 23))
        #expect(WorkHours(start: 15, end: 23).steppingEnd(by: 1) == WorkHours(start: 15, end: 16))
    }

    @Test func aTypedNumberIsReadAsTheClockWouldSayIt() {
        let hours = WorkHours(start: 9, end: 17)
        // The end: the first such hour after the start.
        #expect(hours.typingEnd(4, twelveHour: true) == WorkHours(start: 9, end: 16))
        // Later than eight hours on, the start comes along behind it.
        #expect(hours.typingEnd(6, twelveHour: true) == WorkHours(start: 10, end: 18))
        #expect(hours.typingEnd(11, twelveHour: true) == WorkHours(start: 9, end: 11))
        #expect(hours.typingEnd(12, twelveHour: true) == WorkHours(start: 9, end: 12))
        #expect(hours.typingEnd(9, twelveHour: true) == WorkHours(start: 13, end: 21))
        #expect(hours.typingEnd(18, twelveHour: true) == WorkHours(start: 10, end: 18))
        #expect(hours.typingEnd(6, twelveHour: false) == WorkHours(start: 9, end: 10))
        #expect(hours.typingEnd(18, twelveHour: false) == WorkHours(start: 10, end: 18))
        // The start keeps its half of the day.
        #expect(hours.typingStart(8, twelveHour: true) == WorkHours(start: 8, end: 17))
        #expect(hours.typingStart(12, twelveHour: true) == WorkHours(start: 0, end: 17))
        #expect(hours.typingStart(13, twelveHour: true) == WorkHours(start: 13, end: 17))
        #expect(WorkHours(start: 13, end: 17).typingStart(2, twelveHour: true) == WorkHours(start: 14, end: 17))
        // A start typed past the end takes the end along.
        #expect(hours.typingStart(18, twelveHour: false) == WorkHours(start: 18, end: 23))
        #expect(hours.typingStart(99, twelveHour: false) == WorkHours(start: 22, end: 23))
    }

    @Test func amAndPmMoveAnHourToTheOtherHalfOfTheDay() {
        let hours = WorkHours(start: 9, end: 17)
        #expect(hours.end(afternoon: false) == WorkHours(start: 9, end: 10))
        #expect(WorkHours(start: 6, end: 9).end(afternoon: true) == WorkHours(start: 13, end: 21))
        #expect(WorkHours(start: 6, end: 13).end(afternoon: false) == WorkHours(start: 6, end: 7))
        // A start moved past the end takes the end along.
        #expect(WorkHours(start: 6, end: 9).start(afternoon: true) == WorkHours(start: 18, end: 21))
        #expect(WorkHours(start: 13, end: 17).start(afternoon: false) == WorkHours(start: 1, end: 17))
        // A half that was asked for is kept when the number is typed after it.
        #expect(WorkHours(start: 6, end: 14).typingEnd(8, afternoon: false, twelveHour: true) == WorkHours(start: 6, end: 8))
        #expect(hours.typingEnd(8, afternoon: true, twelveHour: true) == WorkHours(start: 12, end: 20))
        #expect(hours.typingStart(1, afternoon: true, twelveHour: true) == WorkHours(start: 13, end: 17))
    }

    @Test func theHoursAreNeverLongerThanEight() {
        // Asked for outright, the end is brought in.
        #expect(WorkHours(start: 6, end: 21) == WorkHours(start: 6, end: 14))
        #expect(WorkHours.standard.length == WorkHours.longest)
        // An earlier start brings the end with it. A later end brings the start.
        #expect(WorkHours.standard.steppingStart(by: -2) == WorkHours(start: 7, end: 15))
        #expect(WorkHours.standard.steppingEnd(by: 3) == WorkHours(start: 12, end: 20))
        // Shorter hours are left alone.
        #expect(WorkHours(start: 10, end: 15).steppingEnd(by: 1) == WorkHours(start: 10, end: 16))
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
        for number in 1...30 { context.addTask("Task \(number)", to: list) }
        let snapshot = try context.pageSnapshot(current: nil)
        #expect(snapshot.lists[0].lines.count == PageSnapshot.linesPerList)
        #expect(snapshot.lists[0].left == 30)
    }

    @Test func circledTasksComeFirstInTheWidgets() throws {
        let list = try #require(try context.addList(named: "work"))
        context.addTask("One", to: list)
        let two = try #require(context.addTask("Two", to: list))
        let three = try #require(context.addTask("Three", to: list))
        context.toggleCircle(three, at: .now.addingTimeInterval(-10))
        context.toggleCircle(two)
        #expect(try context.pageSnapshot(current: nil).lists[0].lines.map(\.text) == ["Three", "Two", "One"])
        // Circled again, the circle is cleared.
        context.toggleCircle(three)
        #expect(!three.isCircled)
        #expect(try context.pageSnapshot(current: nil).lists[0].lines.map(\.text) == ["Two", "One", "Three"])
    }

    @Test func aStrikeTakesTheCircleWithIt() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        context.toggleCircle(one)
        #expect(one.isCircled)
        context.strike(one)
        #expect(!one.isCircled)
        // A struck task cannot be circled.
        context.toggleCircle(one)
        #expect(!one.isCircled)
    }

    @Test func aLoopGoesRoundAndComesBack() {
        let round = stride(from: 0.0, through: 2 * Double.pi + 0.3, by: 0.2).map {
            CGPoint(x: 100 + 70 * cos($0), y: 40 + 26 * sin($0))
        }
        #expect(TaskLine.closes(round))
        // Most of the way round is enough: the hand does not have to meet where it began.
        let most = stride(from: 0.0, through: 1.55 * Double.pi, by: 0.2).map {
            CGPoint(x: 100 + 70 * cos($0), y: 40 + 14 * sin($0))
        }
        #expect(TaskLine.closes(most))
        // And the other way round.
        #expect(TaskLine.closes(most.reversed()))
        // A strike that wandered is not a loop: it never came back.
        #expect(!TaskLine.closes([CGPoint(x: 20, y: 40), CGPoint(x: 90, y: 52), CGPoint(x: 160, y: 66), CGPoint(x: 230, y: 70)]))
        // Nor is a small scribble.
        #expect(!TaskLine.closes([CGPoint(x: 20, y: 40), CGPoint(x: 30, y: 50), CGPoint(x: 24, y: 44), CGPoint(x: 21, y: 41)]))
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

    @Test func aWidgetDrawnLateStillShowsTheStrikeThenLetsItLeave() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        context.addTask("Two", to: list)
        let tapped = Date.now
        page.snapshot = try context.pageSnapshot(current: list.id, at: tapped)
        page.toggle(task: one.id, at: tapped)

        // The system draws the widget again five seconds after the tap.
        let drawn = tapped.addingTimeInterval(5)
        let first = page.timeline(at: drawn)
        let leaves = try #require(first.leaving[one.id])
        #expect(leaves == drawn.addingTimeInterval(PageSnapshot.linger))
        #expect(first.snapshot.lists[0].shown(at: drawn, leaving: first.leaving).lines.map(\.isLive) == [false, true])
        #expect(first.snapshot.lists[0].shown(at: leaves, leaving: first.leaving).lines.map(\.text) == ["Two"])

        // Drawn again later, the line does not come back.
        let again = page.timeline(at: drawn.addingTimeInterval(10))
        #expect(again.leaving[one.id] == leaves)
        #expect(again.snapshot.lists[0].shown(at: drawn.addingTimeInterval(10), leaving: again.leaving).lines.map(\.text) == ["Two"])
    }

    @Test func aLineStruckLongAgoIsNotShownAgain() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        let struck = Date.now
        page.snapshot = try context.pageSnapshot(current: list.id, at: struck)
        page.toggle(task: one.id, at: struck)
        let later = struck.addingTimeInterval(PageSnapshot.keep + 1)
        let timeline = page.timeline(at: later)
        #expect(timeline.snapshot.lists[0].shown(at: later, leaving: timeline.leaving).lines.isEmpty)
    }

    @Test func undoingAStrikeForgetsWhenItWasToLeave() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        page.snapshot = try context.pageSnapshot(current: list.id)
        page.toggle(task: one.id)
        #expect(page.timeline().leaving[one.id] != nil)
        page.toggle(task: one.id)
        #expect(page.timeline().leaving.isEmpty)
        #expect(page.leaving.isEmpty)
    }

    @Test func struckLinesDoNotTakeTheRoomOfLiveOnes() throws {
        let list = try #require(try context.addList(named: "work"))
        let tasks = (1...30).compactMap { context.addTask("Task \($0)", to: list) }
        context.strike(tasks[0], at: .now)
        let lines = try context.pageSnapshot(current: nil).lists[0].lines
        #expect(lines.count(where: \.isLive) == PageSnapshot.linesPerList)
        #expect(lines.first?.isLive == false)
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

@MainActor
@Suite("Lists in iCloud")
struct RecordCoderTests {
    @Test func everyListHasAZoneOfItsOwn() {
        let id = UUID()
        let zone = RecordCoder.zoneID(for: id, owner: nil)
        #expect(zone.zoneName == "list-\(id.uuidString)")
        #expect(zone.ownerName == CKCurrentUserDefaultName)
        #expect(RecordCoder.listID(fromZone: zone.zoneName) == id)
        #expect(RecordCoder.listID(fromZone: "com.apple.coredata.cloudkit.zone") == nil)
        // A list someone else shared lives in their zone.
        #expect(RecordCoder.zoneID(for: id, owner: "_abc").ownerName == "_abc")
    }

    @Test func aTaskGoesToItsRecordAndBackUnchanged() {
        let zone = RecordCoder.zoneID(for: UUID(), owner: nil)
        let record = CKRecord(recordType: RecordCoder.taskType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        let fields = RecordCoder.TaskFields(
            text: "Call the framer", order: 2.5, created: Date(timeIntervalSince1970: 1_000),
            struck: Date(timeIntervalSince1970: 2_000), strokes: Data([1, 2, 3]),
            struckBy: "Sam", addedBy: "Wayne", circled: nil
        )
        RecordCoder.write(fields, to: record)
        #expect(RecordCoder.taskFields(of: record) == fields)
        // Cleared again: the empty values are written too, not left as they were.
        var live = fields
        live.struck = nil
        live.strokes = nil
        live.struckBy = nil
        live.circled = Date(timeIntervalSince1970: 3_000)
        RecordCoder.write(live, to: record)
        #expect(RecordCoder.taskFields(of: record) == live)
    }

    @Test func aListGoesToItsRecordAndBackUnchanged() {
        let zone = RecordCoder.zoneID(for: UUID(), owner: nil)
        let record = CKRecord(recordType: RecordCoder.listType, recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone))
        let fields = RecordCoder.ListFields(name: "work", order: 1, created: Date(timeIntervalSince1970: 500))
        RecordCoder.write(fields, to: record)
        #expect(RecordCoder.listFields(of: record) == fields)
    }

    @Test func whatICloudSaidAboutARecordIsKeptAndFoundAgain() {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: RecordCoder.zoneID(for: UUID(), owner: nil))
        let record = CKRecord(recordType: RecordCoder.taskType, recordID: id)
        let kept = RecordCoder.systemFields(of: record)
        let again = RecordCoder.record(type: RecordCoder.taskType, id: id, systemFields: kept)
        #expect(again.recordID == id)
        #expect(again.recordType == RecordCoder.taskType)
        // Kept for another record, it is not used: a new one is made.
        let other = CKRecord.ID(recordName: UUID().uuidString, zoneID: id.zoneID)
        #expect(RecordCoder.record(type: RecordCoder.taskType, id: other, systemFields: kept).recordID == other)
        #expect(RecordCoder.record(type: RecordCoder.taskType, id: other, systemFields: Data([9])).recordID == other)
    }

    @Test func onASharedListATaskSaysWhoWroteIt() throws {
        let container = try PageStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let list = try #require(try context.addList(named: "trip"))
        #expect(context.addTask("Mine", to: list, by: "Wayne")?.addedBy == nil)
        list.isShared = true
        #expect(context.addTask("Ours", to: list, by: "Wayne")?.addedBy == "Wayne")
        #expect(list.fields == RecordCoder.ListFields(name: "trip", order: list.order, created: list.createdDate))
    }
}
