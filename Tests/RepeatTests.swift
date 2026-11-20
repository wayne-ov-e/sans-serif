import CloudKit
import Foundation
import SwiftData
import Testing

@testable import SansSerif

/// Tasks that repeat: when they come back, and that there is only ever one to do.
@MainActor
struct RepeatTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let calendar = Calendar.current

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
    }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private func written(_ date: Date) -> String { Repeat.day(date, calendar: calendar) }

    // MARK: The rule

    @Test func everyRuleIsReadBackAsItWasWritten() {
        for text in ["daily", "weekly:2,4,6", "weekly:1", "monthly:1", "monthly:31", "monthly:last", "yearly:11-20", "yearly:2-29"] {
            #expect(Repeat(text)?.written == text)
        }
    }

    @Test func whatIsNotARuleIsNotRead() {
        for text in ["", "hourly", "weekly:", "weekly:0,8", "monthly:0", "monthly:32", "yearly:13-1", "yearly:11", "yearly:2-40"] {
            #expect(Repeat(text) == nil)
        }
    }

    @Test func dailyComesBackTomorrowHoweverLateInTheDay() {
        let rule = Repeat(.day)
        #expect(written(rule.next(after: day(2026, 11, 20, hour: 23), calendar: calendar)) == "2026-11-21")
        #expect(written(rule.next(after: day(2026, 12, 31, hour: 0), calendar: calendar)) == "2027-01-01")
    }

    @Test func weeklyComesBackOnItsDaysAndNeverTheSameDay() {
        // Nov 20, 2026 is a Friday. Monday is 2, Wednesday 4, Friday 6.
        let rule = Repeat(.week([2, 4, 6]))
        #expect(written(rule.next(after: day(2026, 11, 20), calendar: calendar)) == "2026-11-23")
        #expect(written(rule.next(after: day(2026, 11, 23), calendar: calendar)) == "2026-11-25")
        #expect(written(rule.next(after: day(2026, 11, 21), calendar: calendar)) == "2026-11-23")
        // One day a week, struck on that day: a week on.
        #expect(written(Repeat(.week([6])).next(after: day(2026, 11, 20), calendar: calendar)) == "2026-11-27")
    }

    @Test func monthlyFallsOnTheLastDayOfAShortMonth() {
        let thirtyFirst = Repeat(.month(31))
        #expect(written(thirtyFirst.next(after: day(2027, 1, 31), calendar: calendar)) == "2027-02-28")
        #expect(written(thirtyFirst.next(after: day(2027, 2, 28), calendar: calendar)) == "2027-03-31")
        #expect(written(thirtyFirst.next(after: day(2027, 3, 31), calendar: calendar)) == "2027-04-30")
        let last = Repeat(.month(Repeat.lastDay))
        #expect(written(last.next(after: day(2028, 2, 1), calendar: calendar)) == "2028-02-29")
        #expect(written(Repeat(.month(1)).next(after: day(2026, 11, 20), calendar: calendar)) == "2026-12-01")
    }

    @Test func yearlyKeepsItsDateAndALeapDayFallsOnTheTwentyEighth() {
        #expect(written(Repeat(.year(month: 11, day: 20)).next(after: day(2026, 11, 20), calendar: calendar)) == "2027-11-20")
        #expect(written(Repeat(.year(month: 3, day: 3)).next(after: day(2026, 11, 20), calendar: calendar)) == "2027-03-03")
        let leap = Repeat(.year(month: 2, day: 29))
        #expect(written(leap.next(after: day(2026, 11, 20), calendar: calendar)) == "2027-02-28")
        #expect(written(leap.next(after: day(2027, 2, 28), calendar: calendar)) == "2028-02-29")
    }

    @Test func theSmallWordSaysWhen() {
        #expect(Repeat(.day).mark == "daily")
        #expect(Repeat(.week([6, 2, 4])).mark == "mon wed fri")
        #expect(Repeat(.week([1])).mark == "sun")
        #expect(Repeat(.week(Set(1...7))).mark == "daily")
        #expect(Repeat(.month(1)).mark == "1st")
        #expect(Repeat(.month(2)).mark == "2nd")
        #expect(Repeat(.month(3)).mark == "3rd")
        #expect(Repeat(.month(11)).mark == "11th")
        #expect(Repeat(.month(22)).mark == "22nd")
        #expect(Repeat(.month(Repeat.lastDay)).mark == "last")
        #expect(Repeat(.year(month: 11, day: 20)).mark == "nov 20")
    }

    @Test func twoDevicesGiveTheNextCopyTheSameIdentity() {
        let one = Repeat.copyID(series: "A", day: "2026-11-21")
        #expect(one == Repeat.copyID(series: "A", day: "2026-11-21"))
        #expect(one != Repeat.copyID(series: "A", day: "2026-11-22"))
        #expect(one != Repeat.copyID(series: "B", day: "2026-11-21"))
    }

    // MARK: On the page

    @Test func aStruckRepeatGoesToTheArchiveAndWaitsForItsDay() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Take vitamins", to: list))
        context.addTask("Call the framer", to: list)
        context.setRepeat(Repeat(.day), on: task)
        #expect(list.liveTasks.map(\.text) == ["Take vitamins", "Call the framer"])

        let now = Date.now
        context.strike(task, at: now)
        // Gone from the page and from the count, and in the archive once.
        #expect(list.liveTasks.map(\.text) == ["Call the framer"])
        #expect(list.liveCount == 1)
        #expect(list.doneToday(at: now).map(\.text) == ["Take vitamins"])

        let series = try #require(task.series)
        let copies = context.copies(of: series)
        #expect(copies.count == 2)
        let next = try #require(copies.first { $0.isLive })
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        #expect(next.dueDay == written(tomorrow))
        #expect(next.isWaiting(at: now))
        #expect(next.repeats == "daily")
        #expect(next.order == task.order)
        // Tomorrow it is on the page, where it was.
        #expect(!next.isWaiting(at: tomorrow))
        #expect(next.id == Repeat.copyID(series: series, day: written(tomorrow)))
    }

    @Test func aTaskThatDoesNotRepeatLeavesNothingBehind() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Renew passport", to: list))
        context.strike(task)
        #expect((list.tasks ?? []).count == 1)
    }

    @Test func undoingTheStrikeTakesTheWaitingCopyAway() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Water the fig tree", to: list))
        context.setRepeat(Repeat(.week([2, 4, 6])), on: task)
        context.strike(task)
        #expect((list.tasks ?? []).count == 2)
        context.restore(task)
        try context.save()
        #expect((list.tasks ?? []).count == 1)
        #expect(task.isLive)
        #expect(task.repeats == "weekly:2,4,6")
        // Struck again, there is one waiting copy again, not two.
        context.strike(task)
        let series = try #require(task.series)
        #expect(context.copies(of: series).filter(\.isLive).count == 1)
    }

    @Test func anOldCopyBroughtBackBesideTheOneOnThePageIsAnOrdinaryTask() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Pay rent", to: list))
        context.setRepeat(Repeat(.day), on: task)
        let series = try #require(task.series)
        // Struck three days ago: its next copy has been due for two days and is on the page.
        context.strike(task, at: try #require(calendar.date(byAdding: .day, value: -3, to: .now)))
        let onPage = try #require(context.copies(of: series).first { $0.isLive })
        #expect(!onPage.isWaiting())
        context.restore(task)
        #expect(task.repeats == nil)
        #expect(task.series == nil)
        #expect(context.copies(of: series).filter(\.isLive).count == 1)
        #expect(list.liveCount == 2)
    }

    @Test func neverEndsTheRepeatAndNothingBringsItBack() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Take vitamins", to: list))
        context.setRepeat(Repeat(.day), on: task)
        let series = try #require(task.series)
        context.strike(task, at: try #require(calendar.date(byAdding: .day, value: -2, to: .now)))
        let second = try #require(context.copies(of: series).first { $0.isLive })
        context.setRepeat(nil, on: second)
        #expect(second.repeats == nil)
        #expect(task.repeats == nil)
        context.strike(second)
        #expect(context.tidyRepeats() == 0)
        #expect(list.liveCount == 0)
    }

    @Test func deletingTheOneOnThePageEndsTheRepeat() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Take vitamins", to: list))
        context.setRepeat(Repeat(.day), on: task)
        let series = try #require(task.series)
        context.strike(task, at: try #require(calendar.date(byAdding: .day, value: -2, to: .now)))
        let second = try #require(context.copies(of: series).first { $0.isLive })
        #expect(context.deleteTasks([second.id], in: list) == 1)
        try context.save()
        #expect(context.tidyRepeats() == 0)
        #expect(list.liveCount == 0)
        // What was done is still in the archive.
        #expect((list.tasks ?? []).map(\.text) == ["Take vitamins"])
    }

    @Test func theWordsAndTheListOfTheNextCopyAreTheStruckOnes() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        let task = try #require(context.addTask("Water the fig", to: life))
        context.setRepeat(Repeat(.day), on: task)
        context.edit(task, to: "Water the fig tree")
        context.move(task, to: work)
        context.strike(task)
        let series = try #require(task.series)
        let next = try #require(context.copies(of: series).first { $0.isLive })
        #expect(next.text == "Water the fig tree")
        #expect(next.list === work)
    }

    // MARK: Other devices

    @Test func twoCopiesStillToDoBecomeTheEarlierOne() throws {
        // Two people struck it offline on different days: each made a next copy.
        let list = try #require(try context.addList(named: "ours"))
        let done = try #require(context.addTask("Water the fig tree", to: list))
        context.setRepeat(Repeat(.day), on: done)
        let series = try #require(done.series)
        context.strike(done)
        let first = try #require(context.copies(of: series).first { $0.isLive })
        let later = TaskItem(text: done.text, order: done.order, list: list)
        later.repeats = done.repeats
        later.series = series
        later.dueDay = "9999-01-01"
        context.insert(later)
        try context.save()
        #expect(context.tidyRepeats() == 1)
        try context.save()
        let live = context.copies(of: series).filter(\.isLive)
        #expect(live.map(\.id) == [first.id])
        // And it is settled: a second look changes nothing.
        #expect(context.tidyRepeats() == 0)
    }

    @Test func aRepeatStruckOnABuildThatDoesNotKnowThemStillComesBack() throws {
        let list = try #require(try context.addList(named: "ours"))
        let task = try #require(context.addTask("Take vitamins", to: list))
        context.setRepeat(Repeat(.day), on: task)
        let series = try #require(task.series)
        // The older build only writes the strike.
        let struck = try #require(calendar.date(byAdding: .day, value: -1, to: .now))
        task.struckDate = struck
        try context.save()
        #expect(context.copies(of: series).count == 1)
        #expect(context.tidyRepeats() == 1)
        let next = try #require(context.copies(of: series).first { $0.isLive })
        // Struck yesterday, so it is due today, and on the page.
        #expect(next.dueDay == written(.now))
        #expect(list.liveTasks.map(\.id) == [next.id])
        #expect(context.tidyRepeats() == 0)
    }

    @Test func aRepeatStillOnThePageIsLeftAlone() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Take vitamins", to: list))
        context.setRepeat(Repeat(.day), on: task)
        try context.save()
        #expect(context.tidyRepeats() == 0)
        #expect((list.tasks ?? []).count == 1)
    }

    // MARK: iCloud and the widgets

    @Test func theRepeatGoesToICloudAndComesBack() {
        let zone = CKRecordZone.ID(zoneName: "list", ownerName: CKCurrentUserDefaultName)
        let record = CKRecord(recordType: RecordCoder.taskType, recordID: CKRecord.ID(recordName: "task", zoneID: zone))
        var fields = RecordCoder.TaskFields(text: "Pay rent", order: 1, created: .now)
        // A task that does not repeat never mentions the fields.
        RecordCoder.write(fields, to: record)
        #expect(record.changedKeys().contains("repeats") == false)
        #expect(record.changedKeys().contains("due") == false)
        #expect(record.changedKeys().contains("series") == false)
        fields.repeats = "monthly:1"
        fields.due = "2026-12-01"
        fields.series = "S"
        RecordCoder.write(fields, to: record)
        let read = RecordCoder.taskFields(of: record)
        #expect(read.repeats == "monthly:1")
        #expect(read.due == "2026-12-01")
        #expect(read.series == "S")
        // And a repeat ended is cleared there too.
        fields.repeats = nil
        RecordCoder.write(fields, to: record)
        #expect(RecordCoder.taskFields(of: record).repeats == nil)
    }

    @Test func aTaskTakesItsRepeatFromItsFields() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Pay rent", to: list))
        var fields = task.fields
        fields.repeats = "monthly:last"
        fields.due = "9999-01-31"
        fields.series = "S"
        task.fields = fields
        #expect(task.rule == Repeat(.month(Repeat.lastDay)))
        #expect(task.isWaiting())
        #expect(task.fields == fields)
    }

    @Test func theWidgetsDoNotShowACopyThatWaits() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Take vitamins", to: list))
        context.addTask("Call the framer", to: list)
        context.setRepeat(Repeat(.day), on: task)
        let now = Date.now
        context.strike(task, at: now.addingTimeInterval(-600))
        let page = try context.pageSnapshot(current: list.id, at: now)
        #expect(page.lists.first?.lines.map(\.text) == ["Call the framer"])
        #expect(page.lists.first?.left == 1)
    }
}

/// The widgets are drawn without the app: a repeat arrives there on its day.
@MainActor
struct RepeatWidgetTests {
    let calendar = Calendar.current

    @Test func aWaitingRepeatArrivesInTheWidgetOnItsDayWhereItWas() throws {
        let container = try PageStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let list = try #require(try context.addList(named: "life"))
        context.addTask("Call the framer", to: list)
        let task = try #require(context.addTask("Take vitamins", to: list))
        context.addTask("Write to Grandma", to: list)
        context.setRepeat(Repeat(.day), on: task)
        let now = Date.now
        context.strike(task, at: now.addingTimeInterval(-600))

        let page = try #require(try context.pageSnapshot(current: list.id, at: now).lists.first)
        #expect(page.lines.map(\.text) == ["Call the framer", "Write to Grandma"])
        #expect(page.waiting?.count == 1)
        // Today nothing arrives.
        #expect(page.arriving(at: now) == page)

        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)))
        #expect(page.arrivals(after: now) == [tomorrow])
        let then = page.arriving(at: tomorrow)
        #expect(then.lines.map(\.text) == ["Call the framer", "Take vitamins", "Write to Grandma"])
        #expect(then.left == 3)
        #expect(then.waiting?.isEmpty == true)
        // Asked twice, it is there once.
        #expect(then.arriving(at: tomorrow).lines.count == 3)
    }

    @Test func aSnapshotFromAnOlderBuildStillReads() throws {
        let old = #"{"lists":[{"id":"00000000-0000-0000-0000-000000000001","name":"life","lines":[],"left":0}]}"#
        let page = try JSONDecoder().decode(PageSnapshot.self, from: Data(old.utf8))
        #expect(page.lists.first?.waiting == nil)
        #expect(page.arriving(at: .now) == page)
    }
}
