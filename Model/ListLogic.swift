import CoreData
import Foundation
import SwiftData

// MARK: - Reading a list

extension TaskList {
    /// Tasks on the page, in page order.
    var liveTasks: [TaskItem] {
        (tasks ?? []).filter(\.isLive).sorted { $0.order < $1.order }
    }

    /// The count beside the list name: tasks left.
    var liveCount: Int {
        (tasks ?? []).count(where: \.isLive)
    }

    /// The archive is a query: tasks with a struck date, grouped by month, newest first.
    func archive(calendar: Calendar = .current) -> [ArchiveMonth] {
        let struck = (tasks ?? []).compactMap { task in
            task.struckDate.map { (task: task, date: $0) }
        }
        let byMonth = Dictionary(grouping: struck) { entry in
            calendar.dateInterval(of: .month, for: entry.date)?.start ?? entry.date
        }
        return byMonth
            .map { month, entries in
                ArchiveMonth(
                    month: month,
                    tasks: entries.sorted { $0.date > $1.date }.map(\.task)
                )
            }
            .sorted { $0.month > $1.month }
    }
}

/// One month of the archive.
struct ArchiveMonth: Identifiable {
    /// The first moment of the month.
    let month: Date
    /// Struck tasks, most recently struck first.
    let tasks: [TaskItem]

    var id: Date { month }
}

// MARK: - Changing lists and tasks
//
// Deleting uses SwiftData's own `delete(_:)`. Deleting a task leaves no trace in
// the archive; deleting a list cascades to its tasks and its archive.

extension ModelContext {
    /// Every list, in the order of the list names.
    func lists() throws -> [TaskList] {
        try fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.order)]))
    }

    /// Adds a list after the last one. Returns `nil` if the name is blank.
    @discardableResult
    func addList(named name: String) throws -> TaskList? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let last = try lists().last?.order ?? -1
        let list = TaskList(name: name, order: last + 1)
        insert(list)
        return list
    }

    /// Renames a list. A blank name is ignored.
    func rename(_ list: TaskList, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        list.name = name
    }

    /// Adds a task below the last one. Returns `nil` if the text is blank.
    @discardableResult
    func addTask(_ text: String, to list: TaskList) -> TaskItem? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let task = TaskItem(text: text, order: nextOrder(in: list), list: list)
        insert(task)
        return task
    }

    /// Strikes a live task. The one-second hold before it leaves the page is the view's job.
    func strike(_ task: TaskItem, strokeData: Data? = nil, by person: String? = nil, at date: Date = .now) {
        guard task.isLive else { return }
        task.struckDate = date
        task.strokeData = strokeData
        task.struckBy = person
    }

    /// Undoes a strike, or restores a task from the archive. It keeps its place on the page.
    func restore(_ task: TaskItem) {
        task.struckDate = nil
        task.strokeData = nil
        task.struckBy = nil
    }

    /// Moves a task to the bottom of another list.
    func move(_ task: TaskItem, to list: TaskList) {
        guard task.list !== list else { return }
        task.order = nextOrder(in: list)
        task.list = list
    }

    /// Puts a task between two others on the page. Pass `nil` for the top or the bottom.
    func place(_ task: TaskItem, below upper: TaskItem?, above lower: TaskItem?) {
        switch (upper?.order, lower?.order) {
        case let (upper?, lower?) where lower - upper > 1e-6:
            task.order = (upper + lower) / 2
        case (_?, _?):
            // No room left between the two. Number the whole list afresh.
            var tasks = (task.list?.tasks ?? []).filter { $0 !== task }.sorted { $0.order < $1.order }
            let index = tasks.firstIndex { $0 === lower } ?? tasks.endIndex
            tasks.insert(task, at: index)
            for (position, each) in tasks.enumerated() { each.order = Double(position) }
        case let (upper?, nil):
            task.order = upper + 1
        case let (nil, lower?):
            task.order = lower - 1
        case (nil, nil):
            break
        }
    }

    /// The first page is over (brief: First run). The task the user wrote goes
    /// to the list as a live task. The instruction lines they crossed off go to
    /// its archive, when there are any to keep.
    func finishGuide(ownTask: String?, struckLines: [String], in list: TaskList, at date: Date = .now) {
        if let ownTask { addTask(ownTask, to: list) }
        for line in struckLines {
            if let task = addTask(line, to: list) { strike(task, at: date) }
        }
    }

    /// Each device makes life, work and home on its first launch, before it has
    /// heard from iCloud. Once the devices meet there are two of each. This
    /// folds every later copy of a first list into the earliest one: its tasks
    /// and its archive move over, and the copy is removed. Lists the user named
    /// themselves are never merged.
    ///
    /// - Returns: how many copies were removed.
    @discardableResult
    func mergeDuplicateDefaultLists() throws -> Int {
        var removed = 0
        let all = try lists()
        for name in PageStore.defaultListNames {
            let copies = all.filter { $0.name == name }.sorted {
                ($0.createdDate, $0.id.uuidString) < ($1.createdDate, $1.id.uuidString)
            }
            guard let keeper = copies.first, copies.count > 1 else { continue }
            for copy in copies.dropFirst() {
                // Below what the keeper already has, in their own order.
                var order = nextOrder(in: keeper)
                for task in (copy.tasks ?? []).sorted(by: { $0.order < $1.order }) {
                    task.order = order
                    task.list = keeper
                    order += 1
                }
                delete(copy)
                removed += 1
            }
        }
        if removed > 0 { try save() }
        return removed
    }

    private func nextOrder(in list: TaskList) -> Double {
        ((list.tasks ?? []).map(\.order).max() ?? -1) + 1
    }
}

// MARK: - The store

enum PageStore {
    /// The user's first lists (brief: First run). They can be renamed.
    static let defaultListNames = ["life", "work", "home"]

    /// The iCloud container the lists sync through (brief: Data model and sync).
    static let cloudContainer = "iCloud.app.sans-serif"

    /// Lists and tasks, stored on the device. With `syncs`, they also go to the
    /// user's private iCloud database and follow them to their other devices.
    ///
    /// If the store cannot be opened with iCloud, for any reason, it is opened
    /// without: the lists are always there, and sync is the part that waits.
    static func makeContainer(inMemory: Bool = false, syncs: Bool = false) throws -> ModelContainer {
        let local = ModelConfiguration(isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        guard syncs, !inMemory else {
            return try ModelContainer(for: TaskList.self, TaskItem.self, configurations: local)
        }
        let synced = ModelConfiguration(cloudKitDatabase: .private(cloudContainer))
        do {
            return try ModelContainer(for: TaskList.self, TaskItem.self, configurations: synced)
        } catch {
            return try ModelContainer(for: TaskList.self, TaskItem.self, configurations: local)
        }
    }

    #if DEBUG
    /// Tells iCloud's development side every record type and field the lists
    /// use, the empty ones included, so the layout can then be deployed to
    /// production in the CloudKit Console. Run once, from a development build
    /// on a device signed in to iCloud, with the launch argument
    /// `-initCloudKitSchema`. This is the way Apple's SwiftData documentation
    /// gives for it: SwiftData has no call of its own, so Core Data is asked.
    ///
    /// With `printOnly`, nothing is sent: the records that would be created are
    /// printed, which works without an iCloud account.
    static func initializeCloudKitSchema(printOnly: Bool = false) throws {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: [TaskList.self, TaskItem.self]) else {
            return
        }
        let url = URL.temporaryDirectory.appending(path: "schema-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudContainer)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "Schema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        try container.initializeCloudKitSchema(options: printOnly ? [.dryRun, .printSchema] : [])
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }
    }
    #endif

    /// Creates life, work and home when the store has no lists at all.
    static func seedDefaultListsIfNeeded(in context: ModelContext) throws {
        guard try context.fetchCount(FetchDescriptor<TaskList>()) == 0 else { return }
        for name in defaultListNames {
            try context.addList(named: name)
        }
        try context.save()
    }

    #if DEBUG
    /// The lists from the Figma frames, for checking layout before tasks can be typed.
    /// Runs only when the app is launched with `-seedSampleData` and every list is empty.
    static func seedSampleData(in context: ModelContext) throws {
        let lists = try context.lists()
        guard lists.allSatisfy({ ($0.tasks ?? []).isEmpty }) else { return }
        let samples = [
            "life": ["Call the framer", "Renew passport", "Water the fig tree",
                     "Book dinner for Friday", "Return library books", "Write to Grandma"],
            "work": ["Send the wholesale quote", "Review the packaging proof", "Order green coffee samples"],
            "home": ["Fix the hallway light"],
        ]
        for list in lists {
            for text in samples[list.name] ?? [] {
                context.addTask(text, to: list)
            }
        }
        // An archive for the first list: this month open, three months folded.
        if let first = lists.first {
            let struck: [(String, Int)] = [
                ("Book dinner for the weekend", 0), ("Pick up dry cleaning", 0), ("Fix the bike tyre", 0),
                ("Send birthday card", -1), ("Clean the gutters", -1), ("Buy stamps", -2), ("Renew the library card", -3),
            ]
            for (index, (text, monthsAgo)) in struck.enumerated() {
                guard let task = context.addTask(text, to: first),
                      let month = Calendar.current.date(byAdding: .month, value: monthsAgo, to: .now)
                else { continue }
                let when = monthsAgo == 0 ? Date.now.addingTimeInterval(Double(-index) * 60) : month
                let seed = UInt64(index + 1) &* 0x9E37_79B9_7F4A_7C15
                context.strike(task, strokeData: Stroke.encode(Stroke.generated(lines: 1, seed: seed)), at: when)
            }
        }
        try context.save()
    }
    #endif
}

extension Array where Element == TaskList {
    /// The list a number of places after this one in the row of names, or
    /// before it for a negative step. `nil` past either end: the row does not wrap.
    func neighbour(of list: TaskList, by step: Int) -> TaskList? {
        guard let index = firstIndex(where: { $0 === list }) else { return nil }
        let target = index + step
        return indices.contains(target) ? self[target] : nil
    }
}
