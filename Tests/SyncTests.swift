import CloudKit
import Foundation
import SwiftData
import Testing

@testable import SansSerif

/// What iCloud says, written into the store. There is no iCloud in a test, so
/// the records are made here and handed to the sync as iCloud would hand them.
/// Sending, sharing and accounts need the real thing and are not covered.
@MainActor
@Suite("What iCloud says, written into the store")
struct SyncTests {
    let container: ModelContainer
    var context: ModelContext { container.mainContext }
    let sync: CloudSync

    init() throws {
        container = try PageStore.makeContainer(inMemory: true)
        sync = CloudSync(storingIn: container.mainContext)
    }

    // MARK: Records as iCloud would send them

    private func zone(_ list: UUID, owner: String? = nil) -> CKRecordZone.ID {
        RecordCoder.zoneID(for: list, owner: owner)
    }

    private func listRecord(_ id: UUID, name: String, order: Double = 0, owner: String? = nil) -> CKRecord {
        let record = CKRecord(
            recordType: RecordCoder.listType,
            recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zone(id, owner: owner))
        )
        RecordCoder.write(.init(name: name, order: order, created: Date(timeIntervalSince1970: 1_700_000_000)), to: record)
        return record
    }

    private func taskRecord(
        _ id: UUID, in list: UUID, text: String, order: Double = 0, struck: Date? = nil, owner: String? = nil
    ) -> CKRecord {
        let record = CKRecord(
            recordType: RecordCoder.taskType,
            recordID: CKRecord.ID(recordName: id.uuidString, zoneID: zone(list, owner: owner))
        )
        RecordCoder.write(.init(
            text: text, order: order, created: Date(timeIntervalSince1970: 1_700_000_000), struck: struck
        ), to: record)
        return record
    }

    private func lists() throws -> [TaskList] { try context.lists() }
    private func tasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>(sortBy: [SortDescriptor(\.order)]))
    }

    // MARK: Lists

    @Test func aListFromICloudIsMadeHere() throws {
        let id = UUID()
        sync.applying { sync.take(list: listRecord(id, name: "errands", order: 4)) }
        let list = try #require(try lists().first)
        #expect(try lists().count == 1)
        #expect(list.id == id)
        #expect(list.name == "errands")
        #expect(list.order == 4)
        #expect(list.recordData != nil, "what iCloud said about it is kept")
        #expect(!list.isShared)
        #expect(!list.isSomeoneElses)
        #expect(!context.hasChanges, "what iCloud sent is saved")
    }

    @Test func aListAlreadyHereIsChangedAndNotMadeTwice() throws {
        let list = try #require(try context.addList(named: "life"))
        context.addTask("Mine", to: list)
        try context.save()
        sync.applying {
            sync.take(list: listRecord(list.id, name: "living", order: 7))
            sync.take(list: listRecord(list.id, name: "living", order: 7))
        }
        #expect(try lists().count == 1)
        #expect(list.name == "living")
        #expect(list.order == 7)
        #expect(list.liveTasks.map(\.text) == ["Mine"], "its tasks are left alone")
    }

    @Test func aListSomeoneElseSharedIsMarkedAsTheirs() throws {
        let id = UUID()
        sync.applying { sync.take(list: listRecord(id, name: "house", owner: "_ada")) }
        let list = try #require(try lists().first)
        #expect(list.isShared)
        #expect(list.isSomeoneElses)
        #expect(list.zoneOwner == "_ada")
        #expect(list.zoneID == zone(id, owner: "_ada"))
    }

    @Test func aRecordWithANameThatIsNoIdentityIsIgnored() throws {
        let record = CKRecord(
            recordType: RecordCoder.listType,
            recordID: CKRecord.ID(recordName: "not-a-list", zoneID: zone(UUID()))
        )
        sync.applying {
            sync.take(list: record)
            sync.take(task: record)
        }
        #expect(try lists().isEmpty)
        #expect(try tasks().isEmpty)
    }

    // MARK: Tasks

    @Test func aTaskFromICloudArrivesWithEverythingItHad() throws {
        let list = try #require(try context.addList(named: "life"))
        try context.save()
        let id = UUID()
        let struck = Date(timeIntervalSince1970: 1_800_000_000)
        let pen = Stroke.encode(Stroke.generated(lines: 2, seed: 5))
        let record = taskRecord(id, in: list.id, text: "Bins 🗑", order: 3, struck: struck)
        record["strokes"] = pen
        record["struckBy"] = "Ben"
        record["addedBy"] = "Ada"
        sync.applying { sync.take(task: record) }

        let task = try #require(try tasks().first)
        #expect(task.id == id)
        #expect(task.text == "Bins 🗑")
        #expect(task.order == 3)
        #expect(task.struckDate == struck)
        #expect(task.strokeData == pen)
        #expect(task.struckBy == "Ben")
        #expect(task.addedBy == "Ada")
        #expect(task.list === list)
        #expect(task.recordData != nil)
        #expect(list.archive().flatMap(\.tasks).count == 1)
    }

    @Test func aTaskThatArrivesBeforeItsListMakesAPlaceForIt() throws {
        let listID = UUID()
        let taskID = UUID()
        sync.applying { sync.take(task: taskRecord(taskID, in: listID, text: "Early")) }
        #expect(try lists().map(\.id) == [listID])
        #expect(try lists().first?.name == "", "the list is named when its own record comes")
        #expect(try tasks().first?.list?.id == listID)

        sync.applying { sync.take(list: listRecord(listID, name: "errands", order: 2)) }
        #expect(try lists().count == 1)
        #expect(try lists().first?.name == "errands")
        #expect(try lists().first?.liveTasks.map(\.text) == ["Early"])
    }

    @Test func aTaskEarlyOnASharedListMakesASharedList() throws {
        let listID = UUID()
        sync.applying { sync.take(task: taskRecord(UUID(), in: listID, text: "Theirs", owner: "_ada")) }
        let list = try #require(try lists().first)
        #expect(list.isShared)
        #expect(list.zoneOwner == "_ada")
    }

    @Test func aTaskInAZoneThatIsNotAListIsIgnored() throws {
        let record = CKRecord(
            recordType: RecordCoder.taskType,
            recordID: CKRecord.ID(
                recordName: UUID().uuidString,
                zoneID: CKRecordZone.ID(zoneName: "com.apple.coredata.cloudkit.zone", ownerName: CKCurrentUserDefaultName)
            )
        )
        record["text"] = "From an older build"
        sync.applying { sync.take(task: record) }
        #expect(try tasks().isEmpty)
        #expect(try lists().isEmpty)
    }

    @Test func aTaskMovedToAnotherListElsewhereMovesHere() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        let task = try #require(context.addTask("Wanders", to: life))
        try context.save()
        sync.applying { sync.take(task: taskRecord(task.id, in: work.id, text: "Wanders", order: 5)) }
        #expect(task.list === work)
        #expect(life.liveCount == 0)
        #expect(work.liveTasks.map(\.text) == ["Wanders"])
        #expect(try tasks().count == 1)
    }

    @Test func aRecordWithNothingInItGivesAnEmptyTaskAndDoesNotStop() throws {
        let list = try #require(try context.addList(named: "life"))
        try context.save()
        let record = CKRecord(
            recordType: RecordCoder.taskType,
            recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: zone(list.id))
        )
        sync.applying { sync.take(task: record) }
        let task = try #require(try tasks().first)
        #expect(task.text == "")
        #expect(task.order == 0)
        #expect(task.isLive)
    }

    @Test func aStrikeMadeElsewhereStrikesHereAndBroughtBackComesBack() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Shared work", to: list))
        task.circledDate = .now
        try context.save()
        let struck = Date(timeIntervalSince1970: 1_800_000_000)
        sync.applying { sync.take(task: taskRecord(task.id, in: list.id, text: "Shared work", struck: struck)) }
        #expect(task.struckDate == struck)
        #expect(!task.isCircled, "iCloud's copy has no circle")
        sync.applying { sync.take(task: taskRecord(task.id, in: list.id, text: "Shared work")) }
        #expect(task.isLive)
        #expect(list.liveCount == 1)
    }

    // MARK: Echoes

    @Test func anEchoDoesNotUndoAStrikeStillWaitingToGoOut() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Bins", to: list))
        try context.save()
        // Struck here a moment ago, and not sent yet.
        context.strike(task)
        let id = CKRecord.ID(recordName: task.id.uuidString, zoneID: list.zoneID)
        sync.heldBack = [id]
        // iCloud sends back the save before the strike.
        sync.applying { sync.take(task: taskRecord(task.id, in: list.id, text: "Bins")) }
        #expect(!task.isLive, "build 18 lost strikes this way")
        #expect(task.recordData != nil, "what iCloud said is still noted, for the next send")

        // Once the strike has gone out, iCloud's word is taken again.
        sync.heldBack = []
        sync.applying { sync.take(task: taskRecord(task.id, in: list.id, text: "Bins out")) }
        #expect(task.isLive)
        #expect(task.text == "Bins out")
    }

    @Test func anEchoDoesNotUndoARenameStillWaitingToGoOut() throws {
        let list = try #require(try context.addList(named: "life"))
        try context.save()
        context.rename(list, to: "living")
        sync.heldBack = [list.recordID]
        sync.applying { sync.take(list: listRecord(list.id, name: "life", order: 9)) }
        #expect(list.name == "living")
        #expect(list.order != 9)
        sync.heldBack = []
        sync.applying { sync.take(list: listRecord(list.id, name: "life", order: 9)) }
        #expect(list.name == "life")
        #expect(list.order == 9)
    }

    @Test func aChangeNotYetSavedHereIsSavedBeforeICloudsIsWrittenIn() throws {
        let list = try #require(try context.addList(named: "life"))
        context.addTask("Unsaved", to: list)
        #expect(context.hasChanges)
        sync.applying { sync.take(list: listRecord(UUID(), name: "errands", order: 5)) }
        #expect(!context.hasChanges)
        let other = ModelContext(container)
        #expect(try other.fetchCount(FetchDescriptor<TaskItem>()) == 1)
        #expect(try other.fetchCount(FetchDescriptor<TaskList>()) == 2)
    }

    // MARK: Things removed elsewhere

    @Test func aTaskRemovedElsewhereIsRemovedHere() throws {
        let list = try #require(try context.addList(named: "life"))
        let gone = try #require(context.addTask("Gone", to: list))
        context.addTask("Stays", to: list)
        try context.save()
        let id = CKRecord.ID(recordName: gone.id.uuidString, zoneID: list.zoneID)
        sync.applying { sync.remove(id, type: RecordCoder.taskType) }
        #expect(try tasks().map(\.text) == ["Stays"])
    }

    @Test func aRemovalThatIsNotForThisTaskRemovesNothing() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        let task = try #require(context.addTask("Here", to: life))
        try context.save()
        sync.applying {
            // The same task in the zone it moved out of.
            sync.remove(CKRecord.ID(recordName: task.id.uuidString, zoneID: work.zoneID), type: RecordCoder.taskType)
            // A list's record, removed: lists go with their zone, not their record.
            sync.remove(life.recordID, type: RecordCoder.listType)
            // Something of another kind with the task's name.
            sync.remove(CKRecord.ID(recordName: task.id.uuidString, zoneID: life.zoneID), type: "cloudkit.share")
            // A task never seen here, and a name that is no identity.
            sync.remove(CKRecord.ID(recordName: UUID().uuidString, zoneID: life.zoneID), type: RecordCoder.taskType)
            sync.remove(CKRecord.ID(recordName: "share", zoneID: life.zoneID), type: RecordCoder.taskType)
        }
        #expect(try tasks().map(\.text) == ["Here"])
        #expect(try lists().count == 2)
    }

    @Test func aListRemovedElsewhereGoesWithItsTasksAndItsArchive() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        context.addTask("Live", to: work)
        let struck = try #require(context.addTask("Struck", to: work))
        context.strike(struck)
        context.addTask("Mine", to: life)
        try context.save()
        sync.applying { sync.removeList(in: work.zoneID) }
        #expect(try lists().map(\.name) == ["life"])
        #expect(try tasks().map(\.text) == ["Mine"])
    }

    @Test func theLastListIsNeverRemovedOnlyCutLooseFromICloud() throws {
        let list = try #require(try context.addList(named: "house"))
        list.zoneOwner = "_ada"
        list.isShared = true
        list.recordData = Data([1])
        context.addTask("Still here", to: list)
        try context.save()
        sync.applying { sync.removeList(in: list.zoneID) }
        #expect(try lists().count == 1, "there would be no page left")
        #expect(list.recordData == nil)
        #expect(list.zoneOwner == nil)
        #expect(!list.isShared)
        #expect(list.liveTasks.map(\.text) == ["Still here"])
    }

    @Test func aZoneRemovedThatIsNotOneOfTheseListsRemovesNothing() throws {
        let life = try #require(try context.addList(named: "life"))
        try context.addList(named: "work")
        try context.save()
        sync.applying {
            sync.removeList(in: CKRecordZone.ID(zoneName: "_defaultZone", ownerName: CKCurrentUserDefaultName))
            sync.removeList(in: zone(UUID()))
            // The same list as someone else's would have it: not this one.
            sync.removeList(in: zone(life.id, owner: "_ada"))
        }
        #expect(try lists().map(\.name) == ["life", "work"])
    }

    // MARK: What is sent

    @Test func theRecordSentForAListAndATaskCarriesWhatIsInTheStore() throws {
        let list = try #require(try context.addList(named: "life"))
        list.order = 2
        let task = try #require(context.addTask("Bins", to: list))
        context.toggleCircle(task)
        try context.save()

        let sentList = try #require(sync.record(for: list.recordID))
        #expect(sentList.recordType == RecordCoder.listType)
        #expect(RecordCoder.listFields(of: sentList) == list.fields)

        let id = CKRecord.ID(recordName: task.id.uuidString, zoneID: list.zoneID)
        let sentTask = try #require(sync.record(for: id))
        #expect(sentTask.recordType == RecordCoder.taskType)
        #expect(sentTask.recordID == id)
        #expect(RecordCoder.taskFields(of: sentTask) == task.fields)
        #expect(RecordCoder.taskFields(of: sentTask).circled != nil)
    }

    @Test func nothingIsSentForWhatIsGoneOrHasMoved() throws {
        let life = try #require(try context.addList(named: "life"))
        let work = try #require(try context.addList(named: "work"))
        let task = try #require(context.addTask("Wanders", to: life))
        try context.save()
        let old = CKRecord.ID(recordName: task.id.uuidString, zoneID: life.zoneID)
        context.move(task, to: work)
        try context.save()
        #expect(sync.record(for: old) == nil, "it is no longer in that list")
        #expect(sync.record(for: CKRecord.ID(recordName: task.id.uuidString, zoneID: work.zoneID)) != nil)
        #expect(sync.record(for: CKRecord.ID(recordName: UUID().uuidString, zoneID: life.zoneID)) == nil)
        #expect(sync.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: life.zoneID)) == nil)

        context.delete(task)
        try context.save()
        #expect(sync.record(for: CKRecord.ID(recordName: task.id.uuidString, zoneID: work.zoneID)) == nil)
    }

    @Test func whatICloudSaidOnSavingIsKeptForBothKinds() throws {
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Bins", to: list))
        try context.save()
        #expect(list.recordData == nil)
        #expect(task.recordData == nil)
        sync.applying {
            sync.rememberSystemFields(of: listRecord(list.id, name: "life"))
            sync.rememberSystemFields(of: taskRecord(task.id, in: list.id, text: "Bins"))
            // Saved for something that has since gone: nothing to note, and no harm.
            sync.rememberSystemFields(of: taskRecord(UUID(), in: list.id, text: "Gone"))
        }
        #expect(list.recordData != nil)
        #expect(task.recordData != nil)
        #expect(list.name == "life")
        // The next send goes out on top of what iCloud said.
        let next = try #require(sync.record(for: list.recordID))
        #expect(next.recordID == list.recordID)
    }

    @Test func aWholePageArrivingAtOnceIsAllThere() throws {
        let listID = UUID()
        let records = (0..<300).map { taskRecord(UUID(), in: listID, text: "Task \($0)", order: Double($0)) }
        sync.applying {
            // Tasks first, as iCloud may send them, then their list.
            for record in records { sync.take(task: record) }
            sync.take(list: listRecord(listID, name: "errands"))
        }
        #expect(try lists().count == 1)
        let live = try #require(try lists().first).liveTasks
        #expect(live.count == 300)
        #expect(live.first?.text == "Task 0")
        #expect(live.last?.text == "Task 299")
    }
}

@Suite("Records at the edges")
struct RecordEdgeTests {
    @Test func onlyAZoneNamedForAListGivesAList() {
        let id = UUID()
        #expect(RecordCoder.listID(fromZone: RecordCoder.zoneName(for: id)) == id)
        #expect(RecordCoder.listID(fromZone: "list-\(id.uuidString.lowercased())") == id)
        for name in ["", "list-", "list-not-an-id", "tasks-\(id.uuidString)", id.uuidString, "_defaultZone",
                     "LIST-\(id.uuidString)", "list-\(id.uuidString)-extra"] {
            #expect(RecordCoder.listID(fromZone: name) == nil, "\(name)")
        }
    }

    @Test func aListOfOnesOwnIsInOnesOwnPartOfICloud() {
        let id = UUID()
        #expect(RecordCoder.zoneID(for: id, owner: nil).ownerName == CKCurrentUserDefaultName)
        #expect(RecordCoder.zoneID(for: id, owner: "_ada").ownerName == "_ada")
        #expect(RecordCoder.zoneID(for: id, owner: nil).zoneName == RecordCoder.zoneID(for: id, owner: "_ada").zoneName)
    }

    @Test func whatICloudSaidIsOnlyUsedForTheRecordItWasSaidAbout() {
        let zone = RecordCoder.zoneID(for: UUID(), owner: nil)
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        let other = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        let said = RecordCoder.systemFields(of: CKRecord(recordType: RecordCoder.taskType, recordID: id))

        let same = RecordCoder.record(type: RecordCoder.taskType, id: id, systemFields: said)
        #expect(same.recordID == id)
        #expect(same.recordType == RecordCoder.taskType)
        // About another record, about another kind of record, or not readable at all: a new record.
        for (type, identity, data) in [
            (RecordCoder.taskType, other, said),
            (RecordCoder.listType, id, said),
            (RecordCoder.taskType, id, Data([0, 1, 2, 3])),
            (RecordCoder.taskType, id, Data()),
        ] {
            let record = RecordCoder.record(type: type, id: identity, systemFields: data)
            #expect(record.recordID == identity)
            #expect(record.recordType == type)
        }
        #expect(RecordCoder.record(type: RecordCoder.listType, id: id, systemFields: nil).recordType == RecordCoder.listType)
    }

    @Test func whatICloudSaidDoesNotCarryTheFieldsWithIt() {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: RecordCoder.zoneID(for: UUID(), owner: nil))
        let record = CKRecord(recordType: RecordCoder.taskType, recordID: id)
        record["text"] = "Private words"
        let again = RecordCoder.record(
            type: RecordCoder.taskType, id: id, systemFields: RecordCoder.systemFields(of: record)
        )
        #expect(again["text"] == nil)
    }

    @Test func aFieldThatWasClearedIsClearedInTheRecord() {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: RecordCoder.zoneID(for: UUID(), owner: nil))
        let record = CKRecord(recordType: RecordCoder.taskType, recordID: id)
        var fields = RecordCoder.TaskFields(
            text: "Bins", order: 1, created: .now, struck: .now, strokes: Data([1]), struckBy: "Ben",
            addedBy: "Ada", circled: .now
        )
        RecordCoder.write(fields, to: record)
        #expect(record["struck"] != nil)
        fields.struck = nil
        fields.strokes = nil
        fields.struckBy = nil
        fields.circled = nil
        RecordCoder.write(fields, to: record)
        #expect(record["struck"] == nil)
        #expect(record["strokes"] == nil)
        #expect(record["struckBy"] == nil)
        #expect(record["circled"] == nil)
        #expect(RecordCoder.taskFields(of: record) == fields)
    }

    @Test func aRecordMissingItsFieldsOrHoldingTheWrongKindReadsAsEmpty() {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: RecordCoder.zoneID(for: UUID(), owner: nil))
        let record = CKRecord(recordType: RecordCoder.taskType, recordID: id)
        record["text"] = 42
        record["order"] = "first"
        record["struck"] = "yesterday"
        let task = RecordCoder.taskFields(of: record)
        #expect(task.text == "")
        #expect(task.order == 0)
        #expect(task.struck == nil)
        let list = RecordCoder.listFields(of: CKRecord(recordType: RecordCoder.listType, recordID: id))
        #expect(list.name == "")
        #expect(list.order == 0)
    }

    @Test(arguments: ["", "🧺 Laundry", "שלום", String(repeating: "x", count: 20000), "two\nlines"])
    func anyTextGoesToARecordAndBack(text: String) {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: RecordCoder.zoneID(for: UUID(), owner: nil))
        let record = CKRecord(recordType: RecordCoder.taskType, recordID: id)
        let fields = RecordCoder.TaskFields(text: text, order: -1.5, created: Date(timeIntervalSince1970: 0))
        RecordCoder.write(fields, to: record)
        #expect(RecordCoder.taskFields(of: record) == fields)
    }

    @MainActor
    @Test func writingBackWhatIsAlreadyThereChangesNothingInTheStore() throws {
        let container = try PageStore.makeContainer(inMemory: true)
        let context = container.mainContext
        let list = try #require(try context.addList(named: "life"))
        let task = try #require(context.addTask("Bins", to: list))
        context.strike(task, strokeData: Data([1, 2]), by: "Ben")
        try context.save()
        #expect(!context.hasChanges)
        list.fields = list.fields
        task.fields = task.fields
        #expect(!context.hasChanges, "the page does not redraw for nothing")
        var fields = task.fields
        fields.text = "Bins out"
        task.fields = fields
        #expect(context.hasChanges)
        #expect(task.text == "Bins out")
    }
}

@Suite("People on a shared list")
struct SharePeopleTests {
    private func person(_ name: String, owner: Bool = false, me: Bool = false, waiting: Bool = false) -> SharePerson {
        SharePerson(id: name, name: name, isOwner: owner, isMe: me, isWaiting: waiting)
    }

    @Test func aPersonIsNamedByTheBestThingICloudGives() {
        var components = PersonNameComponents()
        components.givenName = "Ada"
        components.familyName = "Lovelace"
        #expect(SharePerson.name(components: components, email: "ada@example.com", phone: nil).contains("Ada"))
        #expect(SharePerson.name(components: nil, email: "ada@example.com", phone: "+15550100") == "ada@example.com")
        #expect(SharePerson.name(components: nil, email: nil, phone: "+15550100") == "+15550100")
        #expect(SharePerson.name(components: nil, email: "", phone: "") == "Someone")
        #expect(SharePerson.name(components: PersonNameComponents(), email: nil, phone: nil) == "Someone")
    }

    @Test func theOwnerComesFirstAndTheRestByName() {
        let people = [person("zoe"), person("Ben"), person("Wayne", owner: true), person("ada")]
        #expect(people.sorted(by: SharePerson.before).map(\.name) == ["Wayne", "ada", "Ben", "zoe"])
    }

    @Test func whatStandsAfterANameSaysWhoTheyAreToTheList() {
        #expect(person("a", owner: true, me: true).note == "you, owner")
        #expect(person("a", me: true).note == "you")
        #expect(person("a", owner: true).note == "owner")
        #expect(person("a", waiting: true).note == "invited")
        #expect(person("a").note == nil)
        #expect(person("a", me: true, waiting: true).note == "you")
    }
}

@Suite("The name the user goes by")
struct OwnNameTests {
    @Test(arguments: [
        ("  Wayne  ", "Wayne"), ("Wayne\nXu", "Wayne Xu"), ("", ""), ("   \n ", ""), ("🧺", "🧺"),
        (String(repeating: "a", count: 90), String(repeating: "a", count: 40)),
    ])
    func aNameIsKeptOnOneLineTrimmedAndNotTooLong(pair: (String, String)) {
        #expect(CloudSync.tidied(pair.0) == pair.1)
    }
}

/// Build 21 stopped at every launch because the app asked an engine to send
/// while it was already sending. Everything asked of the engines now takes turns.
@MainActor
@Suite("One at a time")
struct OneAtATimeTests {
    @Test func workAskedForAtTheSameTimeNeverOverlapsAndKeepsItsOrder() async {
        let turn = OneAtATime()
        let seen = Seen()
        var asked: [Task<Void, Never>] = []
        for number in 0..<40 {
            asked.append(Task { @MainActor in
                await turn.run {
                    seen.running += 1
                    seen.most = max(seen.most, seen.running)
                    // Long enough for the others to pile up behind it.
                    try? await Task.sleep(for: .milliseconds(number % 3 == 0 ? 8 : 1))
                    seen.order.append(number)
                    seen.running -= 1
                }
            })
            // Each asks a moment after the last, as saves follow one another.
            try? await Task.sleep(for: .milliseconds(1))
        }
        for one in asked { await one.value }
        #expect(seen.most == 1, "two were in at once")
        #expect(seen.order == Array(0..<40), "in the order they asked")
        #expect(seen.running == 0)
    }

    @MainActor
    private final class Seen {
        var running = 0
        var most = 0
        var order: [Int] = []
    }

    @Test func theTurnIsFreeAgainAfterTheLastOneLeaves() async {
        let turn = OneAtATime()
        let first = await turn.run { 1 }
        let second = await turn.run { 2 }
        #expect(first + second == 3)
        // And after a pile-up.
        let one = Task { @MainActor in
            await turn.run {
                try? await Task.sleep(for: .milliseconds(5))
                return "a"
            }
        }
        let two = Task { @MainActor in await turn.run { "b" } }
        let both = [await one.value, await two.value]
        #expect(Set(both) == ["a", "b"])
        #expect(await turn.run { "free" } == "free")
    }

    @Test func workInsideWorkOnAnotherGateDoesNotLockUp() async {
        let outer = OneAtATime()
        let inner = OneAtATime()
        let result = await outer.run { await inner.run { "through" } }
        #expect(result == "through")
    }
}
