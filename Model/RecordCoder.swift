import CloudKit
import Foundation

/// How lists and tasks are written to iCloud. Plain data in, plain data out,
/// apart from the store and the network, so that it can be tested.
///
/// Every list has a zone of its own, holding the list's record and its tasks.
/// A zone is the smallest thing iCloud can share with other people, so a list
/// shared is its zone shared, and nothing of the user's other lists goes with it.
enum RecordCoder {
    static let listType = "List"
    static let taskType = "Task"

    /// The zone a list lives in. The same on every device, from the list's own identity.
    static func zoneName(for list: UUID) -> String {
        "list-\(list.uuidString)"
    }

    /// The list a zone holds, if it is one of ours.
    static func listID(fromZone name: String) -> UUID? {
        guard name.hasPrefix("list-") else { return nil }
        return UUID(uuidString: String(name.dropFirst(5)))
    }

    /// The zone of a list. `owner` is empty for the user's own lists, and the
    /// owner's iCloud name for a list someone else shared.
    static func zoneID(for list: UUID, owner: String?) -> CKRecordZone.ID {
        CKRecordZone.ID(zoneName: zoneName(for: list), ownerName: owner ?? CKCurrentUserDefaultName)
    }

    /// What iCloud last said about a record, kept so that the next change to
    /// it is taken as following on from that and not as a clash.
    static func systemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// The record as iCloud last knew it, without its fields, or a new one.
    static func record(type: String, id: CKRecord.ID, systemFields: Data?) -> CKRecord {
        if let systemFields, let coder = try? NSKeyedUnarchiver(forReadingFrom: systemFields) {
            coder.requiresSecureCoding = true
            if let record = CKRecord(coder: coder), record.recordID == id, record.recordType == type {
                return record
            }
        }
        return CKRecord(recordType: type, recordID: id)
    }

    // MARK: Lists

    struct ListFields: Equatable {
        var name: String
        var order: Double
        var created: Date
    }

    static func write(_ fields: ListFields, to record: CKRecord) {
        record["name"] = fields.name
        record["order"] = fields.order
        record["created"] = fields.created
    }

    static func listFields(of record: CKRecord) -> ListFields {
        ListFields(
            name: record["name"] as? String ?? "",
            order: record["order"] as? Double ?? 0,
            created: record["created"] as? Date ?? record.creationDate ?? .now
        )
    }

    // MARK: Tasks

    struct TaskFields: Equatable {
        var text: String
        var order: Double
        var created: Date
        var struck: Date?
        var strokes: Data?
        var struckBy: String?
        var addedBy: String?
        var circled: Date?
        var editedBy: String? = nil
    }

    static func write(_ fields: TaskFields, to record: CKRecord) {
        record["text"] = fields.text
        record["order"] = fields.order
        record["created"] = fields.created
        record["struck"] = fields.struck
        record["strokes"] = fields.strokes
        record["struckBy"] = fields.struckBy
        record["addedBy"] = fields.addedBy
        record["circled"] = fields.circled
        // Written only when it differs: a task nobody has edited never
        // mentions the field, which iCloud learned later than the others.
        if record["editedBy"] as? String != fields.editedBy { record["editedBy"] = fields.editedBy }
    }

    static func taskFields(of record: CKRecord) -> TaskFields {
        TaskFields(
            text: record["text"] as? String ?? "",
            order: record["order"] as? Double ?? 0,
            created: record["created"] as? Date ?? record.creationDate ?? .now,
            struck: record["struck"] as? Date,
            strokes: record["strokes"] as? Data,
            struckBy: record["struckBy"] as? String,
            addedBy: record["addedBy"] as? String,
            circled: record["circled"] as? Date,
            editedBy: record["editedBy"] as? String
        )
    }
}

extension TaskList {
    /// The zone this list lives in.
    var zoneID: CKRecordZone.ID { RecordCoder.zoneID(for: id, owner: zoneOwner) }
    var recordID: CKRecord.ID { CKRecord.ID(recordName: id.uuidString, zoneID: zoneID) }

    /// Someone else's list, shared with the user.
    var isSomeoneElses: Bool { zoneOwner != nil }

    var fields: RecordCoder.ListFields {
        get { RecordCoder.ListFields(name: name, order: order, created: createdDate) }
        set {
            if name != newValue.name { name = newValue.name }
            if order != newValue.order { order = newValue.order }
            if createdDate != newValue.created { createdDate = newValue.created }
        }
    }
}

extension TaskItem {
    /// On a shared list, who the task is by: whoever last changed its words,
    /// when that was someone other than the person who wrote it.
    var byLine: String? {
        if let editedBy, !editedBy.isEmpty, editedBy != addedBy { return "Edited by \(editedBy)" }
        if let addedBy, !addedBy.isEmpty { return "Added by \(addedBy)" }
        return nil
    }

    var fields: RecordCoder.TaskFields {
        get {
            RecordCoder.TaskFields(
                text: text, order: order, created: createdDate, struck: struckDate, strokes: strokeData,
                struckBy: struckBy, addedBy: addedBy, circled: circledDate, editedBy: editedBy
            )
        }
        set {
            // Only what differs is written, so the page does not redraw for nothing.
            if text != newValue.text { text = newValue.text }
            if order != newValue.order { order = newValue.order }
            if createdDate != newValue.created { createdDate = newValue.created }
            if struckDate != newValue.struck { struckDate = newValue.struck }
            if strokeData != newValue.strokes { strokeData = newValue.strokes }
            if struckBy != newValue.struckBy { struckBy = newValue.struckBy }
            if addedBy != newValue.addedBy { addedBy = newValue.addedBy }
            if circledDate != newValue.circled { circledDate = newValue.circled }
            if editedBy != newValue.editedBy { editedBy = newValue.editedBy }
        }
    }
}
