import CloudKit
import Foundation
import SwiftData
import Testing

@testable import SansSerif

/// Lists and tasks where things are most likely to go wrong: blank and odd
/// text, the same thing done twice, the top and the bottom of a page, the
/// first and last moments of a day, and a great many tasks.
@MainActor
@Suite("Lists and tasks at the edges")
struct ListEdgeTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
    }

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0, _ second: Int = 0) -> Date {
        utc.date(from: DateComponents(
            year: year, month: month, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    // MARK: Text

    @Test func textIsTrimmedAndBlankTextIsRefused() throws {
        let list = try #require(try context.addList(named: "  errands \n"))
        #expect(list.name == "errands")
        #expect(try context.addList(named: " \n\t ") == nil)
        #expect(try context.addList(named: "") == nil)

        #expect(context.addTask("  Buy milk \n", to: list)?.text == "Buy milk")
        #expect(context.addTask("", to: list) == nil)
        #expect(context.addTask(" \n\t\u{00A0}", to: list) == nil)
        #expect(list.liveCount == 1)
        #expect(try context.lists().count == 1)
    }

    @Test(arguments: [
        "🧺 Laundry 👕👖",
        "שלום עולם",
        "مرحبا بالعالم",
        "Cafe\u{0301} at 3",
        "買い物に行く",
        "Line one\nLine two",
        "\"Quotes\" & <tags> \\ back",
        String(repeating: "long ", count: 2000) + "end",
    ])
    func unusualTextIsKeptAsItWasWritten(text: String) throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask(text, to: list))
        try context.save()
        #expect(task.text == text)
        #expect(list.liveTasks.map(\.text) == [text])
    }

    @Test func aListNameMayBeAnythingAndTwoListsMayShareOne() throws {
        let first = try #require(try context.addList(named: "🏡"))
        let second = try #require(try context.addList(named: "🏡"))
        #expect(first.id != second.id)
        #expect(first.order < second.order)
        context.addTask("Here", to: first)
        #expect(second.liveCount == 0)
        #expect(try context.lists().count == 2)
    }

    @Test func renamingTrimsAndABlankNameChangesNothing() throws {
        let list = try #require(try context.addList(named: "life"))
        context.rename(list, to: "  home life  ")
        #expect(list.name == "home life")
        context.rename(list, to: "   ")
        context.rename(list, to: "")
        #expect(list.name == "home life")
    }

    // MARK: Lists

    @Test func aNewListGoesAfterTheLastEvenWhenOneWasDeleted() throws {
        for name in ["a", "b", "c"] { try context.addList(named: name) }
        let middle = try #require(try context.lists().first { $0.name == "b" })
        let last = try #require(try context.lists().last)
        context.delete(middle)
        try context.save()
        try context.addList(named: "d")
        let lists = try context.lists()
        #expect(lists.map(\.name) == ["a", "c", "d"])
        #expect(lists.last?.order == last.order + 1)
        #expect(Set(lists.map(\.order)).count == 3)
    }

    @Test func theFirstListsComeBackOnlyWhenThereAreNoListsAtAll() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let lists = try context.lists()
        for list in lists.dropFirst() { context.delete(list) }
        try context.save()
        try PageStore.seedDefaultListsIfNeeded(in: context)
        #expect(try context.lists().map(\.name) == ["life"], "one list left is enough: nothing is added")

        for list in try context.lists() { context.delete(list) }
        try context.save()
        try PageStore.seedDefaultListsIfNeeded(in: context)
        #expect(try context.lists().map(\.name) == PageStore.defaultListNames)
    }

    @Test func deletingOneListLeavesTheOthersAsTheyWere() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        context.addTask("Stay", to: work)
        let struck = try #require(context.addTask("Struck", to: work))
        context.strike(struck)
        for number in 1...20 { context.addTask("Task \(number)", to: life) }
        try context.save()

        context.delete(life)
        try context.save()
        #expect(try context.lists().map(\.name) == ["work"])
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 2)
        #expect(work.liveTasks.map(\.text) == ["Stay"])
        #expect(work.archive().flatMap(\.tasks).map(\.text) == ["Struck"])
    }

    @Test func neighboursAtTheEndsAndOutsideTheRow() throws {
        for name in ["a", "b", "c"] { try context.addList(named: name) }
        let lists = try context.lists()
        let stranger = TaskList(name: "elsewhere", order: 9)
        #expect(lists.neighbour(of: lists[1], by: 0) === lists[1])
        #expect(lists.neighbour(of: lists[0], by: 2) === lists[2])
        #expect(lists.neighbour(of: lists[2], by: -2) === lists[0])
        #expect(lists.neighbour(of: lists[0], by: 3) == nil)
        #expect(lists.neighbour(of: lists[0], by: -1) == nil)
        #expect(lists.neighbour(of: lists[2], by: .max / 2) == nil)
        #expect(lists.neighbour(of: stranger, by: 0) == nil)
        #expect([TaskList]().neighbour(of: stranger, by: 1) == nil)
    }

    // MARK: Striking, circling, restoring

    @Test func strikingTwiceKeepsTheFirstStrike() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Once", to: list))
        let first = date(2026, 11, 18, 9)
        let pen = Stroke.encode(Stroke.generated(lines: 1, seed: 7))
        context.strike(task, strokeData: pen, by: "Ada", at: first)
        context.strike(task, strokeData: nil, by: "Ben", at: date(2026, 11, 19, 9))
        #expect(task.struckDate == first)
        #expect(task.struckBy == "Ada")
        #expect(task.strokeData == pen)
    }

    @Test func aCircleGoesOnAndOffAndNeverOnAStruckTask() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Matters", to: list))
        let when = date(2026, 11, 18)
        context.toggleCircle(task, at: when)
        #expect(task.isCircled)
        #expect(task.circledDate == when)
        context.toggleCircle(task)
        #expect(!task.isCircled)

        context.toggleCircle(task)
        context.strike(task)
        #expect(!task.isCircled, "done is done: the circle goes with the strike")
        context.toggleCircle(task)
        #expect(!task.isCircled, "a struck task cannot be circled")
        context.restore(task)
        #expect(!task.isCircled, "brought back, it is not circled again")
    }

    @Test func restoringClearsThePenLineAndKeepsThePlaceOnThePage() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = ["One", "Two", "Three"].compactMap { context.addTask($0, to: list) }
        context.strike(tasks[1], strokeData: Stroke.encode(Stroke.generated(lines: 2, seed: 3)), by: "Ada")
        #expect(list.liveTasks.map(\.text) == ["One", "Three"])
        context.restore(tasks[1])
        #expect(tasks[1].isLive)
        #expect(tasks[1].strokeData == nil)
        #expect(tasks[1].struckBy == nil)
        #expect(list.liveTasks.map(\.text) == ["One", "Two", "Three"])
        #expect(list.archive().isEmpty)

        // Restoring a task that was never struck is harmless.
        context.restore(tasks[0])
        #expect(list.liveTasks.map(\.text) == ["One", "Two", "Three"])
    }

    @Test func theCountIsOfLiveTasksOnly() throws {
        let list = try #require(try context.addList(named: "life"))
        #expect(list.liveCount == 0)
        #expect(list.liveTasks.isEmpty)
        let tasks = (1...5).compactMap { context.addTask("Task \($0)", to: list) }
        context.strike(tasks[0])
        context.strike(tasks[4])
        #expect(list.liveCount == 3)
        context.delete(tasks[2])
        try context.save()
        #expect(list.liveCount == 2)
        #expect(list.liveTasks.map(\.text) == ["Task 2", "Task 4"])
    }

    // MARK: Moving and placing

    @Test func movingToItsOwnListChangesNothing() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = ["One", "Two"].compactMap { context.addTask($0, to: list) }
        let order = tasks[0].order
        context.move(tasks[0], to: list)
        #expect(tasks[0].order == order)
        #expect(list.liveTasks.map(\.text) == ["One", "Two"])
    }

    @Test func aMovedTaskIsFirstInAnEmptyListAndLastInAFullOne() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        let home = try #require(try context.addList(named: "home"))
        let one = try #require(context.addTask("One", to: life))
        let two = try #require(context.addTask("Two", to: life))
        context.addTask("There", to: work)
        context.addTask("Also there", to: work)

        context.move(one, to: home)
        #expect(one.order == 0)
        #expect(home.liveTasks.map(\.text) == ["One"])
        context.move(two, to: work)
        #expect(work.liveTasks.map(\.text) == ["There", "Also there", "Two"])
        #expect(life.liveCount == 0)
    }

    @Test func aStruckTaskMovedTakesItsStrikeAlong() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        let task = try #require(context.addTask("Done", to: life))
        context.strike(task)
        context.move(task, to: work)
        #expect(!task.isLive)
        #expect(life.archive().isEmpty)
        #expect(work.archive().flatMap(\.tasks).map(\.text) == ["Done"])
        #expect(work.liveCount == 0)
    }

    @Test func placingAtTheTopTheBottomAndNowhere() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = ["One", "Two", "Three"].compactMap { context.addTask($0, to: list) }
        context.place(tasks[2], below: nil, above: tasks[0])
        #expect(list.liveTasks.map(\.text) == ["Three", "One", "Two"])
        context.place(tasks[2], below: tasks[1], above: nil)
        #expect(list.liveTasks.map(\.text) == ["One", "Two", "Three"])
        let order = tasks[1].order
        context.place(tasks[1], below: nil, above: nil)
        #expect(tasks[1].order == order, "with nothing to go between, it stays")
        #expect(list.liveTasks.map(\.text) == ["One", "Two", "Three"])
    }

    @Test func aTaskAloneOnThePageCanBePutBackWhereItIs() throws {
        let list = try #require(try context.addList(named: "life"))
        let only = try #require(context.addTask("Only", to: list))
        context.place(only, below: nil, above: nil)
        #expect(list.liveTasks.map(\.text) == ["Only"])
    }

    @Test func placingInTheSameGapAHundredTimesKeepsEveryTaskInItsPlace() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = (0..<100).compactMap { context.addTask("Task \($0)", to: list) }
        // Each task in turn goes just under the first: the gap halves every time,
        // until there is no room left and the page is numbered afresh.
        var under = tasks[1]
        for task in tasks.dropFirst(2) {
            context.place(task, below: tasks[0], above: under)
            under = task
        }
        let expected = ["Task 0"] + (2..<100).reversed().map { "Task \($0)" } + ["Task 1"]
        #expect(list.liveTasks.map(\.text) == expected)
        let orders = list.liveTasks.map(\.order)
        #expect(Set(orders).count == 100, "no two tasks share a place")
        #expect(orders.allSatisfy { $0.isFinite })
    }

    @Test func numberingAfreshCountsStruckTasksAndLeavesThemStruck() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = ["One", "Two", "Three", "Four"].compactMap { context.addTask($0, to: list) }
        context.strike(tasks[1])
        // No room between One and Three.
        tasks[0].order = 1
        tasks[2].order = 1 + 1e-9
        context.place(tasks[3], below: tasks[0], above: tasks[2])
        #expect(list.liveTasks.map(\.text) == ["One", "Four", "Three"])
        #expect(!tasks[1].isLive)
        #expect(Set((list.tasks ?? []).map(\.order)).count == 4)
    }

    // MARK: The archive and the day

    @Test func doneTodayRunsFromTheFirstMomentOfTheDayToTheLast() throws {
        let list = try #require(try context.addList(named: "life"))
        let now = date(2026, 11, 18, 15)
        let moments: [(String, Date)] = [
            ("Yesterday's last", date(2026, 11, 17, 23, 59, 59)),
            ("Midnight", date(2026, 11, 18, 0, 0, 0)),
            ("Morning", date(2026, 11, 18, 8)),
            ("Last second", date(2026, 11, 18, 23, 59, 59)),
            ("Tomorrow's first", date(2026, 11, 19, 0, 0, 0)),
        ]
        for (text, when) in moments {
            let task = try #require(context.addTask(text, to: list))
            context.strike(task, at: when)
        }
        context.addTask("Still live", to: list)
        #expect(list.doneToday(at: now, calendar: utc).map(\.text) == ["Last second", "Morning", "Midnight"])
        // The months below do not repeat today, and do not lose what came after it either.
        let below = list.archive(calendar: utc, before: now).flatMap(\.tasks).map(\.text)
        #expect(below == ["Yesterday's last"])
        #expect(list.archive(calendar: utc).flatMap(\.tasks).count == 5)
    }

    @Test func theSameMomentIsADifferentDayInAnotherPlace() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Late", to: list))
        // Half past midnight on the 1st in UTC is still the evening of the 31st in New York.
        context.strike(task, at: date(2026, 11, 1, 0, 30))
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!

        let here = try #require(list.archive(calendar: utc).first)
        let there = try #require(list.archive(calendar: newYork).first)
        #expect(utc.component(.month, from: here.month) == 11)
        #expect(newYork.component(.month, from: there.month) == 10)
        #expect(list.doneToday(at: date(2026, 11, 1, 9), calendar: utc).count == 1)
        #expect(list.doneToday(at: date(2026, 11, 1, 9), calendar: newYork).isEmpty)
    }

    @Test func theArchiveCrossesAYearNewestMonthFirst() throws {
        let list = try #require(try context.addList(named: "life"))
        let struck: [(String, Date)] = [
            ("Old", date(2024, 2, 29)),
            ("December", date(2025, 12, 31, 23, 59, 59)),
            ("January", date(2026, 1, 1, 0, 0, 0)),
            ("January again", date(2026, 1, 20)),
        ]
        for (text, when) in struck {
            let task = try #require(context.addTask(text, to: list))
            context.strike(task, at: when)
        }
        let months = list.archive(calendar: utc)
        #expect(months.map { $0.tasks.map(\.text) } == [["January again", "January"], ["December"], ["Old"]])
        #expect(months.map(\.month) == [date(2026, 1, 1, 0), date(2025, 12, 1, 0), date(2024, 2, 1, 0)])
        #expect(Set(months.map(\.id)).count == 3)
    }

    @Test func anEmptyListHasAnEmptyArchive() throws {
        let list = try #require(try context.addList(named: "life"))
        #expect(list.archive().isEmpty)
        #expect(list.doneToday().isEmpty)
        context.addTask("Live", to: list)
        #expect(list.archive().isEmpty)
        #expect(list.archive(before: .now).isEmpty)
        #expect(list.doneToday().isEmpty)
    }

    @Test func tasksStruckInTheSameInstantAreAllKept() throws {
        let list = try #require(try context.addList(named: "life"))
        let when = date(2026, 11, 18)
        for number in 1...10 {
            let task = try #require(context.addTask("Task \(number)", to: list))
            context.strike(task, at: when)
        }
        #expect(list.doneToday(at: when, calendar: utc).count == 10)
        #expect(list.archive(calendar: utc).first?.tasks.count == 10)
    }

    // MARK: The first page

    @Test func theFirstPageKeepsNothingWhenNothingWasWritten() throws {
        let list = try #require(try context.addList(named: "life"))
        context.finishGuide(ownTask: nil, struckLines: [], in: list)
        context.finishGuide(ownTask: "   ", struckLines: ["", " \n"], in: list)
        #expect((list.tasks ?? []).isEmpty)
    }

    @Test func theFirstPagesLinesAreStruckAtTheMomentItEnded() throws {
        let list = try #require(try context.addList(named: "life"))
        let when = date(2026, 11, 18, 10)
        context.finishGuide(ownTask: " Mine ", struckLines: ["Cross this off", "And this"], in: list, at: when)
        #expect(list.liveTasks.map(\.text) == ["Mine"])
        let struck = list.archive(calendar: utc).flatMap(\.tasks)
        #expect(Set(struck.map(\.text)) == ["Cross this off", "And this"])
        #expect(struck.allSatisfy { $0.struckDate == when })
    }

    // MARK: Shared lists

    @Test func whoWroteATaskIsKeptOnlyOnASharedList() throws {
        let own = try #require(try context.addList(named: "life"))
        let shared = try #require(try context.addList(named: "house"))
        shared.isShared = true
        #expect(context.addTask("Mine", to: own, by: "Ada")?.addedBy == nil)
        #expect(context.addTask("Ours", to: shared, by: "Ada")?.addedBy == "Ada")
        #expect(context.addTask("Unsigned", to: shared)?.addedBy == nil)
        let task = try #require(context.addTask("Bins", to: shared, by: "Ada"))
        context.strike(task, by: "Ben")
        #expect(task.addedBy == "Ada")
        #expect(task.struckBy == "Ben")
    }

    // MARK: Lists meeting

    @Test func threeCopiesOfAFirstListBecomeOneWithEverythingInIt() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let life = try #require(try context.lists().first { $0.name == "life" })
        life.createdDate = date(2026, 1, 1)
        context.addTask("First device", to: life)
        for (index, name) in ["Second device", "Third device"].enumerated() {
            let copy = TaskList(name: "life", order: Double(10 + index))
            copy.createdDate = date(2026, 2, 1 + index)
            context.insert(copy)
            context.addTask(name, to: copy)
            let done = try #require(context.addTask("\(name) done", to: copy))
            context.strike(done, at: date(2026, 3, 1 + index))
        }
        try context.save()

        #expect(try context.mergeDuplicateDefaultLists() == 2)
        #expect(try context.lists().map(\.name) == ["life", "work", "home"])
        #expect(life.liveTasks.map(\.text) == ["First device", "Second device", "Third device"])
        #expect(life.archive(calendar: utc).flatMap(\.tasks).map(\.text) == ["Third device done", "Second device done"])
        #expect(Set((life.tasks ?? []).map(\.order)).count == 5)
        #expect(try context.mergeDuplicateDefaultLists() == 0, "a second pass has nothing to do")
    }

    @Test func copiesMadeInTheSameInstantAreSettledTheSameWayEverywhere() throws {
        let when = date(2026, 1, 1)
        let first = TaskList(name: "work", order: 0)
        let second = TaskList(name: "work", order: 1)
        first.createdDate = when
        second.createdDate = when
        context.insert(first)
        context.insert(second)
        try context.save()
        let keeper = [first, second].min { $0.id.uuidString < $1.id.uuidString }
        try context.mergeDuplicateDefaultLists()
        #expect(try context.lists().map(\.id) == [keeper?.id])
    }

    @Test func aFirstListTheUserRenamedIsNotACopy() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        for name in ["Life", "life ", "lifes", "LIFE"] {
            context.insert(TaskList(name: name, order: 20))
        }
        try context.save()
        #expect(try context.mergeDuplicateDefaultLists() == 0)
        #expect(try context.lists().count == 7)
    }

    // MARK: Many, and kept

    @Test func aThousandTasksStayInTheOrderTheyWereWritten() throws {
        let list = try #require(try context.addList(named: "life"))
        for number in 0..<1000 { context.addTask("Task \(number)", to: list) }
        try context.save()
        let live = list.liveTasks
        #expect(live.count == 1000)
        #expect(live.first?.text == "Task 0")
        #expect(live.last?.text == "Task 999")
        #expect(zip(live, live.dropFirst()).allSatisfy { $0.order < $1.order })
        for task in live where task.order.truncatingRemainder(dividingBy: 2) == 0 { context.strike(task) }
        #expect(list.liveCount == 500)
        #expect(list.archive().flatMap(\.tasks).count == 500)
    }

    @Test func whatIsSavedIsThereForAnotherReader() throws {
        let list = try #require(try context.addList(named: "life"))
        context.addTask("Kept", to: list)
        let struck = try #require(context.addTask("Struck", to: list))
        context.toggleCircle(struck)
        context.strike(struck, strokeData: Stroke.encode(Stroke.generated(lines: 1, seed: 1)), by: "Ada")
        try context.save()

        let other = ModelContext(container)
        let lists = try other.fetch(FetchDescriptor<TaskList>())
        #expect(lists.map(\.name) == ["life"])
        let tasks = try other.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.order)]))
        #expect(tasks.map(\.text) == ["Kept", "Struck"])
        #expect(tasks[1].struckBy == "Ada")
        #expect(tasks[1].strokes.count == 1)
        #expect(tasks[1].list?.id == list.id)
        #expect(!tasks[1].isCircled)
    }

    @Test func whatWasNotSavedCanBeTakenBack() throws {
        let list = try #require(try context.addList(named: "life"))
        try context.save()
        context.addTask("Never kept", to: list)
        context.rollback()
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 0)
        #expect(list.name == "life")
    }
}

/// Two people writing on a shared list at once.
@MainActor
@Suite("The same order on every device")
struct SameOrderTests {
    /// Two devices, each with its own store, as two people have.
    private func device() throws -> (ModelContainer, CloudSync) {
        let container = try PageStore.makeContainer(inMemory: true)
        return (container, CloudSync(storingIn: container.mainContext))
    }

    private func record(_ id: UUID, in list: UUID, text: String, order: Double, created: Date) -> CKRecord {
        let record = CKRecord(
            recordType: RecordCoder.taskType,
            recordID: CKRecord.ID(recordName: id.uuidString, zoneID: RecordCoder.zoneID(for: list, owner: nil))
        )
        RecordCoder.write(.init(text: text, order: order, created: created), to: record)
        return record
    }

    @Test func tasksGivenTheSamePlaceAtOnceReadTheSameOnBothDevices() throws {
        let (first, firstSync) = try device()
        let (second, secondSync) = try device()
        let list = UUID()
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        // Three tasks written in the same moment by different people: all are
        // given place 4, and two of them the very same instant.
        let ids = [UUID(), UUID(), UUID()]
        let records = [
            record(ids[0], in: list, text: "Ada's", order: 4, created: moment.addingTimeInterval(1)),
            record(ids[1], in: list, text: "Ben's", order: 4, created: moment),
            record(ids[2], in: list, text: "Cy's", order: 4, created: moment),
            record(UUID(), in: list, text: "Earlier", order: 1, created: moment.addingTimeInterval(50)),
        ]
        // Each device hears of them in a different order.
        firstSync.applying { for one in records { firstSync.take(task: one) } }
        secondSync.applying { for one in records.reversed() { secondSync.take(task: one) } }

        let here = try #require(try first.mainContext.lists().first).liveTasks.map(\.text)
        let there = try #require(try second.mainContext.lists().first).liveTasks.map(\.text)
        #expect(here == there)
        #expect(here.first == "Earlier", "place comes first")
        #expect(here.last == "Ada's", "then whichever was written first")
        // Written in the same instant: by identity, which is the same everywhere.
        let tied = [("Ben's", ids[1]), ("Cy's", ids[2])].sorted { $0.1.uuidString < $1.1.uuidString }.map(\.0)
        #expect(Array(here[1...2]) == tied)

        let widgetHere = try first.mainContext.pageSnapshot(current: nil).lists[0].lines.map(\.text)
        let widgetThere = try second.mainContext.pageSnapshot(current: nil).lists[0].lines.map(\.text)
        #expect(widgetHere == here, "the widgets read as the page does")
        #expect(widgetThere == here)
    }

    @Test func listsGivenTheSamePlaceAtOnceStandInTheSameOrderOnBothDevices() throws {
        let (first, _) = try device()
        let (second, _) = try device()
        let moment = Date(timeIntervalSince1970: 1_800_000_000)
        let made: [(UUID, String, Date)] = [
            (UUID(), "trips", moment.addingTimeInterval(5)), (UUID(), "errands", moment), (UUID(), "garden", moment),
        ]
        for (container, lists) in [(first, made), (second, made.reversed())] {
            for (id, name, created) in lists {
                let list = TaskList(name: name, order: 3)
                list.id = id
                list.createdDate = created
                container.mainContext.insert(list)
            }
            try container.mainContext.save()
        }
        let here = try first.mainContext.lists().map(\.name)
        #expect(here == (try second.mainContext.lists().map(\.name)))
        #expect(here.last == "trips")
    }

    @Test func aTaskCarriedBetweenTwoThatShareAPlaceLandsBetweenThem() throws {
        let (device, _) = try device()
        let context = device.mainContext
        let list = try #require(try context.addList(named: "house"))
        let tasks = ["One", "Two", "Three"].compactMap { context.addTask($0, to: list) }
        tasks[0].order = 2
        tasks[1].order = 2
        let (upper, lower) = TaskItem.inPageOrder(tasks[0], tasks[1]) ? (tasks[0], tasks[1]) : (tasks[1], tasks[0])
        context.place(tasks[2], below: upper, above: lower)
        #expect(list.liveTasks.map(\.text) == [upper.text, "Three", lower.text])
        #expect(Set(list.liveTasks.map(\.order)).count == 3)
    }
}

@MainActor
@Suite("Deleting several tasks at once")
struct BulkDeleteTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
    }

    @Test func theTasksPickedAreDeletedAndTheRestKeepTheirOrder() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = (1...6).compactMap { context.addTask("Task \($0)", to: list) }
        try context.save()
        #expect(context.deleteTasks([tasks[1].id, tasks[3].id, tasks[5].id], in: list) == 3)
        try context.save()
        #expect(list.liveTasks.map(\.text) == ["Task 1", "Task 3", "Task 5"])
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 3)
        #expect(list.archive().isEmpty, "deleted is not done: nothing goes to the archive")
    }

    @Test func nothingPickedOrThingsThatAreGoneDeleteNothing() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Stays", to: list))
        try context.save()
        #expect(context.deleteTasks([], in: list) == 0)
        #expect(context.deleteTasks([UUID(), UUID()], in: list) == 0)
        try context.save()
        #expect(list.liveTasks.map(\.id) == [task.id])
    }

    @Test func aPickMadeOnOnePageNeverReachesAnother() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        let mine = try #require(context.addTask("Mine", to: life))
        let theirs = try #require(context.addTask("Theirs", to: work))
        try context.save()
        #expect(context.deleteTasks([mine.id, theirs.id], in: life) == 1)
        try context.save()
        #expect(life.liveCount == 0)
        #expect(work.liveTasks.map(\.text) == ["Theirs"])
    }

    @Test func everyTaskOfAListCanBeDeletedAtOnceStruckOnesIncluded() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = (0..<200).compactMap { context.addTask("Task \($0)", to: list) }
        context.strike(tasks[0])
        try context.save()
        #expect(context.deleteTasks(Set(tasks.map(\.id)), in: list) == 200)
        try context.save()
        #expect((list.tasks ?? []).isEmpty)
        #expect(try context.lists().count == 1, "the list itself stays")
    }

    @Test func whatWasDeletedTogetherIsSentToICloudAsGoneAndNotBroughtBack() throws {
        let sync = CloudSync(storingIn: context)
        let list = try #require(try context.addList(named: "life"))
        let tasks = (1...3).compactMap { context.addTask("Task \($0)", to: list) }
        try context.save()
        let ids = tasks.map { CKRecord.ID(recordName: $0.id.uuidString, zoneID: list.zoneID) }
        context.deleteTasks([tasks[0].id, tasks[1].id], in: list)
        try context.save()
        #expect(sync.record(for: ids[0]) == nil)
        #expect(sync.record(for: ids[1]) == nil)
        #expect(sync.record(for: ids[2]) != nil)
    }
}

@MainActor @Suite struct EditedBy {
    let container: ModelContainer
    init() throws { container = try PageStore.makeContainer(inMemory: true) }

    private func page() throws -> (ModelContext, TaskList, TaskList) {
        let context = container.mainContext
        let own = try #require(try context.addList(named: "mine"))
        let shared = try #require(try context.addList(named: "ours"))
        shared.isShared = true
        return (context, own, shared)
    }

    @Test func someoneElsesEditIsSaidInPlaceOfWhoAdded() throws {
        let (context, _, shared) = try page()
        let task = try #require(context.addTask("Bins", to: shared, by: "Ada"))
        #expect(task.byLine == "Added by Ada")
        context.edit(task, to: "Bins and bottles", by: "Ben")
        #expect(task.text == "Bins and bottles")
        #expect(task.addedBy == "Ada")
        #expect(task.byLine == "Edited by Ben")
    }

    @Test func editingOnesOwnTaskStillSaysAdded() throws {
        let (context, _, shared) = try page()
        let task = try #require(context.addTask("Bins", to: shared, by: "Ada"))
        context.edit(task, to: "Bottles", by: "Ada")
        #expect(task.byLine == "Added by Ada")
    }

    @Test func theLastEditorIsTheOneNamed() throws {
        let (context, _, shared) = try page()
        let task = try #require(context.addTask("Bins", to: shared, by: "Ada"))
        context.edit(task, to: "Bottles", by: "Ben")
        context.edit(task, to: "Boxes", by: "Cy")
        #expect(task.byLine == "Edited by Cy")
        context.edit(task, to: "Bins", by: "Ada")
        #expect(task.byLine == "Added by Ada")
    }

    @Test func nothingChangedNamesNobody() throws {
        let (context, own, shared) = try page()
        let task = try #require(context.addTask("Bins", to: shared, by: "Ada"))
        context.edit(task, to: " Bins ", by: "Ben")
        context.edit(task, to: "   ", by: "Ben")
        #expect(task.text == "Bins")
        #expect(task.editedBy == nil)
        // Without a name, the words change and nobody is named.
        context.edit(task, to: "Bottles")
        #expect(task.text == "Bottles")
        #expect(task.byLine == "Added by Ada")
        // The user's own lists go unsigned.
        let mine = try #require(context.addTask("Mine", to: own, by: "Ada"))
        context.edit(mine, to: "Still mine", by: "Ada")
        #expect(mine.editedBy == nil)
        #expect(mine.byLine == nil)
    }

    @Test func aTaskWithNoWriterKnownStillSaysWhoEdited() throws {
        let (context, _, shared) = try page()
        let task = try #require(context.addTask("Old", to: shared))
        context.edit(task, to: "New", by: "Ben")
        #expect(task.byLine == "Edited by Ben")
    }

    @Test func theEditorGoesToICloudAndBackAndUneditedTasksLeaveTheFieldAlone() throws {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: RecordCoder.zoneID(for: UUID(), owner: nil))
        let record = CKRecord(recordType: RecordCoder.taskType, recordID: id)
        var fields = RecordCoder.TaskFields(
            text: "Bins", order: 1, created: .now, struck: nil, strokes: nil, struckBy: nil, addedBy: "Ada", circled: nil
        )
        RecordCoder.write(fields, to: record)
        #expect(record.changedKeys().contains("editedBy") == false)
        fields.editedBy = "Ben"
        RecordCoder.write(fields, to: record)
        #expect(record.changedKeys().contains("editedBy"))
        #expect(RecordCoder.taskFields(of: record).editedBy == "Ben")
    }
}
