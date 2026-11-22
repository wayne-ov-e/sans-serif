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

@Suite("Pulling a sheet past its edge")
struct PullTrackerTests {
    /// A page that fits: 750 pt of paper in an 812 pt scroll view with a 62 pt top inset.
    private func past(_ edge: PullEdge, offset: CGFloat, topInset: CGFloat = 62) -> CGFloat {
        PullTracker.past(edge, offset: offset, topInset: topInset, bottomInset: 0,
                         contentHeight: 750, containerHeight: 812)
    }

    @Test func aPageThatFitsRestsAtBothEdges() {
        #expect(past(.top, offset: -62) == 0)
        #expect(past(.bottom, offset: -62) == 0)
    }

    @Test func aDragPastTheEndCountsOnceWhileTheFingerIsDown() {
        var pull = PullTracker(edge: .bottom)
        pull.began(past: 0, offset: -62)
        #expect(pull.changed(past: 20, offset: -42) == false)
        #expect(pull.changed(past: 45, offset: -17) == true)
        #expect(pull.changed(past: 60, offset: -2) == false)
        #expect(pull.released() == false)
    }

    @Test func aQuickPullThatBeganAtTheEdgeCountsOnRelease() {
        var pull = PullTracker(edge: .bottom)
        pull.began(past: 0, offset: -62)
        #expect(pull.changed(past: 18, offset: -44) == false)
        #expect(pull.released() == true)
    }

    @Test func aScrollThatRanOnToTheEndDoesNotCountOnRelease() {
        var pull = PullTracker(edge: .bottom)
        // The finger came down in the middle of a long page.
        pull.began(past: -300, offset: 100)
        #expect(pull.changed(past: 18, offset: 418) == false)
        #expect(pull.released() == false)
    }

    @Test func aBounceAfterTheFingerLiftedDoesNotCount() {
        var pull = PullTracker(edge: .bottom)
        pull.began(past: -300, offset: 100)
        #expect(pull.released() == false)
        #expect(pull.changed(past: 80, offset: 480) == false)
    }

    /// The fault found on Nov 17, 2026: a drag up opened settings, because the
    /// insets shifted and the sheet looked as if it were past its top.
    @Test func lookingPastAnEdgeWithoutBeingDraggedThereDoesNotCount() {
        var pull = PullTracker(edge: .top)
        pull.began(past: 0, offset: -62)
        // Dragged up 30 pt, while the inset is read as 0: 62 pt "past the top".
        #expect(pull.changed(past: 62, offset: -32) == false)
        #expect(pull.released() == false)
    }

    /// The fault Wayne found on Nov 18, 2026: the drag that put settings away
    /// went on to open the archive. A pull that was not on offer when the finger
    /// came down cannot count during that drag, however far it goes.
    @Test func aPullNotOnOfferWhenTheDragBeganNeverCounts() {
        var archive = PullTracker(edge: .bottom)
        // Settings are down, so the archive is not on offer.
        archive.began(past: 0, offset: -62, isEnabled: false)
        #expect(archive.changed(past: 60, offset: -2) == false)
        #expect(archive.changed(past: 120, offset: 58) == false)
        #expect(archive.released() == false)

        // The next drag, with settings away, is a new one.
        archive.began(past: 0, offset: -62, isEnabled: true)
        #expect(archive.changed(past: 45, offset: -17) == true)
    }

    @Test func thePaperIsHeldWhenTheScrollingLetsGoOfItUnderTheFinger() {
        var tracker = PullTracker(edge: .top)
        tracker.began(past: 0, offset: -62)
        let before = tracker.held()
        #expect(before == nil)
        let counted = tracker.changed(past: 47, offset: -109)
        #expect(counted)
        #expect(tracker.pull.shift == 47)
        // Following the finger, there is nothing to hold.
        _ = tracker.changed(past: 61, offset: -123)
        let following = tracker.held()
        #expect(following == nil)
        // Settings arrive, and for a frame or two the sheet reads as back at its edge.
        _ = tracker.changed(past: 0, offset: -62)
        let first = tracker.held()
        #expect(first == 61)
        _ = tracker.changed(past: 0, offset: -62)
        let second = tracker.held()
        #expect(second == 61)
        // The finger moves, the scrolling has the sheet again, and the hold ends.
        _ = tracker.changed(past: 46, offset: -108)
        let resumed = tracker.held()
        #expect(resumed == 0)
        // Lifted, the sheet springs back by itself. Nothing is held.
        _ = tracker.released()
        _ = tracker.changed(past: 20, offset: -82)
        let springing = tracker.held()
        #expect(springing == nil)
        _ = tracker.changed(past: 0, offset: -62)
        let rested = tracker.held()
        #expect(rested == nil)
        let nothingToLetGo = tracker.letGo()
        #expect(!nothingToLetGo)
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

    @Test func aQuickPullBegunWhileAShortSheetSpringsBackCounts() {
        // Settings were just put away: the page, all of it in view, is still
        // 30 points up from its top, on its way back. A quick pull moves it 25
        // points and lets go short of its top: it counts.
        var quick = PullTracker(edge: .top)
        quick.began(past: -30, offset: -32, fits: true)
        let early = quick.changed(past: -5, offset: -57)
        #expect(!early)
        let flicked = quick.released()
        #expect(flicked)

        // Dragged 40 points, it counts while the finger is still down,
        // though it never gets past its top.
        var dragged = PullTracker(edge: .top)
        dragged.began(past: -80, offset: 18, fits: true)
        let far = dragged.changed(past: -30, offset: -32)
        #expect(far)

        // The other way it is no pull down at all.
        var wrongWay = PullTracker(edge: .top)
        wrongWay.began(past: -30, offset: -32, fits: true)
        _ = wrongWay.changed(past: -80, offset: 18)
        let up = wrongWay.released()
        #expect(!up)

        // A long page scrolled that far is being scrolled, not pulled.
        var scrolled = PullTracker(edge: .top)
        scrolled.began(past: -30, offset: -32)
        _ = scrolled.changed(past: -5, offset: -57)
        let scroll = scrolled.released()
        #expect(!scroll)
    }

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

    @Test func aPullLetGoPastTheEdgeIsFollowedBackToIt() {
        var tracker = PullTracker(edge: .top)
        tracker.began(past: 0, offset: -62)
        // Nothing has counted yet: the scrolling brings it back by itself.
        _ = tracker.changed(past: 10, offset: -72)
        let early = tracker.rebounds()
        #expect(!early)
        let counted = tracker.changed(past: 61, offset: -123)
        #expect(counted)
        _ = tracker.held()
        _ = tracker.released()
        let rebounds = tracker.rebounds()
        #expect(rebounds)
        let first = tracker.rebounded()
        #expect(first == 61)
        _ = tracker.changed(past: 30, offset: -92)
        let halfway = tracker.rebounded()
        #expect(halfway == 30)
        // What is taken off the paper is the distance before it was rounded.
        _ = tracker.changed(past: 12, offset: -74)
        let exact = tracker.rebounded(exactly: 12.4)
        #expect(exact == 12.4)
        // Back at its edge: told once, and then no more.
        _ = tracker.changed(past: 0, offset: -62)
        let back = tracker.rebounded(exactly: 0.3)
        #expect(back == 0)
        let after = tracker.rebounded()
        #expect(after == nil)

        // Away from the top a sheet is only scrolled, and does not come back.
        var away = PullTracker(edge: .awayFromTop)
        away.began(past: 0, offset: -62)
        _ = away.changed(past: 30, offset: -32)
        _ = away.released()
        let scrolled = away.rebounds()
        #expect(!scrolled)

        // Up past the end is a shift up, and a finger coming down again ends it.
        var up = PullTracker(edge: .bottom)
        up.began(past: 0, offset: 0)
        _ = up.changed(past: 45, offset: 45)
        _ = up.released()
        let upRebounds = up.rebounds()
        #expect(upRebounds)
        let shift = up.rebounded()
        #expect(shift == -45)
        up.began(past: 20, offset: 20)
        #expect(!up.isRebounding)
    }

    @Test func aFingerLiftedWhileThePaperIsHeldLetsItDown() {
        var tracker = PullTracker(edge: .bottom)
        tracker.began(past: 0, offset: 0)
        let counted = tracker.changed(past: 45, offset: 45)
        #expect(counted)
        #expect(tracker.pull.shift == -45)
        _ = tracker.held()
        _ = tracker.changed(past: 0, offset: 0)
        let held = tracker.held()
        // Up past the end, the paper is held above its edge.
        #expect(held == -45)
        _ = tracker.released()
        let letDown = tracker.letGo()
        #expect(letDown)
        let again = tracker.letGo()
        #expect(!again)
    }

    @Test func oneDragCountsOnlyOnce() {
        var pull = PullTracker(edge: .awayFromTop)
        pull.began(past: 0, offset: -62)
        #expect(pull.changed(past: 22, offset: -40) == true)
        #expect(pull.changed(past: 80, offset: 18) == false)
        #expect(pull.released() == false)
    }

    @Test func withSettingsDownAnyDragUpCounts() {
        var pull = PullTracker(edge: .awayFromTop)
        pull.began(past: 0, offset: -62)
        #expect(pull.changed(past: 12, offset: -50) == false)
        #expect(pull.changed(past: 22, offset: -40) == true)
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
