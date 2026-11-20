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

    /// Twice as many live lines of each list as the largest widget can show.
    /// A widget strikes tasks without the app, so it needs the next ones to
    /// bring up in their place.
    static let linesPerList = 16
    /// A struck line stays where it is showing for this long, struck, then leaves.
    static let linger: TimeInterval = 2.5
    /// A struck line stays in the snapshot for this long, so that a widget
    /// drawn late still has it to show. The system can take seconds to draw a
    /// widget again after a tap, and a line that had already been taken out
    /// by then was never seen struck at all.
    static let keep: TimeInterval = 30

    func list(_ id: UUID?) -> List? {
        lists.first { $0.id == id } ?? lists.first { $0.id == current } ?? lists.first
    }
}

extension PageSnapshot.List {
    /// The list without the lines struck before `date`: they have left for the archive.
    func leaving(struckBefore date: Date) -> PageSnapshot.List {
        var list = self
        list.lines.removeAll { line in
            guard let struck = line.struck else { return false }
            return struck < date
        }
        return list
    }

    /// The list as a widget shows it at `date`, given when each struck line leaves.
    func shown(at date: Date, leaving: [UUID: Date]) -> PageSnapshot.List {
        var list = self
        list.lines.removeAll { line in
            guard line.struck != nil else { return false }
            return (leaving[line.id] ?? .distantPast) <= date
        }
        return list
    }
}

extension PageSnapshot {
    /// The snapshot without the lines struck before `date`.
    func leaving(struckBefore date: Date) -> PageSnapshot {
        var snapshot = self
        snapshot.lists = lists.map { $0.leaving(struckBefore: date) }
        return snapshot
    }

    /// When each struck line leaves the widgets. A line a widget has not drawn
    /// struck yet stays for a moment from `now`, the moment it is drawn, and
    /// not from the moment it was struck: the two can be seconds apart. A line
    /// already given a time keeps it, so drawing again does not bring it back.
    func leaving(known: [UUID: Date], at now: Date) -> [UUID: Date] {
        var leaving: [UUID: Date] = [:]
        for line in lists.flatMap(\.lines) {
            guard let struck = line.struck else { continue }
            if let date = known[line.id] {
                leaving[line.id] = date
            } else if now.timeIntervalSince(struck) < Self.keep {
                leaving[line.id] = now.addingTimeInterval(Self.linger)
            } else {
                leaving[line.id] = .distantPast
            }
        }
        return leaving
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
    private static let leavingKey = "leaving"

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

    /// When each struck line leaves the widgets. The widgets write this as they draw.
    var leaving: [UUID: Date] {
        get {
            guard let data = read(Self.leavingKey) else { return [:] }
            return (try? JSONDecoder().decode([UUID: Date].self, from: data)) ?? [:]
        }
        nonmutating set { write(newValue.isEmpty ? nil : try? JSONEncoder().encode(newValue), Self.leavingKey) }
    }

    /// The lists as the widgets show them from `now`: first as they are, then
    /// once more each time a struck line leaves.
    func timeline(at now: Date = .now) -> (snapshot: PageSnapshot, leaving: [UUID: Date]) {
        let snapshot = snapshot
        let known = leaving
        let leaving = snapshot.leaving(known: known, at: now)
        if leaving != known { self.leaving = leaving }
        return (snapshot, leaving)
    }

    /// A tap on a task outside the app: struck if it was live, live again if
    /// it was struck. The line changes at once where it is showing, and the
    /// app takes the change into its store the next time it runs.
    ///
    /// `expectingLive` is how the line looked where it was tapped. A widget and
    /// the Live Activity are drawn apart, so one may still show a task live
    /// that was struck in the other: a tap there means what it showed, and
    /// changes nothing when that has been done already. It must not undo it.
    @discardableResult
    func toggle(task: UUID, expectingLive: Bool? = nil, at date: Date = .now) -> Bool {
        var snapshot = snapshot
        for list in snapshot.lists.indices {
            guard let line = snapshot.lists[list].lines.firstIndex(where: { $0.id == task }) else { continue }
            let strikes = snapshot.lists[list].lines[line].isLive
            if let expectingLive, expectingLive != strikes { return false }
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
        write(nil, Self.leavingKey)
    }
}
