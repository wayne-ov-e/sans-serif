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
    /// Shared or private. Always private until step 11.
    var isShared: Bool = false

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

    var list: TaskList?

    init(text: String, order: Double, list: TaskList) {
        self.text = text
        self.order = order
        self.list = list
    }

    var isLive: Bool { struckDate == nil }
}
