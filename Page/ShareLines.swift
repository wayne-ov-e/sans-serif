import CloudKit
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Sharing a list, as lines of text at the top of the page, where settings
/// stand: who is on the list, a link to send, and the way to stop or to leave.
/// The page waits below it, as it does below settings.
///
/// The link is the invitation: anyone who is given it can join, and read and
/// write the list. A person on the list is struck off it with a tap.
struct ShareLines: View {
    let list: TaskList
    /// Leaving a list someone else shared: the page asks first, as for deleting a list.
    var leave: () -> Void = {}

    @Environment(\.pageMetrics) private var metrics

    private enum Load: Equatable {
        case asking
        /// What iCloud says. No link and nobody: the list is not shared yet.
        case known(link: URL?, people: [SharePerson])
        case failed(String)
    }

    @State private var load = Load.asking
    /// Something is on its way to iCloud. The lines wait.
    @State private var isBusy = false
    @State private var isConfirmingStop = false
    @State private var copied = false
    /// People struck off and not yet gone from what iCloud says.
    @State private var struck: Set<String> = []
    @State private var changes = 0
    /// Counts the times the user has changed their name here.
    @State private var names = 0

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsGap) {
            Text(list.isSomeoneElses ? "Shared with you" : "Share \(list.name)")
                .typeStyle(.monthLabel)
                .foregroundStyle(.inkFaded)
                .accessibilityAddTraits(.isHeader)

            switch load {
            case .asking:
                note("Asking iCloud")
            case .failed(let words):
                note(words)
                word("Try again") { Task { await ask() } }
            case .known(let link, let people):
                if let link {
                    shared(link: link, people: people)
                } else {
                    // Before there is a link, one thing to do and nothing else
                    // (Wayne, Nov 19, 2026). The name and the rest come with the link.
                    word("Make a link") { Task { await makeLink() } }
                }
            }
        }
        .opacity(isBusy ? 0.5 : 1)
        .allowsHitTesting(!isBusy)
        .animation(.quick, value: isBusy)
        .animation(.quick, value: load)
        .animation(.quick, value: isConfirmingStop)
        .haptic(.pen, trigger: changes)
        .task(id: list.id) { await ask() }
        // The user's own line reads as they have just named themselves.
        .onChange(of: names) { _, _ in
            guard case .known(let link, var people) = load, let me = people.firstIndex(where: \.isMe),
                  let name = CloudSync.shared.myName, !name.isEmpty
            else { return }
            people[me].name = name
            load = .known(link: link, people: people)
        }
        .environment(\.nameChanged) { names += 1 }
    }

    // MARK: Lines

    @ViewBuilder private func shared(link: URL, people: [SharePerson]) -> some View {
        NameLine()
        ForEach(people) { person in
            PersonLine(
                person: person,
                isStruck: struck.contains(person.id),
                // Only the owner takes people off, and never themselves.
                strike: list.isSomeoneElses || person.isOwner || person.isMe ? nil : { remove(person) }
            )
        }
        if !list.isSomeoneElses {
            if people.count < 2 { note("Anyone with the link can join and write.") }
            ShareLink(item: link, subject: Text(list.name), message: Text("Join my list, \(list.name)")) {
                line("Send link")
            }
            .buttonStyle(.plain)
            word(copied ? "Copied" : "Copy link") { copy(link) }
            if isConfirmingStop {
                word("Yes, stop sharing", isDestructive: true) { Task { await stop() } }
                word("Keep sharing") { isConfirmingStop = false }
            } else {
                word("Stop sharing", isDestructive: true) { isConfirmingStop = true }
            }
        } else {
            word("Leave list", isDestructive: true, action: leave)
        }
    }

    private func note(_ words: String) -> some View {
        Text(words)
            .typeStyle(.listName)
            .foregroundStyle(.inkFaded)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func line(_ words: String, isDestructive: Bool = false) -> some View {
        Text(words)
            .typeStyle(.task)
            .foregroundStyle(isDestructive ? .inkRed : .ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }

    /// A line that does something when it is tapped, like Gestures in settings.
    private func word(_ words: String, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { line(words, isDestructive: isDestructive) }
            .buttonStyle(.plain)
    }

    // MARK: iCloud

    #if DEBUG
    /// With `-previewShare`, a list shared with two people, to look at the
    /// lines without iCloud.
    static let isPreview = ProcessInfo.processInfo.arguments.contains("-previewShare")
    private static let previewPeople = [
        SharePerson(id: "me", name: "Wayne Xu", isOwner: true, isMe: true, isWaiting: false),
        SharePerson(id: "ada", name: "Ada Lovelace", isOwner: false, isMe: false, isWaiting: false),
        SharePerson(id: "ben", name: "ben@example.com", isOwner: false, isMe: false, isWaiting: true),
    ]
    #endif

    private func ask() async {
        #if DEBUG
        if Self.isPreview {
            load = list.isShared
                ? .known(link: URL(string: "https://www.icloud.com/share/preview"), people: Self.previewPeople)
                : .known(link: nil, people: [])
            return
        }
        #endif
        guard CloudSync.shared.isRunning else {
            load = .failed("Turn on iCloud sync to share.")
            return
        }
        // Not shared, as far as this device knows: nothing to ask iCloud yet.
        guard list.isShared || list.isSomeoneElses else {
            load = .known(link: nil, people: [])
            return
        }
        if case .failed = load { load = .asking }
        await reach { try await CloudSync.shared.currentShare(for: list) }
    }

    private func makeLink() async {
        #if DEBUG
        if Self.isPreview {
            list.isShared = true
            await ask()
            return
        }
        #endif
        await reach { try await CloudSync.shared.share(for: list) }
    }

    private func remove(_ person: SharePerson) {
        struck.insert(person.id)
        changes += 1
        Task {
            // The pen line is seen before the name leaves.
            try? await Task.sleep(for: .seconds(0.6))
            await reach { try await CloudSync.shared.remove(person, from: list) }
            struck.remove(person.id)
        }
    }

    private func stop() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await CloudSync.shared.stopSharing(list)
            isConfirmingStop = false
            changes += 1
            load = .known(link: nil, people: [])
        } catch {
            load = .failed(Self.words(for: error))
        }
    }

    /// Asks iCloud for the share, in one way or another, and shows what comes back.
    private func reach(_ share: () async throws -> CKShare?) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let share = try await share()
            load = .known(
                link: share?.url,
                people: share.map { SharePerson.people(on: $0, myName: CloudSync.shared.myName) } ?? []
            )
        } catch {
            load = .failed(Self.words(for: error))
        }
    }

    /// With iCloud's own number for what went wrong, so it can be told apart.
    static func words(for error: any Error) -> String {
        guard let error = error as? CKError else { return "Could not reach iCloud just now." }
        switch error.code {
        case .networkUnavailable, .networkFailure: return "No connection. Try again in a moment."
        case .notAuthenticated: return "Sign in to iCloud in Settings to share."
        case .quotaExceeded: return "iCloud is full."
        default: return "Could not share just now (\(error.code.rawValue))."
        }
    }

    private func copy(_ link: URL) {
        #if os(iOS)
        UIPasteboard.general.url = link
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.absoluteString, forType: .string)
        #endif
        changes += 1
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

private struct NameChangedKey: EnvironmentKey {
    static let defaultValue: @MainActor () -> Void = {}
}

private extension EnvironmentValues {
    var nameChanged: @MainActor () -> Void {
        get { self[NameChangedKey.self] }
        set { self[NameChangedKey.self] = newValue }
    }
}

/// The name the user goes by on shared lists: "you are Wayne". It stands by
/// the tasks they write and strike. A tap on it and it is typed where it
/// stands. iCloud's name for them is there to begin with, when it gives one.
private struct NameLine: View {
    @Environment(\.nameChanged) private var nameChanged
    @State private var name = CloudSync.shared.myName ?? ""
    @State private var isTyping = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("you are").foregroundStyle(.inkFaded)
            if isTyping {
                TextField("", text: $draft, prompt: Text("your name").foregroundStyle(.inkFaded))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.ink)
                    .tint(.ink)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    .textContentType(.name)
                    .submitLabel(.done)
                    #endif
                    .autocorrectionDisabled()
                    .padding(.vertical, 6)
                    .focused($isFocused)
                    .onSubmit(keep)
                    .onChange(of: isFocused) { _, focused in if !focused { keep() } }
                    // "done", above the keys.
                    .onChange(of: HourEntry.shared.dones) { _, _ in keep() }
                    .onDisappear { HourEntry.shared.isWritingElsewhere = false }
                    .accessibilityLabel("Your name")
            } else {
                Text(name.isEmpty ? "add your name" : name)
                    .foregroundStyle(name.isEmpty ? .inkFaded : .ink)
                    .lineLimit(1)
                    // Pencil dots under a word that can be changed, as in settings.
                    .underline(pattern: .dot, color: .inkFaded)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle().inset(by: -6))
                    .onTapGesture {
                        draft = name
                        HourEntry.shared.isWritingElsewhere = true
                        isTyping = true
                        isFocused = true
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Your name")
                    .accessibilityValue(name.isEmpty ? "Not set" : name)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Tap to write the name others see by your tasks")
            }
        }
        .typeStyle(.listName)
        .frame(maxWidth: .infinity, alignment: .leading)
        // iCloud may give a name a moment after the lines appear.
        .task {
            try? await Task.sleep(for: .seconds(1.5))
            if !isTyping, name.isEmpty { name = CloudSync.shared.myName ?? "" }
        }
    }

    private func keep() {
        guard isTyping else { return }
        isTyping = false
        isFocused = false
        HourEntry.shared.isWritingElsewhere = false
        CloudSync.shared.setName(draft)
        name = CloudSync.shared.myName ?? ""
        nameChanged()
    }
}

/// One person on the list. Struck, they are being taken off it.
private struct PersonLine: View {
    let person: SharePerson
    let isStruck: Bool
    /// Takes the person off the list. Nothing for people who cannot be taken off.
    let strike: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress = 0.0

    private var stroke: Stroke {
        // The same pen line for the same person every time.
        Stroke.generated(seed: person.id.utf8.reduce(UInt64(0xcbf2_9ce4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 })
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(person.name)
                .typeStyle(.task)
                .foregroundStyle(isStruck ? .inkFaded : .ink)
                .lineLimit(1)
                .overlayPreferenceValue(Text.LayoutKey.self) { layouts in
                    GeometryReader { proxy in
                        StrikeMarks(lines: StrikeLine.measure(layouts, in: proxy), strokes: [stroke], progress: progress)
                    }
                }
            if let note = person.note {
                Text(note)
                    .typeStyle(.monthLabel)
                    .foregroundStyle(.inkFaded)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if !isStruck { strike?() } }
        .onChange(of: isStruck, initial: true) { _, struck in
            if reduceMotion {
                progress = struck ? 1 : 0
            } else {
                withAnimation(.linear(duration: TaskLine.secondsPerLine)) { progress = struck ? 1 : 0 }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(person.name)
        .accessibilityValue(person.note ?? "")
        .accessibilityAddTraits(strike == nil ? [] : .isButton)
        .accessibilityHint(strike == nil ? "" : "Takes them off the list")
        .accessibilityAction { if !isStruck { strike?() } }
    }
}
