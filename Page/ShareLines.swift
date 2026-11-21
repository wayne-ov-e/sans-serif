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
    /// The share itself, as iCloud last gave it: what "Send link" hands over.
    @State private var share: CKShare?
    /// Something is on its way to iCloud. The lines wait.
    @State private var isBusy = false
    @State private var isConfirmingStop = false
    @State private var copied = false
    /// The person the owner has tapped, and is being asked about.
    @State private var asking: SharePerson?
    /// People struck off and not yet gone from what iCloud says.
    @State private var struck: Set<String> = []
    @State private var changes = 0
    /// Counts the times the user has changed their name here.
    @State private var names = 0
    /// What iCloud calls the user: the name they have until they write another.
    @State private var iCloudName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.settingsGap) {
            // No heading: the lines say what they are for, and less is better
            // (Wayne, Nov 19, 2026).
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
                    // Before there is a link: the user's own line, and one thing to do.
                    OwnLine(fallback: iCloudName, note: "you")
                    word("Make a link") { Task { await makeLink() } }
                }
            }
        }
        .opacity(isBusy ? 0.5 : 1)
        .allowsHitTesting(!isBusy)
        .animation(.quick, value: isBusy)
        .animation(.quick, value: load)
        .animation(.quick, value: isConfirmingStop)
        .animation(.quick, value: asking)
        .animation(.quick, value: iCloudName)
        .haptic(.pen, trigger: changes)
        .task(id: list.id) { await ask() }
        // The user's own line reads as they have just named themselves.
        .onChange(of: names) { _, _ in
            noteICloudName()
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
        // The user's own line is where their name is changed: no line apart
        // for it (Wayne, Nov 19, 2026).
        if !people.contains(where: \.isMe) { OwnLine(fallback: iCloudName, note: "you") }
        ForEach(people) { person in
            if person.isMe {
                OwnLine(fallback: person.name, note: person.note)
            } else {
            PersonLine(
                person: person,
                isStruck: struck.contains(person.id),
                // Only the owner takes people off, and never themselves. A tap
                // asks first: taking someone off is not done by a slip of the finger.
                strike: list.isSomeoneElses || person.isOwner || person.isMe ? nil : {
                    asking = asking == person ? nil : person
                }
            )
            if asking == person {
                HStack(alignment: .firstTextBaseline, spacing: metrics.listNameGap) {
                    Button { asking = nil; remove(person) } label: {
                        Text("Yes, remove").foregroundStyle(.inkRed)
                    }
                    Button { asking = nil } label: {
                        Text("Keep").foregroundStyle(.ink)
                    }
                }
                .buttonStyle(.plain)
                .typeStyle(.action)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
            }
            }
        }
        if !list.isSomeoneElses {
            if people.count < 2 { note("Anyone with the link can join and write.") }
            // The share itself is sent, not its bare link. Given only a link,
            // Messages looked the address up and drew iCloud's logo (Wayne,
            // Nov 21, 2026); given the share, it draws the list's name and the
            // card that `CloudSync.dress` put on it. The price is Apple's
            // "Collaborate" line at the top of the share sheet.
            Group {
                if let share {
                    ShareLink(
                        item: ListInvite(share: share, link: link), subject: Text(list.name),
                        message: Text("Join my list, \(list.name)"),
                        preview: SharePreview(list.name, image: ShareCard.image(named: list.name))
                    ) {
                        line("Send link")
                    }
                } else {
                    ShareLink(
                        item: link, subject: Text(list.name), message: Text("Join my list, \(list.name)"),
                        preview: SharePreview(list.name, image: ShareCard.image(named: list.name))
                    ) {
                        line("Send link")
                    }
                }
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

    #if DEBUG
    /// The same list as the person it was shared with sees it.
    private static let previewJoined = [
        SharePerson(id: "ada", name: "Ada Lovelace", isOwner: true, isMe: false, isWaiting: false),
        SharePerson(id: "me", name: "Wayne Xu", isOwner: false, isMe: true, isWaiting: false),
        SharePerson(id: "ben", name: "ben@example.com", isOwner: false, isMe: false, isWaiting: true),
    ]
    #endif

    private func ask() async {
        #if DEBUG
        if Self.isPreview {
            iCloudName = "Wayne Xu"
            let link = URL(string: "https://www.icloud.com/share/preview")
            if list.isSomeoneElses {
                load = .known(link: link, people: Self.previewJoined)
            } else {
                load = list.isShared ? .known(link: link, people: Self.previewPeople) : .known(link: nil, people: [])
            }
            return
        }
        #endif
        guard CloudSync.shared.isRunning else {
            load = .failed("Turn on iCloud sync to share.")
            return
        }
        // Not shared, as far as this device knows: nothing to ask iCloud yet,
        // but what it calls the user.
        guard list.isShared || list.isSomeoneElses else {
            noteICloudName()
            load = .known(link: nil, people: [])
            if iCloudName.isEmpty {
                await CloudSync.shared.learnName()
                noteICloudName()
            }
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
        #if DEBUG
        if Self.isPreview {
            Task {
                try? await Task.sleep(for: .seconds(0.8))
                if case .known(let link, let people) = load {
                    load = .known(link: link, people: people.filter { $0.id != person.id })
                }
                struck.remove(person.id)
            }
            return
        }
        #endif
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
            noteICloudName()
            load = .known(link: nil, people: [])
        } catch {
            load = .failed(Self.words(for: error))
        }
    }

    /// What the user's own line reads until they write a name: iCloud's.
    private func noteICloudName() {
        #if DEBUG
        if Self.isPreview { return }
        #endif
        iCloudName = CloudSync.shared.nameIsTyped ? "" : CloudSync.shared.myName ?? ""
    }

    /// Asks iCloud for the share, in one way or another, and shows what comes back.
    private func reach(_ share: () async throws -> CKShare?) async {
        isBusy = true
        defer { isBusy = false }
        do {
            let share = try await share()
            self.share = share
            load = .known(
                link: share?.url,
                people: share.map { SharePerson.people(on: $0, myName: CloudSync.shared.myName) } ?? []
            )
        } catch {
            load = .failed(Self.words(for: error))
        }
        noteICloudName()
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

/// The user's own line among the people on a list, and before there are any.
/// It is where they say what they go by: a tap on the name and it is typed
/// where it stands. The name stands by the tasks they write and strike.
/// iCloud's name for them is there to begin with, when it gives one.
private struct OwnLine: View {
    /// What iCloud calls the user, shown until they write a name of their own.
    let fallback: String
    /// What stands after the name: "you", or "you, owner".
    let note: String?

    @Environment(\.nameChanged) private var nameChanged
    @State private var typed = CloudSync.shared.nameIsTyped ? CloudSync.shared.myName ?? "" : ""
    @State private var isTyping = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private var name: String { typed.isEmpty ? fallback : typed }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if isTyping {
                TextField("", text: $draft, prompt: Text("your name").foregroundStyle(.inkFaded))
                    .textFieldStyle(.plain)
                    .typeStyle(.task)
                    .foregroundStyle(.ink)
                    .tint(.ink)
                    #if os(iOS)
                    .textInputAutocapitalization(.words)
                    .textContentType(.name)
                    .submitLabel(.done)
                    #endif
                    .autocorrectionDisabled()
                    .fixedSize()
                    .focused($isFocused)
                    .onSubmit(keep)
                    .onChange(of: isFocused) { _, focused in if !focused { keep() } }
                    // "done", above the keys.
                    .onChange(of: HourEntry.shared.dones) { _, _ in keep() }
                    .onDisappear { HourEntry.shared.isWritingElsewhere = false }
                    .accessibilityLabel("Your name")
            } else {
                Text(name.isEmpty ? "add your name" : name)
                    .typeStyle(.task)
                    .foregroundStyle(name.isEmpty ? .inkFaded : .ink)
                    .lineLimit(1)
                    // Pencil dots under a word that can be changed, as in settings.
                    .underline(pattern: .dot, color: .inkFaded)
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
            if let note {
                Text(note)
                    .typeStyle(.monthLabel)
                    .foregroundStyle(.inkFaded)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func keep() {
        guard isTyping else { return }
        isTyping = false
        isFocused = false
        HourEntry.shared.isWritingElsewhere = false
        // Left as it stood, nothing was written, and nothing changes: not the
        // name the user typed before, and not iCloud's name for them.
        let written = CloudSync.tidied(draft)
        guard written != name else { return }
        CloudSync.shared.setName(written)
        typed = CloudSync.shared.nameIsTyped ? CloudSync.shared.myName ?? "" : ""
        nameChanged()
        // Emptied: iCloud's name is asked for again and used.
        if written.isEmpty {
            Task { @MainActor in
                await CloudSync.shared.learnName()
                nameChanged()
            }
        }
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

/// A shared list as it is handed to the share sheet: the share for what can
/// show an invitation as one, as Messages does, and the plain link for the rest.
struct ListInvite: Transferable {
    let share: CKShare
    let link: URL

    static var transferRepresentation: some TransferRepresentation {
        CKShareTransferRepresentation { invite in
            // The link is the invitation: anyone given it may join and write.
            // Nothing else is offered, so the sheet has no choices to show.
            .existing(
                invite.share, container: CKContainer(identifier: PageStore.cloudContainer),
                allowedSharingOptions: CKAllowedSharingOptions(
                    allowedParticipantPermissionOptions: .readWrite,
                    allowedParticipantAccessOptions: .anyoneWithLink
                )
            )
        }
        ProxyRepresentation(exporting: \.link)
    }
}
