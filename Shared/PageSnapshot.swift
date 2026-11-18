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
    static let shared = SharedPage(defaults: UserDefaults(suiteName: group) ?? .standard)

    let defaults: UserDefaults

    private static let snapshotKey = "pageSnapshot"
    private static let pendingKey = "pendingChanges"

    var snapshot: PageSnapshot {
        get {
            guard let data = defaults.data(forKey: Self.snapshotKey),
                  let snapshot = try? JSONDecoder().decode(PageSnapshot.self, from: data)
            else { return PageSnapshot() }
            return snapshot
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.snapshotKey)
        }
    }

    var pending: [PendingChange] {
        get {
            guard let data = defaults.data(forKey: Self.pendingKey) else { return [] }
            return (try? JSONDecoder().decode([PendingChange].self, from: data)) ?? []
        }
        nonmutating set {
            defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.pendingKey)
        }
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
        if !changes.isEmpty { defaults.removeObject(forKey: Self.pendingKey) }
        return changes
    }

    func reset() {
        defaults.removeObject(forKey: Self.snapshotKey)
        defaults.removeObject(forKey: Self.pendingKey)
    }
}
