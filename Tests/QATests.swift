import CloudKit
import Foundation
import SwiftData
import Testing

@testable import SansSerif

/// What a review of the whole app turned up on Nov 19, 2026: each test holds
/// one of the faults it found.
@MainActor
@Suite("Faults found in review")
struct ReviewFaultTests {
    let container: ModelContainer
    let page: SharedPage
    var context: ModelContext { container.mainContext }

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
        let name = "review-\(UUID().uuidString)"
        page = SharedPage(defaults: try #require(UserDefaults(suiteName: name)))
    }

    // MARK: Lists

    @Test func aListSomeoneElseSharedIsNotFoldedIntoTheUsersOwnOfTheSameName() throws {
        let mine = try #require(try context.addList(named: "work"))
        context.addTask("Mine", to: mine)
        let theirs = try #require(try context.addList(named: "work"))
        theirs.zoneOwner = "_ada"
        theirs.isShared = true
        theirs.createdDate = mine.createdDate.addingTimeInterval(-1000)
        context.addTask("Theirs", to: theirs)
        try context.save()

        #expect(try context.mergeDuplicateDefaultLists() == 0)
        #expect(try context.lists().count == 2)
        #expect((mine.tasks ?? []).map(\.text) == ["Mine"])
        #expect((theirs.tasks ?? []).map(\.text) == ["Theirs"])
    }

    @Test func aListTheUserSharesIsNotFoldedAwayEither() throws {
        let shared = try #require(try context.addList(named: "home"))
        shared.isShared = true
        let other = try #require(try context.addList(named: "home"))
        other.createdDate = shared.createdDate.addingTimeInterval(-1000)
        try context.save()
        #expect(try context.mergeDuplicateDefaultLists() == 0)
        #expect(try context.lists().count == 2)
    }

    @Test func aTaskStruckByAClockThatRunsAheadStillStandsUnderAHeading() throws {
        let calendar = Calendar.current
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 23, minute: 58)))
        let list = try #require(try context.addList(named: "life"))
        let ahead = try #require(context.addTask("Ahead", to: list))
        context.strike(ahead, at: now.addingTimeInterval(4 * 60))
        let yesterday = try #require(context.addTask("Yesterday", to: list))
        context.strike(yesterday, at: now.addingTimeInterval(-86_400))

        #expect(list.doneToday(at: now).map(\.text) == ["Ahead"])
        #expect(list.archive(before: now).flatMap(\.tasks).map(\.text) == ["Yesterday"])
        #expect(list.doneGroup(with: ahead, now: now).map(\.text) == ["Ahead"])
    }

    // MARK: Widgets and the Live Activity

    @Test func aTapWhereTheTaskStillShowedLiveDoesNotUndoAStrikeMadeElsewhere() throws {
        let list = try #require(try context.addList(named: "work"))
        let one = try #require(context.addTask("One", to: list))
        page.snapshot = try context.pageSnapshot(current: list.id)

        // Struck in the widget.
        #expect(page.toggle(task: one.id, expectingLive: true))
        // The Live Activity had not been drawn again: it still showed it live.
        #expect(!page.toggle(task: one.id, expectingLive: true), "the second tap changes nothing")
        #expect(page.snapshot.lists[0].lines[0].isLive == false)
        #expect(page.pending.count == 1)

        try context.apply(page.takePending())
        #expect(!one.isLive)

        // A tap that knows the task is struck still undoes it.
        page.snapshot = try context.pageSnapshot(current: list.id)
        if page.snapshot.lists[0].lines.contains(where: { $0.id == one.id }) {
            #expect(page.toggle(task: one.id, expectingLive: false))
        }
    }

    @Test func aStrikeMadeOutsideTheAppCarriesTheUsersNameOnASharedList() throws {
        let own = try #require(try context.addList(named: "mine"))
        let shared = try #require(try context.addList(named: "ours"))
        shared.isShared = true
        let private_ = try #require(context.addTask("Private", to: own))
        let ours = try #require(context.addTask("Ours", to: shared))
        try context.apply([
            PendingChange(task: private_.id, struck: true, date: .now),
            PendingChange(task: ours.id, struck: true, date: .now),
        ], by: "Wayne")
        #expect(ours.struckBy == "Wayne")
        #expect(private_.struckBy == nil, "the user's own lists go unsigned")
    }

    // MARK: iCloud

    @Test func aDeletionThatWentDownWithARefusedBatchIsAskedForAgain() {
        #expect(CloudSync.deletesAgain(after: .batchRequestFailed))
        #expect(CloudSync.deletesAgain(after: .operationCancelled))
        #expect(CloudSync.deletesAgain(after: .serverRecordChanged))
        // Nothing left to delete.
        #expect(CloudSync.deletesAgain(after: .unknownItem) == false)
        #expect(CloudSync.deletesAgain(after: .zoneNotFound) == false)
        #expect(CloudSync.deletesAgain(after: .userDeletedZone) == false)
        // The engine tries these again by itself.
        #expect(CloudSync.deletesAgain(after: .networkFailure) == false)
    }

    @Test func aShareSeenOnAnotherDeviceMarksTheListSharedAndItsRemovalUnmarksIt() throws {
        let sync = CloudSync(storingIn: context)
        let list = try #require(try context.addList(named: "life"))
        let other = try #require(try context.addList(named: "work"))
        try context.save()
        #expect(!list.isShared)

        let share = CKShare(recordZoneID: list.zoneID)
        sync.applying { sync.take(share: share) }
        #expect(list.isShared)
        #expect(!other.isShared)

        sync.applying { sync.shareGone(in: list.zoneID) }
        #expect(!list.isShared)
        #expect(list.shareURL == nil)
    }

    @Test func aShareInSomeoneElsesZoneSaysNothingAboutTheUsersLists() throws {
        let sync = CloudSync(storingIn: context)
        let list = try #require(try context.addList(named: "life"))
        try context.save()
        let theirs = CKRecordZone.ID(zoneName: list.zoneID.zoneName, ownerName: "_ada")
        sync.applying { sync.take(share: CKShare(recordZoneID: theirs)) }
        #expect(!list.isShared)
    }

    // MARK: The first lists and iCloud

    @Test func untouchedFirstListsDoNotComeBackOnceICloudHasTheUsersLists() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let sync = CloudSync(storingIn: context)
        sync.heardFromICloud = false
        let seeds = try context.lists()
        #expect(seeds.allSatisfy { sync.isHeld($0) }, "nothing is sent before iCloud is heard from")

        // On another device life was renamed and home deleted. iCloud has these two.
        for name in ["personal", "work"] {
            let known = try #require(try context.addList(named: name))
            known.recordData = Data([1])
            context.addTask("Kept", to: known)
        }
        try context.save()

        let sent = sync.settleSeeds()
        #expect(sent.isEmpty, "nothing of the first lists is sent")
        #expect(Set(try context.lists().map(\.name)) == ["personal", "work"])
        #expect(try context.lists().count == 2)
        #expect(sync.heardFromICloud)
    }

    @Test func firstListsThatWereWrittenInAreKeptAndSent() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let sync = CloudSync(storingIn: context)
        sync.heardFromICloud = false
        let home = try #require(try context.lists().first { $0.name == "home" })
        context.addTask("Written before iCloud answered", to: home)
        let known = try #require(try context.addList(named: "personal"))
        known.recordData = Data([1])
        try context.save()

        let sent = sync.settleSeeds()
        #expect(sent.map(\.name) == ["home"])
        #expect(home.isSeeded == false)
        #expect(Set(try context.lists().map(\.name)) == ["personal", "home"])
    }

    @Test func withNothingInICloudTheFirstListsAreSent() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let sync = CloudSync(storingIn: context)
        sync.heardFromICloud = false
        let sent = sync.settleSeeds()
        #expect(Set(sent.map(\.name)) == ["life", "work", "home"])
        #expect(try context.lists().count == 3)
        #expect(try context.lists().allSatisfy { !$0.isSeeded && !sync.isHeld($0) })
    }

    @Test func theLastListIsNeverTakenAway() throws {
        try PageStore.seedDefaultListsIfNeeded(in: context)
        let sync = CloudSync(storingIn: context)
        sync.heardFromICloud = false
        // iCloud has only a list someone else shared: not one of the user's own.
        let shared = try #require(try context.lists().first)
        shared.isSeeded = false
        shared.recordData = Data([1])
        try context.save()
        sync.settleSeeds()
        #expect(try context.lists().count >= 1)
    }

    // MARK: A list deleted elsewhere

    @Test func aMissingZoneMeansDeletedElsewhereOnlyWhenICloudHadTheList() {
        #expect(CloudSync.wasDeletedElsewhere(code: .zoneNotFound, iCloudHadList: true))
        #expect(CloudSync.wasDeletedElsewhere(code: .userDeletedZone, iCloudHadList: false))
        // Never sent yet: the zone is made, the list is not thrown away.
        #expect(CloudSync.wasDeletedElsewhere(code: .zoneNotFound, iCloudHadList: false) == false)
    }

    // MARK: A change of iCloud account

    @Test func anotherAccountLeavesNothingOfTheOldOne() throws {
        let sync = CloudSync(storingIn: context)
        let own = try #require(try context.addList(named: "life"))
        own.isShared = true
        own.shareURL = "https://www.icloud.com/share/old"
        own.recordData = Data([1])
        let task = try #require(context.addTask("Mine", to: own))
        task.recordData = Data([1])
        let theirs = try #require(try context.addList(named: "trip"))
        theirs.zoneOwner = "_ada"
        theirs.isShared = true
        theirs.recordData = Data([1])
        try context.save()

        sync.applying { sync.forgetAccount() }

        let lists = try context.lists()
        #expect(lists.map(\.name) == ["life"], "a list shared with the old account leaves with it")
        #expect(own.isShared == false)
        #expect(own.shareURL == nil)
        #expect(own.recordData == nil)
        #expect(task.recordData == nil)
        #expect(task.text == "Mine", "the user's own tasks stay")
    }

    // MARK: While the iCloud sync line is struck

    @Test func whatIsWrittenDownForLaterIsReadBackAsItWas() {
        let zone = CKRecordZone.ID(zoneName: "list-\(UUID().uuidString)", ownerName: "_ada")
        #expect(CloudSync.zone(written: CloudSync.written(zone)) == zone)
        let own = CKRecordZone.ID(zoneName: "list-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
        let task = UUID()
        let record = CloudSync.record(written: CloudSync.written(task, in: own))
        #expect(record?.recordName == task.uuidString)
        #expect(record?.zoneID == own)
        #expect(CloudSync.zone(written: "nonsense") == nil)
        #expect(CloudSync.record(written: "not-a-uuid|zone|owner") == nil)
    }

    @Test func changesAndDeletionsMadeWithoutSyncAreNotedAndOnlyThose() throws {
        let defaults = try #require(UserDefaults(suiteName: "waiting-\(UUID().uuidString)"))
        let list = try #require(try context.addList(named: "life"))
        list.recordData = Data([1])
        let gone = try #require(try context.addList(named: "errands"))
        gone.recordData = Data([1])
        let fresh = try #require(try context.addList(named: "never sent"))
        var known: [TaskItem] = []
        for text in ["Edited", "Deleted", "Untouched"] {
            let task = try #require(context.addTask(text, to: list))
            task.recordData = Data([1])
            known.append(task)
        }
        try context.save()

        let sync = CloudSync(storingIn: context)
        sync.rememberPlaces()
        context.edit(known[0], to: "Edited here")
        context.delete(known[1])
        context.delete(gone)
        context.delete(fresh)
        let written = try #require(context.addTask("Written here", to: list))
        sync.storeWillSaveWithoutSync(defaults: defaults)
        try context.save()

        let waited = sync.takeWhatWaited(defaults: defaults)
        // The list counts as changed too: a task was added to it and one taken from it.
        #expect(Set(waited.changed).subtracting([list.id]) == [known[0].id, written.id])
        #expect(waited.changed.contains(known[2].id) == false, "what was not touched is not sent again")
        #expect(waited.zones == [gone.zoneID], "a list iCloud never had leaves nothing to delete")
        #expect(waited.records.map(\.recordName) == [known[1].id.uuidString])
        // Taken once.
        let again = sync.takeWhatWaited(defaults: defaults)
        #expect(again.changed.isEmpty && again.zones.isEmpty && again.records.isEmpty)
    }

    // MARK: The card that goes with a shared list's link

    @Test func aShareIsDressedWithTheListsNameAndCardAndOnlyWhenItNeedsToBe() throws {
        let sync = CloudSync(storingIn: context)
        let list = try #require(try context.addList(named: "Groceries"))
        let share = CKShare(recordZoneID: list.zoneID)

        #expect(sync.dress(share, for: list))
        #expect(share[CKShare.SystemFieldKey.title] as? String == "Groceries")
        let card = try #require(share[CKShare.SystemFieldKey.thumbnailImageData] as? Data)
        // A PNG, and small enough to travel with the link.
        #expect(card.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(card.count < 400_000)

        #expect(sync.dress(share, for: list) == false, "nothing to save a second time")
        context.rename(list, to: "Food")
        #expect(sync.dress(share, for: list), "a renamed list is dressed again")
        #expect(share[CKShare.SystemFieldKey.title] as? String == "Food")
    }

    @Test func theCardIsDrawnForShortAndLongNames() throws {
        for name in ["life", "Groceries for the cabin this weekend", "買い物", "a"] {
            let card = try #require(ShareCard.png(named: name), "\(name)")
            #expect(card.count > 1000)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("sharecard-\(name.count).png")
            try card.write(to: file)
            print("SHARECARD \(file.path)")
        }
    }
}
