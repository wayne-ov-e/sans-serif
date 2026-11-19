import CloudKit
import Foundation
import SwiftData

/// Keeps the lists in step with iCloud, and shares a list with other people.
///
/// The lists are stored on the device by SwiftData, which cannot share with
/// other people. So iCloud is spoken to here, through `CKSyncEngine`: every
/// list in a zone of its own (see `RecordCoder`). There are two engines. One
/// is for the user's own lists, in their private database. The other is for
/// lists other people shared with them, which iCloud keeps in a database of
/// its own.
///
/// Changes go out a moment after the store is saved. Changes made elsewhere
/// arrive by push, a few seconds after they are made, and are written into
/// the store, where the page sees them like any other change.
@MainActor
final class CloudSync {
    static let shared = CloudSync()

    private let container = CKContainer(identifier: PageStore.cloudContainer)
    private var context: ModelContext?
    private var mine: CKSyncEngine?
    private var theirs: CKSyncEngine?
    private var observer: (any NSObjectProtocol)?
    private var listener: Listener?
    /// True while what iCloud sent is being written into the store. Those
    /// changes came from iCloud and are not sent back to it.
    private var isApplying = false
    /// The zone each task was last known to be in, to tell when one moves to another list.
    private var zoneOfTask: [UUID: CKRecordZone.ID] = [:]
    /// The zone of each list, kept for the moment a list is deleted.
    private var zoneOfList: [UUID: CKRecordZone.ID] = [:]

    private static let nameKey = "cloudSync.myName"

    /// The user's name as iCloud gives it to people they share with. Known
    /// once a shared list has been opened.
    var myName: String? {
        get { UserDefaults.standard.string(forKey: Self.nameKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.nameKey) }
    }

    var isRunning: Bool { mine != nil }

    // MARK: Starting

    func start(context: ModelContext) {
        guard mine == nil else { return }
        self.context = context
        let delegate = Listener(owner: self)
        // The engines do not keep their delegate alive. Without this it is gone at once, and they say nothing.
        listener = delegate
        mine = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: Self.state(.private), delegate: delegate
        ))
        theirs = CKSyncEngine(CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase, stateSerialization: Self.state(.shared), delegate: delegate
        ))
        for list in lists() {
            zoneOfList[list.id] = list.zoneID
            for task in list.tasks ?? [] { zoneOfTask[task.id] = list.zoneID }
        }
        // Whatever iCloud has never heard of goes out now: the first time, that is everything.
        for list in lists() where list.recordData == nil { queue(list, withTasks: true) }
        for task in tasks() where task.recordData == nil { queue(task) }
        observer = NotificationCenter.default.addObserver(
            forName: ModelContext.willSave, object: context, queue: .main
        ) { _ in
            MainActor.assumeIsolated { CloudSync.shared.storeWillSave() }
        }
    }

    private func engine(for zone: CKRecordZone.ID) -> CKSyncEngine? {
        zone.ownerName == CKCurrentUserDefaultName ? mine : theirs
    }

    private func lists() -> [TaskList] { (try? context?.fetch(FetchDescriptor<TaskList>())) ?? [] }
    private func tasks() -> [TaskItem] { (try? context?.fetch(FetchDescriptor<TaskItem>())) ?? [] }

    // MARK: What changed here

    /// The store is about to be saved: everything added, changed or removed since the last save is queued.
    private func storeWillSave() {
        guard !isApplying, let context else { return }
        for model in context.deletedModelsArray {
            if let list = model as? TaskList {
                guard let zone = zoneOfList.removeValue(forKey: list.id) else { continue }
                // The whole zone goes. For a list someone else shared, that is leaving it.
                engine(for: zone)?.state.add(pendingDatabaseChanges: [.deleteZone(zone)])
                for task in list.tasks ?? [] { zoneOfTask[task.id] = nil }
            } else if let task = model as? TaskItem {
                guard let zone = zoneOfTask.removeValue(forKey: task.id), zoneOfList.values.contains(zone) else { continue }
                engine(for: zone)?.state.add(pendingRecordZoneChanges: [
                    .deleteRecord(CKRecord.ID(recordName: task.id.uuidString, zoneID: zone)),
                ])
            }
        }
        for model in context.insertedModelsArray + context.changedModelsArray {
            if let list = model as? TaskList {
                queue(list, withTasks: false)
            } else if let task = model as? TaskItem {
                queue(task)
            }
        }
    }

    private func queue(_ list: TaskList, withTasks: Bool) {
        let zone = list.zoneID
        if zoneOfList[list.id] == nil || list.recordData == nil, !list.isSomeoneElses {
            mine?.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zone))])
        }
        zoneOfList[list.id] = zone
        engine(for: zone)?.state.add(pendingRecordZoneChanges: [.saveRecord(list.recordID)])
        if withTasks { for task in list.tasks ?? [] { queue(task) } }
    }

    private func queue(_ task: TaskItem) {
        guard let list = task.list else { return }
        let zone = list.zoneID
        if let old = zoneOfTask[task.id], old != zone {
            // Moved to another list: it leaves the old zone and is written afresh in the new one.
            engine(for: old)?.state.add(pendingRecordZoneChanges: [
                .deleteRecord(CKRecord.ID(recordName: task.id.uuidString, zoneID: old)),
            ])
            task.recordData = nil
        }
        zoneOfTask[task.id] = zone
        engine(for: zone)?.state.add(pendingRecordZoneChanges: [
            .saveRecord(CKRecord.ID(recordName: task.id.uuidString, zoneID: zone)),
        ])
    }

    // MARK: Sending

    /// The record to send for an identity iCloud is waiting on, or nothing if it is gone.
    fileprivate func record(for id: CKRecord.ID) -> CKRecord? {
        guard let uuid = UUID(uuidString: id.recordName) else { return nil }
        if let list = lists().first(where: { $0.id == uuid }), list.zoneID == id.zoneID {
            let record = RecordCoder.record(type: RecordCoder.listType, id: id, systemFields: list.recordData)
            RecordCoder.write(list.fields, to: record)
            return record
        }
        if let task = tasks().first(where: { $0.id == uuid }), task.list?.zoneID == id.zoneID {
            let record = RecordCoder.record(type: RecordCoder.taskType, id: id, systemFields: task.recordData)
            RecordCoder.write(task.fields, to: record)
            return record
        }
        return nil
    }

    // MARK: What iCloud says

    fileprivate func handle(_ event: CKSyncEngine.Event, from engine: CKSyncEngine) {
        #if DEBUG
        Self.log(event, mine: engine === mine)
        #endif
        switch event {
        case .stateUpdate(let update):
            Self.keep(update.stateSerialization, engine === mine ? .private : .shared)
        case .fetchedDatabaseChanges(let changes):
            applying {
                for deletion in changes.deletions { removeList(in: deletion.zoneID) }
            }
        case .fetchedRecordZoneChanges(let changes):
            applying {
                // Lists before tasks, so that a task finds its list.
                let records = changes.modifications.map(\.record)
                for record in records where record.recordType == RecordCoder.listType { take(list: record) }
                for record in records where record.recordType == RecordCoder.taskType { take(task: record) }
                for deletion in changes.deletions { remove(deletion.recordID, type: deletion.recordType) }
            }
            // Two devices each made life, work and home before they met. Folding
            // them together is a change of ours, and goes out like any other.
            _ = try? context?.mergeDuplicateDefaultLists()
            try? context?.save()
        case .sentRecordZoneChanges(let sent):
            applying {
                for record in sent.savedRecords { rememberSystemFields(of: record) }
                for failure in sent.failedRecordSaves { resolve(failure, in: engine) }
            }
        case .accountChange(let change):
            if case .signIn = change.changeType { return }
            // Signed out, or another account: what iCloud knew of these lists no longer holds.
            applying {
                for list in lists() { list.recordData = nil }
                for task in tasks() { task.recordData = nil }
            }
        default:
            break
        }
    }

    /// Runs changes that come from iCloud, saved without being sent back to it.
    private func applying(_ changes: () -> Void) {
        // What the user changed and the store has not saved yet is theirs, and
        // is saved first, so that it is sent and not taken for iCloud's.
        try? context?.save()
        isApplying = true
        changes()
        try? context?.save()
        isApplying = false
    }

    private func take(list record: CKRecord) {
        guard let context, let id = UUID(uuidString: record.recordID.recordName) else { return }
        let zone = record.recordID.zoneID
        let list = lists().first { $0.id == id } ?? {
            let new = TaskList(name: "", order: 0)
            new.id = id
            context.insert(new)
            return new
        }()
        list.fields = RecordCoder.listFields(of: record)
        list.recordData = RecordCoder.systemFields(of: record)
        if zone.ownerName != CKCurrentUserDefaultName {
            list.zoneOwner = zone.ownerName
            list.isShared = true
        }
        zoneOfList[id] = zone
    }

    private func take(task record: CKRecord) {
        guard let context, let id = UUID(uuidString: record.recordID.recordName),
              let listID = RecordCoder.listID(fromZone: record.recordID.zoneID.zoneName)
        else { return }
        let zone = record.recordID.zoneID
        // A task can arrive before its list. The list is made now and named when its own record comes.
        let list = lists().first { $0.id == listID } ?? {
            let new = TaskList(name: "", order: Double(lists().count))
            new.id = listID
            if zone.ownerName != CKCurrentUserDefaultName {
                new.zoneOwner = zone.ownerName
                new.isShared = true
            }
            context.insert(new)
            zoneOfList[listID] = zone
            return new
        }()
        let fields = RecordCoder.taskFields(of: record)
        let task = tasks().first { $0.id == id } ?? {
            let new = TaskItem(text: fields.text, order: fields.order, list: list)
            new.id = id
            context.insert(new)
            return new
        }()
        task.fields = fields
        if task.list !== list { task.list = list }
        task.recordData = RecordCoder.systemFields(of: record)
        zoneOfTask[id] = zone
    }

    private func remove(_ id: CKRecord.ID, type: CKRecord.RecordType) {
        guard let context, let uuid = UUID(uuidString: id.recordName) else { return }
        if type == RecordCoder.taskType, let task = tasks().first(where: { $0.id == uuid }),
           task.list?.zoneID == id.zoneID {
            zoneOfTask[uuid] = nil
            context.delete(task)
        }
    }

    private func removeList(in zone: CKRecordZone.ID) {
        guard let context, let id = RecordCoder.listID(fromZone: zone.zoneName),
              let list = lists().first(where: { $0.id == id }), list.zoneID == zone
        else { return }
        // The last list is never removed: there would be no page left.
        guard lists().count > 1 else {
            list.recordData = nil
            list.zoneOwner = nil
            list.isShared = false
            return
        }
        zoneOfList[id] = nil
        for task in list.tasks ?? [] { zoneOfTask[task.id] = nil }
        context.delete(list)
    }

    private func rememberSystemFields(of record: CKRecord) {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return }
        let data = RecordCoder.systemFields(of: record)
        if record.recordType == RecordCoder.listType {
            lists().first { $0.id == id }?.recordData = data
        } else {
            tasks().first { $0.id == id }?.recordData = data
        }
    }

    /// A change that iCloud would not take.
    private func resolve(_ failure: CKSyncEngine.Event.SentRecordZoneChanges.FailedRecordSave, in engine: CKSyncEngine) {
        let id = failure.record.recordID
        switch failure.error.code {
        case .serverRecordChanged:
            // Someone else changed it first. Theirs stands: the last change to reach iCloud wins.
            guard let server = failure.error.serverRecord else { return }
            if server.recordType == RecordCoder.listType { take(list: server) } else { take(task: server) }
        case .zoneNotFound, .userDeletedZone:
            // The zone has to exist before anything can be written in it.
            if id.zoneID.ownerName == CKCurrentUserDefaultName {
                engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: id.zoneID))])
                engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }
        case .unknownItem:
            // iCloud no longer has the record this was a change to. It is written afresh.
            if let uuid = UUID(uuidString: id.recordName) {
                lists().first { $0.id == uuid }?.recordData = nil
                tasks().first { $0.id == uuid }?.recordData = nil
            }
            engine.state.add(pendingRecordZoneChanges: [.saveRecord(id)])
        default:
            // The network, a busy server, a full account: the engine tries again by itself.
            break
        }
    }

    #if DEBUG
    /// What the engines are doing, in the console of a development build.
    private static func log(_ event: CKSyncEngine.Event, mine: Bool) {
        let side = mine ? "private" : "shared"
        switch event {
        case .accountChange(let change): NSLog("SYNC \(side): account \(String(describing: change.changeType))")
        case .fetchedDatabaseChanges(let changes):
            NSLog("SYNC \(side): zones changed \(changes.modifications.count), deleted \(changes.deletions.count)")
        case .fetchedRecordZoneChanges(let changes):
            NSLog("SYNC \(side): fetched \(changes.modifications.count) records, \(changes.deletions.count) deletions")
        case .sentDatabaseChanges(let sent):
            NSLog("SYNC \(side): zones saved \(sent.savedZones.count), failed \(sent.failedZoneSaves.map { $0.error.code.rawValue })")
        case .sentRecordZoneChanges(let sent):
            NSLog("SYNC \(side): records saved \(sent.savedRecords.count), failed \(sent.failedRecordSaves.map { $0.error.code.rawValue }), deleted \(sent.deletedRecordIDs.count)")
        case .didFetchRecordZoneChanges(let done):
            if let error = done.error { NSLog("SYNC \(side): fetch of \(done.zoneID.zoneName) failed \(error.code.rawValue)") }
        default: break
        }
    }
    #endif

    // MARK: The engines' memory

    private enum Side: String { case `private`, shared }

    private static func state(_ side: Side) -> CKSyncEngine.State.Serialization? {
        guard let data = UserDefaults.standard.data(forKey: "cloudSync.state.\(side.rawValue)") else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private static func keep(_ state: CKSyncEngine.State.Serialization, _ side: Side) {
        UserDefaults.standard.set(try? JSONEncoder().encode(state), forKey: "cloudSync.state.\(side.rawValue)")
    }

    // MARK: Sharing

    /// The share for a list, made if it has none yet. The list's zone is
    /// shared, so its tasks and its archive go with it and nothing else does.
    func share(for list: TaskList) async throws -> CKShare {
        guard let mine, !list.isSomeoneElses else { throw CKError(.permissionFailure) }
        // The list has to be in iCloud before it can be shared.
        try await mine.sendChanges()
        let zone = list.zoneID
        let database = container.privateCloudDatabase
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone)
        let share: CKShare
        if let existing = try? await database.record(for: shareID) as? CKShare {
            share = existing
        } else {
            let new = CKShare(recordZoneID: zone)
            new[CKShare.SystemFieldKey.title] = list.name
            new.publicPermission = .none
            guard let saved = try await database.save(new) as? CKShare else { throw CKError(.internalError) }
            share = saved
        }
        list.isShared = true
        list.shareURL = share.url?.absoluteString
        noteName(from: share)
        return share
    }

    /// The share of a list someone else shared, to see who is on it or to leave.
    func joinedShare(for list: TaskList) async throws -> CKShare {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: list.zoneID)
        guard let share = try await container.sharedCloudDatabase.record(for: shareID) as? CKShare else {
            throw CKError(.unknownItem)
        }
        noteName(from: share)
        return share
    }

    var cloudContainer: CKContainer { container }

    /// An invitation was opened: the list is joined and fetched.
    func accept(_ metadata: CKShare.Metadata) async {
        do {
            let share = try await container.accept(metadata)
            noteName(from: share)
            try await theirs?.fetchChanges()
        } catch {
            // The invitation was withdrawn, or there is no network. Nothing is joined.
        }
    }

    /// The list is no longer shared with anyone: sharing was stopped from the share sheet.
    func sharingStopped(for list: TaskList) {
        list.isShared = false
        list.shareURL = nil
    }

    private func noteName(from share: CKShare) {
        guard let components = share.currentUserParticipant?.userIdentity.nameComponents else { return }
        let name = PersonNameComponentsFormatter.localizedString(from: components, style: .short)
        if !name.isEmpty { myName = name }
    }
}

/// The engines speak on threads of their own. This hears them and passes what
/// they say to the main actor, where the store lives.
private final class Listener: CKSyncEngineDelegate {
    private unowned let owner: CloudSync

    init(owner: CloudSync) {
        self.owner = owner
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await owner.handle(event, from: syncEngine)
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let owner = owner
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            if let record = await owner.record(for: id) { return record }
            // Gone since it was queued: nothing to send.
            syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            return nil
        }
    }
}
