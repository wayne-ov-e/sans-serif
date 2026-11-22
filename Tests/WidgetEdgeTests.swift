import Foundation
import SwiftData
import Testing

@testable import SansSerif

/// The shared drawer between the app and its widgets, where either side may
/// find it empty, damaged, or changed by the other since it last looked.
@MainActor
@Suite("Widgets at the edges")
struct WidgetEdgeTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let page: SharedPage
    let folder: URL

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
        folder = FileManager.default.temporaryDirectory.appending(path: "widget-edge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "widget-edge-\(UUID().uuidString)"
        // Kept in files, as on a device.
        page = SharedPage(defaults: try #require(UserDefaults(suiteName: name)), directory: folder)
    }

    private func line(_ text: String, struck: Date? = nil) -> PageSnapshot.Line {
        PageSnapshot.Line(id: UUID(), text: text, struck: struck)
    }

    private func list(_ name: String, _ lines: [PageSnapshot.Line]) -> PageSnapshot.List {
        PageSnapshot.List(id: UUID(), name: name, lines: lines, left: lines.count(where: \.isLive))
    }

    // MARK: The drawer

    @Test func anEmptyDrawerReadsAsNothing() {
        #expect(page.snapshot == PageSnapshot())
        #expect(page.pending.isEmpty)
        #expect(page.leaving.isEmpty)
        #expect(page.takePending().isEmpty)
        #expect(page.snapshot.list(nil) == nil)
        #expect(!page.toggle(task: UUID()))
        #expect(page.timeline().leaving.isEmpty)
    }

    @Test func whatIsPutInTheDrawerIsReadBackFromItsFiles() throws {
        let work = list("work", [line("One"), line("Two", struck: Date(timeIntervalSince1970: 1_800_000_000))])
        page.snapshot = PageSnapshot(lists: [work], current: work.id)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "pageSnapshot.json").path))

        // Another reader of the same folder: the widget, in a process of its own.
        let widget = SharedPage(defaults: page.defaults, directory: folder)
        #expect(widget.snapshot == page.snapshot)
        #expect(widget.toggle(task: work.lines[0].id))
        #expect(page.pending.map(\.task) == [work.lines[0].id], "the app sees what the widget did")
        #expect(page.snapshot.lists[0].left == 0)
    }

    @Test func damagedFilesReadAsNothingAndAreWrittenOver() throws {
        for name in ["pageSnapshot", "pendingChanges", "leaving"] {
            try Data("{ not json".utf8).write(to: folder.appending(path: "\(name).json"))
        }
        #expect(page.snapshot == PageSnapshot())
        #expect(page.pending.isEmpty)
        #expect(page.leaving.isEmpty)
        #expect(!page.toggle(task: UUID()))

        let work = list("work", [line("One")])
        page.snapshot = PageSnapshot(lists: [work])
        #expect(page.toggle(task: work.lines[0].id))
        #expect(page.pending.count == 1)
        #expect(!page.snapshot.lists[0].lines[0].isLive)
    }

    @Test func aFolderThatIsNotThereLosesWhatIsWrittenWithoutStopping() {
        let nowhere = SharedPage(
            defaults: page.defaults, directory: folder.appending(path: "missing/deeper")
        )
        nowhere.snapshot = PageSnapshot(lists: [list("work", [line("One")])])
        #expect(nowhere.snapshot == PageSnapshot())
        #expect(!nowhere.toggle(task: UUID()))
        nowhere.reset()
    }

    @Test func clearingTheDrawerLeavesNothingBehind() throws {
        let work = list("work", [line("One")])
        page.snapshot = PageSnapshot(lists: [work])
        page.toggle(task: work.lines[0].id)
        _ = page.timeline()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).count == 3)
        page.reset()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        page.reset()
        #expect(page.snapshot == PageSnapshot())
    }

    @Test func aSnapshotWrittenByAnOlderBuildIsStillRead() throws {
        let id = UUID()
        let old = """
        {"lists":[{"id":"\(id.uuidString)","name":"work","left":1,"lines":[{"id":"\(UUID().uuidString)","text":"One"}]}]}
        """
        try Data(old.utf8).write(to: folder.appending(path: "pageSnapshot.json"))
        let snapshot = page.snapshot
        #expect(snapshot.current == nil)
        #expect(snapshot.lists.map(\.name) == ["work"])
        #expect(snapshot.lists[0].lines[0].isLive)
    }

    // MARK: Choosing the list and its lines

    @Test func aWidgetWhoseListIsGoneShowsTheOpenOneOrTheFirst() {
        let lists = [list("life", []), list("work", [line("One")]), list("home", [])]
        var snapshot = PageSnapshot(lists: lists, current: lists[1].id)
        #expect(snapshot.list(lists[2].id)?.name == "home")
        #expect(snapshot.list(UUID())?.name == "work", "the list last open in the app")
        #expect(snapshot.list(nil)?.name == "work")
        snapshot.current = UUID()
        #expect(snapshot.list(UUID())?.name == "life", "or the first, when that is gone too")
        snapshot.current = nil
        #expect(snapshot.list(nil)?.name == "life")
        #expect(PageSnapshot().list(lists[0].id) == nil)
    }

    @Test func aWidgetTakesAsManyLinesAsItHasRoomFor() {
        let work = list("work", [line("One", struck: .now), line("Two"), line("Three")])
        #expect(work.lines(0).isEmpty)
        #expect(work.lines(2).map(\.text) == ["One", "Two"])
        #expect(work.lines(99).count == 3)
        #expect(work.next?.text == "Two", "what is next is the first that is not struck")
        #expect(list("done", [line("One", struck: .now)]).next == nil)
        #expect(list("empty", []).next == nil)
    }

    // MARK: Taps

    @Test func aTapFindsItsTaskInWhicheverListItIsIn() {
        let life = list("life", [line("A")])
        let work = list("work", [line("B"), line("C")])
        page.snapshot = PageSnapshot(lists: [life, work], current: life.id)
        #expect(page.toggle(task: work.lines[1].id))
        let after = page.snapshot
        #expect(after.lists[0] == life, "the other list is untouched")
        #expect(after.lists[1].lines.map(\.isLive) == [true, false])
        #expect(after.lists[1].left == 1)
        #expect(after.current == life.id)
    }

    @Test func manyTapsOnOneTaskAreAllKeptAndTheLastOneStands() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        page.snapshot = try context.pageSnapshot(current: list.id)
        for _ in 0..<5 { page.toggle(task: one.id) }
        #expect(page.pending.map(\.struck) == [true, false, true, false, true])
        #expect(page.snapshot.lists[0].left == 0)
        try context.apply(page.takePending())
        #expect(!one.isLive)
        #expect(page.pending.isEmpty)
        #expect(page.takePending().isEmpty, "taken once, they are not handed over again")
    }

    @Test func tapsOnSeveralTasksGoInInTheOrderTheyWereMade() throws {
        let list = try #require(try context.addList(named: "work"))
        let tasks = ["One", "Two", "Three"].compactMap { context.addTask($0, to: list) }
        page.snapshot = try context.pageSnapshot(current: list.id)
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        page.toggle(task: tasks[2].id, at: first)
        page.toggle(task: tasks[0].id, at: first.addingTimeInterval(1))
        try context.apply(page.takePending())
        #expect(list.liveTasks.map(\.text) == ["Two"])
        #expect(tasks[2].struckDate == first)
        #expect(tasks[0].struckDate == first.addingTimeInterval(1))
    }

    @Test func aTapOnWhatTheAppHasSinceChangedDoesNoHarm() throws {
        let list = try #require(try context.addList(named: "work"))
        let struckInApp = try #require(context.addTask("Struck in the app", to: list))
        let deleted = try #require(context.addTask("Deleted", to: list))
        let live = try #require(context.addTask("Live", to: list))
        page.snapshot = try context.pageSnapshot(current: list.id)
        let early = Date(timeIntervalSince1970: 1_800_000_000)

        // Meanwhile, in the app.
        context.strike(struckInApp, by: "Ada", at: early)
        context.delete(deleted)
        try context.save()

        try context.apply([
            PendingChange(task: struckInApp.id, struck: true, date: early.addingTimeInterval(60)),
            PendingChange(task: deleted.id, struck: true, date: early),
            PendingChange(task: live.id, struck: false, date: early),
        ])
        #expect(struckInApp.struckDate == early, "the first strike stands")
        #expect(struckInApp.struckBy == "Ada")
        #expect(live.isLive, "undoing a strike that is not there changes nothing")
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 2)
        try context.apply([])
    }

    // MARK: When a struck line leaves

    @Test func linesStruckAtDifferentDrawingsLeaveAtTheirOwnTimes() {
        let work = list("work", [line("One"), line("Two"), line("Three")])
        page.snapshot = PageSnapshot(lists: [work])
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        page.toggle(task: work.lines[0].id, at: start)
        let first = page.timeline(at: start)
        page.toggle(task: work.lines[2].id, at: start.addingTimeInterval(1))
        let second = page.timeline(at: start.addingTimeInterval(1))

        #expect(second.leaving[work.lines[0].id] == first.leaving[work.lines[0].id])
        #expect(second.leaving[work.lines[2].id] == start.addingTimeInterval(1 + PageSnapshot.linger))
        let shown = { (date: Date) in second.snapshot.lists[0].shown(at: date, leaving: second.leaving).lines.map(\.text) }
        #expect(shown(start.addingTimeInterval(1)) == ["One", "Two", "Three"])
        #expect(shown(start.addingTimeInterval(PageSnapshot.linger)) == ["Two", "Three"])
        #expect(shown(start.addingTimeInterval(1 + PageSnapshot.linger)) == ["Two"])
    }

    @Test func aLineLeavesOnTheStrokeOfItsTimeAndNotBefore() {
        let struck = line("One", struck: .now)
        let work = list("work", [struck, line("Two")])
        let leaves = Date(timeIntervalSince1970: 1_800_000_000)
        let leaving = [struck.id: leaves]
        #expect(work.shown(at: leaves.addingTimeInterval(-0.001), leaving: leaving).lines.count == 2)
        #expect(work.shown(at: leaves, leaving: leaving).lines.map(\.text) == ["Two"])
        // A struck line nobody gave a time to has left. A live line never does.
        #expect(work.shown(at: leaves, leaving: [:]).lines.map(\.text) == ["Two"])
        #expect(work.shown(at: .distantFuture, leaving: [work.lines[1].id: .distantPast]).lines.map(\.text) == ["Two"])
    }

    @Test func leaveTimesAreForgottenForLinesThatAreGoneOrLiveAgain() {
        let work = list("work", [line("One", struck: .now), line("Two")])
        let snapshot = PageSnapshot(lists: [work])
        let stale: [UUID: Date] = [UUID(): .now, work.lines[1].id: .now, work.lines[0].id: .distantFuture]
        let leaving = snapshot.leaving(known: stale, at: .now)
        #expect(leaving == [work.lines[0].id: .distantFuture])
    }

    @Test func aLineIsFreshUntilTheSnapshotWouldHaveDroppedIt() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let justInside = line("Inside", struck: now.addingTimeInterval(-PageSnapshot.keep + 0.5))
        let justOutside = line("Outside", struck: now.addingTimeInterval(-PageSnapshot.keep))
        let ahead = line("Clock moved", struck: now.addingTimeInterval(120))
        let snapshot = PageSnapshot(lists: [list("work", [justInside, justOutside, ahead])])
        let leaving = snapshot.leaving(known: [:], at: now)
        #expect(leaving[justInside.id] == now.addingTimeInterval(PageSnapshot.linger))
        #expect(leaving[justOutside.id] == .distantPast)
        #expect(leaving[ahead.id] == now.addingTimeInterval(PageSnapshot.linger), "a strike dated ahead still leaves")
    }

    @Test func linesStruckBeforeAMomentAreDroppedFromEveryList() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lists = [
            list("life", [line("Old", struck: now.addingTimeInterval(-10)), line("Live")]),
            list("work", [line("New", struck: now), line("Older", struck: now.addingTimeInterval(-3))]),
        ]
        let kept = PageSnapshot(lists: lists, current: lists[1].id).leaving(struckBefore: now.addingTimeInterval(-2.5))
        #expect(kept.lists.map { $0.lines.map(\.text) } == [["Live"], ["New"]])
        #expect(kept.current == lists[1].id)
        #expect(kept.lists.map(\.left) == lists.map(\.left), "the count of what is left does not change")
    }

    // MARK: The page as the widgets are given it

    @Test func anEmptyStoreGivesAnEmptySnapshot() throws {
        #expect(try context.pageSnapshot(current: nil) == PageSnapshot())
        try context.addList(named: "life")
        let snapshot = try context.pageSnapshot(current: nil)
        #expect(snapshot.lists.map(\.lines.count) == [0])
        #expect(snapshot.lists[0].left == 0)
        #expect(snapshot.lists[0].next == nil)
    }

    @Test func listsAreInTheOrderOfTheirNamesAndEachHasItsOwnLines() throws {
        let home = try #require(try context.addList(named: "home"))
        let life = try #require(try context.addList(named: "life"))
        home.order = 5
        life.order = 1
        context.addTask("At home", to: home)
        context.addTask("In life", to: life)
        let snapshot = try context.pageSnapshot(current: home.id)
        #expect(snapshot.lists.map(\.name) == ["life", "home"])
        #expect(snapshot.lists.map { $0.lines.map(\.text) } == [["In life"], ["At home"]])
        #expect(snapshot.current == home.id)
    }

    @Test func aStruckTaskStaysInTheSnapshotForAWhileAndThenIsDropped() throws {
        let list = try #require(try context.addList(named: "work"))
        let task = try #require(context.addTask("One", to: list))
        let struck = Date(timeIntervalSince1970: 1_800_000_000)
        context.strike(task, at: struck)
        let lines = { (after: TimeInterval) in
            try context.pageSnapshot(current: nil, at: struck.addingTimeInterval(after)).lists[0].lines
        }
        #expect(try lines(0).map(\.struck) == [struck])
        #expect(try lines(PageSnapshot.keep - 0.1).count == 1)
        #expect(try lines(PageSnapshot.keep).isEmpty)
        #expect(try lines(86400).isEmpty)
        #expect(try context.pageSnapshot(current: nil, at: struck).lists[0].left == 0)
    }

    @Test func circledTasksLeadTheLinesAndStillLeaveRoomForTheRest() throws {
        let list = try #require(try context.addList(named: "work"))
        let tasks = (0..<40).compactMap { context.addTask("Task \($0)", to: list) }
        context.toggleCircle(tasks[39], at: Date(timeIntervalSince1970: 2))
        context.toggleCircle(tasks[20], at: Date(timeIntervalSince1970: 1))
        let lines = try context.pageSnapshot(current: nil).lists[0].lines
        #expect(lines.count == PageSnapshot.linesPerList)
        #expect(lines.prefix(3).map(\.text) == ["Task 20", "Task 39", "Task 0"])
        #expect(try context.pageSnapshot(current: nil).lists[0].left == 40)
    }

    @Test func aSnapshotGoesToItsFileAndBackUnchanged() throws {
        let list = try #require(try context.addList(named: "wörk 🧺"))
        context.addTask("Écrire à Zoë", to: list)
        let struck = try #require(context.addTask("Done", to: list))
        context.strike(struck)
        let snapshot = try context.pageSnapshot(current: list.id)
        page.snapshot = snapshot
        #expect(page.snapshot == snapshot)
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(PageSnapshot.self, from: data) == snapshot)
    }

    // MARK: The app keeping the drawer in step

    @Test func theAppTakesInATapAndWritesThePageBack() throws {
        LiveView.isAllowed = false
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        context.addTask("Two", to: list)
        try context.save()

        let mirror = PageMirror()
        mirror.start(context: context, page: page)
        #expect(page.snapshot.lists[0].lines.map(\.text) == ["One", "Two"])
        mirror.current = list.id
        #expect(page.snapshot.current == list.id)

        // Struck in a widget while the app was away.
        #expect(page.toggle(task: one.id))
        #expect(one.isLive)
        mirror.refresh()
        #expect(!one.isLive)
        #expect(page.pending.isEmpty)
        #expect(page.snapshot.lists[0].left == 1)
        #expect(page.snapshot.lists[0].lines.map(\.isLive) == [false, true])

        // Undone in the widget before the line left.
        #expect(page.toggle(task: one.id))
        mirror.refresh()
        #expect(one.isLive)
        #expect(page.snapshot.lists[0].left == 2)
    }

    @Test func theAppWritesNothingWhenNothingChanged() throws {
        LiveView.isAllowed = false
        let list = try #require(try context.addList(named: "work"))
        context.addTask("One", to: list)
        let mirror = PageMirror()
        mirror.start(context: context, page: page)
        let file = folder.appending(path: "pageSnapshot.json")
        let written = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        mirror.refresh()
        mirror.refresh()
        let after = try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
        #expect(after == written)
    }
}
