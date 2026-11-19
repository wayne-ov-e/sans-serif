import Foundation
import SwiftData

// The model is small: lists hold tasks, and a task is either live or struck
// (brief: Data model and sync).
//
// Both models already follow CloudKit's rules for SwiftData, so step 10 can
// move storage without a schema change: every property has a default or is
// optional, relationships are optional, and nothing is marked unique.

/// A list named by the user, such as life, work, home.
@Model
final class TaskList {
    var id: UUID = UUID()
    var name: String = ""
    /// Position in the row of list names, ascending.
    var order: Double = 0
    var createdDate: Date = Date.now
    /// Shared with other people, by the user or with the user.
    var isShared: Bool = false
    /// Whose list it is in iCloud. Empty for the user's own lists. For a list
    /// someone else shared, the owner's iCloud name, which is where it is kept.
    var zoneOwner: String?
    /// The link people were invited with, once the list has been shared.
    var shareURL: String?
    /// What iCloud last said about the list's record. See `RecordCoder`.
    var recordData: Data?

    /// Live and struck tasks together. Deleting a list removes its tasks and archive.
    @Relationship(deleteRule: .cascade, inverse: \TaskItem.list)
    var tasks: [TaskItem]? = []

    init(name: String, order: Double) {
        self.name = name
        self.order = order
    }
}

/// One line on the page.
@Model
final class TaskItem {
    var id: UUID = UUID()
    var text: String = ""
    /// Position on the page, ascending.
    var order: Double = 0
    var createdDate: Date = Date.now
    /// Empty while the task is live. Set when it is struck.
    var struckDate: Date?
    /// The pen line, one stroke shape or seed per line of text.
    /// Step 4 (the strike) defines the encoding.
    var strokeData: Data?
    /// Who struck the task, for shared lists.
    var struckBy: String?
    /// Set when the task is circled: the one that matters. Circled tasks come
    /// first in the widgets. Empty when it is not circled.
    var circledDate: Date?
    /// What iCloud last said about the task's record. See `RecordCoder`.
    var recordData: Data?
    /// Who wrote the task, for shared lists. Empty for tasks written before lists could be shared.
    var addedBy: String?

    var list: TaskList?

    init(text: String, order: Double, list: TaskList) {
        self.text = text
        self.order = order
        self.list = list
    }

    var isLive: Bool { struckDate == nil }
    var isCircled: Bool { circledDate != nil }
}
