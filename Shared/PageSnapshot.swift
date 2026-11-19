import Foundation

/// What the widgets and the Live Activity know of the page: each list, and the
/// first few lines of it. The app writes it after every change. A widget
/// cannot open the app's store, so this is all it reads.
struct PageSnapshot: Codable, Equatable, Sendable {
    struct Line: Codable, Hashable, Sendable, Identifiable {
        var id: UUID
        var text: String
        /// Struck from a widget or the Live Activity, and still showing there.
        var struck: Date?

        var isLive: Bool { struck == nil }
    }

    struct List: Codable, Hashable, Sendable, Identifiable {
        var id: UUID
        var name: String
        /// The first lines of the page, in page order.
        var lines: [Line]
        /// How many tasks are live, the ones not shown included.
        var left: Int

        /// Lines to show in a place with room for `count`.
        func lines(_ count: Int) -> [Line] { Array(lines.prefix(count)) }
        var next: Line? { lines.first(where: \.isLive) }
    }

    var lists: [List] = []
    /// The list last open in the app.
    var current: UUID?

    /// As many lines of each list as the largest widget can show.
    static let linesPerList = 8

    func list(_ id: UUID?) -> List? {
        lists.first { $0.id == id } ?? lists.first { $0.id == current } ?? lists.first
    }
}

/// A strike, or a strike undone, made outside the app and not yet in its store.
struct PendingChange: Codable, Equatable, Sendable {
    var task: UUID
    var struck: Bool
    var date: Date
}

/// Where the app, its widgets and the Live Activity meet: a small shared
/// drawer in the app group. The app's own store stays where it is.
struct SharedPage: @unchecked Sendable {
    static let group = "group.app.sans-serif"
    static let shared = SharedPage(
        defaults: UserDefaults(suiteName: group) ?? .standard,
        directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
    )

    let defaults: UserDefaults
    /// The app group's folder. What is kept there is read from the file every
    /// time, so the widget sees at once what the app has just written. Settings
    /// shared between two processes can be a moment behind. Without a folder,
    /// as in the tests, the settings are used.
    var directory: URL?

    private static let snapshotKey = "pageSnapshot"
    private static let pendingKey = "pendingChanges"

    private func read(_ key: String) -> Data? {
        guard let directory else { return defaults.data(forKey: key) }
        return try? Data(contentsOf: directory.appending(path: "\(key).json"))
    }

    private func write(_ data: Data?, _ key: String) {
        guard let directory else {
            defaults.set(data, forKey: key)
            return
        }
        let file = directory.appending(path: "\(key).json")
        if let data {
            try? data.write(to: file, options: .atomic)
        } else {
            try? FileManager.default.removeItem(at: file)
        }
    }

    var snapshot: PageSnapshot {
        get {
            guard let data = read(Self.snapshotKey),
                  let snapshot = try? JSONDecoder().decode(PageSnapshot.self, from: data)
            else { return PageSnapshot() }
            return snapshot
        }
        nonmutating set { write(try? JSONEncoder().encode(newValue), Self.snapshotKey) }
    }

    var pending: [PendingChange] {
        get {
            guard let data = read(Self.pendingKey) else { return [] }
            return (try? JSONDecoder().decode([PendingChange].self, from: data)) ?? []
        }
        nonmutating set { write(try? JSONEncoder().encode(newValue), Self.pendingKey) }
    }

    /// A tap on a task outside the app: struck if it was live, live again if
    /// it was struck. The line changes at once where it is showing, and the
    /// app takes the change into its store the next time it runs.
    @discardableResult
    func toggle(task: UUID, at date: Date = .now) -> Bool {
        var snapshot = snapshot
        for list in snapshot.lists.indices {
            guard let line = snapshot.lists[list].lines.firstIndex(where: { $0.id == task }) else { continue }
            let strikes = snapshot.lists[list].lines[line].isLive
            snapshot.lists[list].lines[line].struck = strikes ? date : nil
            snapshot.lists[list].left += strikes ? -1 : 1
            self.snapshot = snapshot
            pending += [PendingChange(task: task, struck: strikes, date: date)]
            return true
        }
        return false
    }

    /// Hands over what was done outside the app, and forgets it.
    func takePending() -> [PendingChange] {
        let changes = pending
        if !changes.isEmpty { write(nil, Self.pendingKey) }
        return changes
    }

    func reset() {
        write(nil, Self.snapshotKey)
        write(nil, Self.pendingKey)
    }
}
