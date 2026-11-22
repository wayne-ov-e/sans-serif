import Foundation
import SwiftData
import Testing

@testable import SansSerif

@MainActor
struct ListLogicTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
    }

    @Test func seedsLifeWorkHomeOnce() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        try PageStore.seedDefaultListsIfNeeded(in: context)
        #expect(try context.lists().map(\.name) == ["life", "work", "home"])
    }

    @Test func addsTasksInPageOrderAndSkipsBlankText() throws {
        let list = try #require(try context.addList(named: "life"))
        context.addTask("Call the framer", to: list)
        context.addTask("   ", to: list)
        context.addTask("  Renew passport \n", to: list)
        #expect(list.liveTasks.map(\.text) == ["Call the framer", "Renew passport"])
        #expect(list.liveCount == 2)
    }

    @Test func todayHasItsOwnPlaceInTheArchiveAndTheMonthsDoNotRepeatIt() throws {
        let list = try #require(try context.addList(named: "life"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 15))!
        let earlier = try #require(context.addTask("This morning", to: list))
        let later = try #require(context.addTask("Just now", to: list))
        let yesterday = try #require(context.addTask("Yesterday", to: list))
        let lastMonth = try #require(context.addTask("Last month", to: list))
        context.addTask("Still to do", to: list)
        context.strike(earlier, at: now.addingTimeInterval(-6 * 3600))
        context.strike(later, at: now.addingTimeInterval(-60))
        context.strike(yesterday, at: now.addingTimeInterval(-24 * 3600))
        context.strike(lastMonth, at: now.addingTimeInterval(-30 * 24 * 3600))

        #expect(list.doneToday(at: now, calendar: calendar).map(\.text) == ["Just now", "This morning"])
        let months = list.archive(calendar: calendar, before: now)
        #expect(months.map { $0.tasks.map(\.text) } == [["Yesterday"], ["Last month"]])
        // Asked for whole, the archive still holds everything.
        #expect(list.archive(calendar: calendar).flatMap(\.tasks).count == 4)
        // An empty archive has neither.
        let empty = try #require(try context.addList(named: "work"))
        #expect(empty.doneToday(at: now, calendar: calendar).isEmpty)
        #expect(empty.archive(calendar: calendar, before: now).isEmpty)
    }

    @Test func strikingMovesATaskToTheArchiveAndRestoringBringsItBack() throws {
        let list = try #require(try context.addList(named: "life"))
        let first = try #require(context.addTask("One", to: list))
        context.addTask("Two", to: list)
        context.addTask("Three", to: list)

        context.strike(first, strokeData: Data([1]))
        #expect(list.liveTasks.map(\.text) == ["Two", "Three"])
        #expect(list.liveCount == 2)
        #expect(list.archive().flatMap(\.tasks).map(\.text) == ["One"])

        context.restore(first)
        #expect(first.struckDate == nil)
        #expect(first.strokeData == nil)
        #expect(list.liveTasks.map(\.text) == ["One", "Two", "Three"])
        #expect(list.archive().isEmpty)
    }

    @Test func archiveGroupsByMonthNewestFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        }

        let list = try #require(try context.addList(named: "life"))
        let struck = [("a", date(2026, 9, 30)), ("b", date(2026, 11, 2)), ("c", date(2026, 11, 14)), ("d", date(2026, 10, 1))]
        for (text, when) in struck {
            let task = try #require(context.addTask(text, to: list))
            context.strike(task, at: when)
        }

        let archive = list.archive(calendar: calendar)
        #expect(archive.map(\.month) == [date(2026, 11, 1), date(2026, 10, 1), date(2026, 9, 1)].map {
            calendar.startOfDay(for: $0)
        })
        #expect(archive.map { $0.tasks.map(\.text) } == [["c", "b"], ["d"], ["a"]])
    }

    @Test func movingATaskPutsItLastInTheOtherList() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        let task = try #require(context.addTask("Move me", to: life))
        context.addTask("Already here", to: work)

        context.move(task, to: work)
        #expect(life.liveCount == 0)
        #expect(work.liveTasks.map(\.text) == ["Already here", "Move me"])
    }

    @Test func placingATaskReordersThePage() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = try ["a", "b", "c", "d"].map { try #require(context.addTask($0, to: list)) }

        context.place(tasks[3], below: tasks[0], above: tasks[1])
        #expect(list.liveTasks.map(\.text) == ["a", "d", "b", "c"])
        context.place(tasks[2], below: nil, above: tasks[0])
        #expect(list.liveTasks.map(\.text) == ["c", "a", "d", "b"])
        context.place(tasks[2], below: tasks[1], above: nil)
        #expect(list.liveTasks.map(\.text) == ["a", "d", "b", "c"])
    }

    @Test func placingStillWorksWhenThereIsNoRoomBetweenTwoTasks() throws {
        let list = try #require(try context.addList(named: "life"))
        let tasks = try ["a", "b", "c"].map { try #require(context.addTask($0, to: list)) }
        tasks[1].order = tasks[0].order

        context.place(tasks[2], below: tasks[0], above: tasks[1])
        #expect(list.liveTasks.map(\.text) == ["a", "c", "b"])
        #expect(Set(list.liveTasks.map(\.order)).count == 3)
    }

    @Test func deletingATaskLeavesNoTrace() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Gone", to: list))
        context.strike(task)
        context.delete(task)
        try context.save()
        #expect(list.liveCount == 0)
        #expect(list.archive().isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<TaskItem>()) == 0)
    }

    @Test func deletingAListRemovesItsTasksAndArchive() throws {
        let list = try #require(try context.addList(named: "life"))
        let other = try #require(try context.addList(named: "work"))
        let struck = try #require(context.addTask("Struck", to: list))
        context.strike(struck)
        context.addTask("Live", to: list)
        context.addTask("Kept", to: other)
        try context.save()

        context.delete(list)
        try context.save()
        #expect(try context.lists().map(\.name) == ["work"])
        #expect(try context.fetch(FetchDescriptor<TaskItem>()).map(\.text) == ["Kept"])
    }

    @Test func neighboursFollowTheRowOfNamesAndDoNotWrap() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let lists = try context.lists()
        #expect(lists.neighbour(of: lists[0], by: 1)?.name == "work")
        #expect(lists.neighbour(of: lists[2], by: -1)?.name == "work")
        #expect(lists.neighbour(of: lists[0], by: -1) == nil)
        #expect(lists.neighbour(of: lists[2], by: 1) == nil)
    }

    @Test func renamingIgnoresBlankNames() throws {
        let list = try #require(try context.addList(named: "life"))
        context.rename(list, to: "  ")
        #expect(list.name == "life")
        context.rename(list, to: " errands ")
        #expect(list.name == "errands")
    }
}

struct StrokeTests {
    @Test func pencilPressureSetsTheWeightOfTheLine() {
        #expect(Stroke.weight(forPressure: 0) == Stroke.pencilWeightRange.lowerBound)
        #expect(Stroke.weight(forPressure: 1) == Stroke.pencilWeightRange.upperBound)
        // Ordinary writing gives a line a little over the nominal width.
        #expect((1.0...1.3).contains(Stroke.weight(forPressure: 0.25)))
        #expect(Stroke.weight(forPressure: 0.2) < Stroke.weight(forPressure: 0.4))
    }
}

@MainActor
@Suite("Guide and haptics")
struct GuideAndHapticsTests {
    @Test func finishingTheGuideKeepsTheOwnTaskLiveAndArchivesTheLines() throws {
        let container = try PageStore.makeContainer(inMemory: true)
        defer { _ = container }
        let context = container.mainContext
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let first = try #require(try context.lists().first)

        context.finishGuide(ownTask: "Buy milk", struckLines: ["Cross me off.", "Hold a line for more."], in: first)

        #expect(first.liveTasks.map(\.text) == ["Buy milk"])
        let archive = first.archive()
        #expect(archive.count == 1)
        #expect(Set(archive[0].tasks.map(\.text)) == ["Cross me off.", "Hold a line for more."])
        // A struck line with no stored pen line still has one stroke per line of text.
        #expect(archive[0].tasks[0].strokes(forLines: 2).count == 2)
    }

    @Test func skippingTheGuideLeavesNothingBehind() throws {
        let container = try PageStore.makeContainer(inMemory: true)
        defer { _ = container }
        let context = container.mainContext
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let first = try #require(try context.lists().first)

        context.finishGuide(ownTask: nil, struckLines: [], in: first)

        #expect((first.tasks ?? []).isEmpty)
    }

    @Test func aDragIsFeltOnLandingAndAlongTheLine() {
        var ticks = DragTicks()
        ticks.land()
        #expect(ticks.count == 1)
        ticks.move(to: 0.05)
        #expect(ticks.count == 1)
        ticks.move(to: 0.5)
        ticks.move(to: 0.5)
        #expect(ticks.count == 2)
        ticks.move(to: 1)
        #expect(ticks.count == 3)
    }

    /// Where the pen cannot be played, every call says so and nothing else happens.
    @Test func thePenIsSafeToCallAnywhere() {
        let pen = PenHaptics.shared
        let landed = pen.land()
        #expect(pen.move(speed: 400, along: 0.5) == landed)
        _ = pen.click(armed: true)
        _ = pen.lift(speed: 900, extraLines: 2)
        _ = pen.retract()
        pen.stop()
        #expect(pen.move(speed: 400, along: 0.5) == false)
    }
}

@Suite("The paper between settings, the page and the archive")
struct DeckTests {
    private let deck = Deck(settingsHeight: 300, height: 900)

    @Test func aPointOfTheFingerIsAPointOfThePaperOnEitherSideOfThePage() {
        #expect(deck.points(-1) == -300)
        #expect(deck.points(1) == 900)
        #expect(deck.place(points: -150) == -0.5)
        #expect(deck.place(points: 450) == 0.5)
        // Down 150 from the page is half way to settings; up 450 is half way to the archive.
        #expect(deck.dragged(from: 0, by: 150, low: -1, high: 1) == -0.5)
        #expect(deck.dragged(from: 0, by: -450, low: -1, high: 1) == 0.5)
    }

    @Test func thePaperDoesNotMoveTowardASideThatIsNotOpen() {
        // A long page scrolled away from its top: down is for the list, not for settings.
        #expect(deck.dragged(from: 0, by: 200, low: 0, high: 1) == 0)
        #expect(deck.dragged(from: 0, by: -200, low: -1, high: 0) == 0)
    }

    @Test func pastSettingsAndPastTheArchiveItGivesLessAndLess() {
        let little = deck.points(deck.dragged(from: 1, by: -40, low: 0, high: 1)) - 900
        let more = deck.points(deck.dragged(from: 1, by: -400, low: 0, high: 1)) - 900
        let far = deck.points(deck.dragged(from: 1, by: -4000, low: 0, high: 1)) - 900
        // It goes with the finger, by less than the finger asks, and never beyond its reach.
        #expect(little > 0 && little < 40)
        #expect(more > little && more < 400 * Deck.give)
        #expect(far > more && far < Deck.reach)
        #expect(deck.dragged(from: -1, by: 100, low: -1, high: 0) < -1)
    }

    @Test func aHarderFlickGetsAQuickerSpringAndNeverOneThatPassesItsPlace() {
        let usual = 2 * Double.pi / Deck.response
        // At rest, or let go slowly: the usual spring.
        #expect(Deck.pace(from: 0, to: 900, speed: 0) == usual)
        #expect(Deck.pace(from: 0, to: 900, speed: 500) == usual)
        // Close to its place and still fast: quicker, enough that it does not pass.
        let quick = Deck.pace(from: 800, to: 900, speed: 2000)
        #expect(quick > usual)
        #expect(quick >= 2000.0 / 100)
        // And no quicker than the quickest.
        #expect(Deck.pace(from: 890, to: 900, speed: 9000) == 2 * Double.pi / Deck.quickest)
    }

    @Test func theArchiveIsAShortWayOffAndThePageIsGoneBeforeItIsWhole() {
        // Under half the screen, and never the whole of it.
        #expect(Deck.travel(screen: 874) < 874 / 2)
        #expect(Deck.travel(screen: 874) >= 260)
        #expect(Deck.travel(screen: 2000) == 420)
        #expect(Deck.pageInk(up: 0) == 1)
        #expect(Deck.archiveInk(up: 0) == 0)
        #expect(Deck.pageInk(up: 1) == 0)
        #expect(Deck.archiveInk(up: 1) == 1)
        // Half way, neither is strong.
        #expect(Deck.pageInk(up: 0.5) < 0.3)
        #expect(Deck.archiveInk(up: 0.5) < 0.3)
    }

    @Test func aFlickGoesOnePlaceOn() {
        #expect(deck.target(now: -0.1, grabbed: 0, heading: 0, inFlight: false, speed: -800) == Deck.settings)
        #expect(deck.target(now: 0.1, grabbed: 0, heading: 0, inFlight: false, speed: 800) == Deck.archive)
        #expect(deck.target(now: -0.8, grabbed: -1, heading: -1, inFlight: false, speed: 800) == Deck.page)
        #expect(deck.target(now: 0.9, grabbed: 1, heading: 1, inFlight: false, speed: -800) == Deck.page)
        // However hard, from settings it stops at the page.
        #expect(deck.target(now: -0.5, grabbed: -1, heading: -1, inFlight: false, speed: 9000) == Deck.page)
    }

    @Test func aSlowDragGoesOnOnlyIfItMovedThePaperFarEnough() {
        let short = Deck.carry - 20, long = Deck.carry + 10
        #expect(deck.target(now: deck.place(points: short), grabbed: 0, heading: 0, inFlight: false, speed: 0) == Deck.page)
        #expect(deck.target(now: deck.place(points: -short), grabbed: 0, heading: 0, inFlight: false, speed: 0) == Deck.page)
        #expect(deck.target(now: deck.place(points: long), grabbed: 0, heading: 0, inFlight: false, speed: 0) == Deck.archive)
        #expect(deck.target(now: deck.place(points: -long), grabbed: 0, heading: 0, inFlight: false, speed: 0) == Deck.settings)
        // A slow lift is not a flick, however small the movement.
        #expect(deck.target(now: 0.02, grabbed: 0, heading: 0, inFlight: false, speed: Deck.flick - 20) == Deck.page)
    }

    @Test func twoFlicksGoTwoPlaces() {
        // Up from settings, caught half way to the page, and flicked up again: the archive.
        #expect(deck.target(now: -0.4, grabbed: -0.5, heading: 0, inFlight: true, speed: 800) == Deck.archive)
        // Down from the archive, caught on its way to the page, and flicked down again: settings.
        #expect(deck.target(now: 0.4, grabbed: 0.5, heading: 0, inFlight: true, speed: -800) == Deck.settings)
        // Caught on its way and sent back: only as far as where it came from.
        #expect(deck.target(now: -0.6, grabbed: -0.5, heading: 0, inFlight: true, speed: -800) == Deck.settings)
    }

    @Test func itNeverGoesWhereTheFingerMayNotTakeIt() {
        // A long page not at its end: a flick up scrolls the list, and the paper stays on the page.
        #expect(deck.target(now: 0, grabbed: 0, heading: 0, inFlight: false, speed: 800, low: -1, high: 0) == Deck.page)
        #expect(deck.target(now: 0, grabbed: 0, heading: 0, inFlight: false, speed: -800, low: 0, high: 1) == Deck.page)
    }

    #if os(iOS)
    @Test func onlyAPhoneAsWideAsAnOpenDuoIsTurned() {
        // The widest ordinary iPhone, either way up.
        #expect(!AppDelegate.turns(phoneScreen: CGSize(width: 440, height: 956)))
        #expect(!AppDelegate.turns(phoneScreen: CGSize(width: 956, height: 440)))
        #expect(!AppDelegate.turns(phoneScreen: CGSize(width: 402, height: 874)))
        // An inner screen, wider than any of them.
        #expect(AppDelegate.turns(phoneScreen: CGSize(width: 700, height: 900)))
    }
    #endif

    @Test func theListForTheLiveViewIsReadFromSettingsOrIsNone() throws {
        let defaults = try #require(UserDefaults(suiteName: "live-\(UUID().uuidString)"))
        #expect(LiveView.chosenList(defaults: defaults) == nil)
        let id = UUID()
        defaults.set(id.uuidString, forKey: LiveView.listKey)
        #expect(LiveView.chosenList(defaults: defaults) == id)
        // Turned off, it is written empty; nonsense is none too.
        for nothing in ["", "not a list"] {
            defaults.set(nothing, forKey: LiveView.listKey)
            #expect(LiveView.chosenList(defaults: defaults) == nil)
        }
    }
}

@Suite("Settings")
struct SettingDefaultsTests {
    @Test func aFirstLaunchShowsTheGuideAndFollowsTheSystemForDarkPaper() {
        #expect(Setting.guideDone.defaultValue == false)
        #expect(Setting.guideReplay.defaultValue == false)
        #expect(Setting.darkPaper.defaultValue == true)
        #expect(Setting.haptics.defaultValue == true)
    }

    @Test func everySettingHasItsOwnKey() {
        let keys = [Setting.showCounts, Setting.iCloudSync, Setting.haptics, Setting.darkPaper, Setting.guideDone, Setting.guideReplay].map(\.key)
        #expect(Set(keys).count == keys.count)
    }
}

@MainActor
@Suite("Lists meeting through iCloud")
struct MergeListsTests {
    /// Held for the length of a test: a context does not keep its container alive.
    let container: ModelContainer

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
        try PageStore.seedDefaultListsIfNeeded(in: container.mainContext)
    }

    private func store() throws -> ModelContext { container.mainContext }

    @Test func aFirstListIsFoldedIntoTheOneICloudAlreadyHad() throws {
        let context = try store()
        let life = try #require(try context.lists().first { $0.name == "life" })
        context.addTask("From this phone", to: life)

        // What iCloud already had: the list of another device, and what was written there.
        let known = try #require(try context.addList(named: "life"))
        known.recordData = Data([1])
        known.createdDate = life.createdDate.addingTimeInterval(-3600)
        context.addTask("From the other phone", to: known)
        let done = try #require(context.addTask("Done there", to: known))
        context.strike(done)

        #expect(try context.mergeDuplicateDefaultLists() == 1)

        let lists = try context.lists()
        #expect(Set(lists.map(\.name)) == ["life", "work", "home"])
        #expect(lists.count == 3)
        // iCloud's list is the one kept: it is the one the other devices have.
        #expect(lists.contains { $0 === known })
        #expect(known.liveTasks.map(\.text) == ["From the other phone", "From this phone"])
        #expect(known.archive().flatMap(\.tasks).map(\.text) == ["Done there"])
    }

    @Test func iCloudsListIsKeptEvenWhenThisDevicesIsOlder() throws {
        let context = try store()
        let seed = try #require(try context.lists().first { $0.name == "work" })
        let known = try #require(try context.addList(named: "work"))
        known.recordData = Data([1])
        known.createdDate = seed.createdDate.addingTimeInterval(3600)

        try context.mergeDuplicateDefaultLists()

        #expect(try context.lists().filter { $0.name == "work" }.map(\.id) == [known.id])
    }

    @Test func aSecondListTheUserNamesLikeAFirstOneIsTheirsToKeep() throws {
        let context = try store()
        // Made by the user on this device: not a seed, and not from iCloud.
        try context.addList(named: "home")
        #expect(try context.mergeDuplicateDefaultLists() == 0)
        #expect(try context.lists().filter { $0.name == "home" }.count == 2)

        // Nor once both have been sent to iCloud and are no longer seeds.
        for list in try context.lists() {
            list.isSeeded = false
            list.recordData = Data([1])
        }
        #expect(try context.mergeDuplicateDefaultLists() == 0)
        #expect(try context.lists().filter { $0.name == "home" }.count == 2)
    }

    @Test func listsTheUserNamedAreLeftAlone() throws {
        let context = try store()
        try context.addList(named: "errands")
        try context.addList(named: "errands")

        #expect(try context.mergeDuplicateDefaultLists() == 0)
        #expect(try context.lists().count == 5)
    }

    @Test func nothingToMergeChangesNothing() throws {
        let context = try store()
        #expect(try context.mergeDuplicateDefaultLists() == 0)
        #expect(try context.lists().map(\.name) == ["life", "work", "home"])
    }
}
