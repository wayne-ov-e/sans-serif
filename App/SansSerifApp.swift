import SwiftData
import SwiftUI

@main
struct SansSerifApp: App {
    private let container: ModelContainer
    #if os(iOS)
    /// Hears an invitation to a shared list being opened.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #elseif os(macOS)
    /// The same on the Mac, where the invitation comes to the app itself.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        do {
            // The UI tests start from an empty store that is thrown away afterwards.
            let isTest = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
            if isTest, let bundleID = Bundle.main.bundleIdentifier {
                // Settings as on a first launch, the first page included.
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
                // Nothing left over in the widgets, and no Live Activity during a test.
                SharedPage.shared.reset()
            }
            LiveView.isAllowed = !isTest
            let arguments = ProcessInfo.processInfo.arguments
            // The iCloud sync line in settings. Struck, the lists stay on this device.
            // It is read once, here: a change takes effect the next time the app opens.
            #if DEBUG
            // A development build talks to iCloud's development side, and the
            // lists on a real device belong to the production side. So it only
            // syncs when asked to, and then with a store of its own.
            let syncs = arguments.contains("-syncInDevelopment")
            let storeName: String? = syncs ? "development" : nil
            #else
            let syncs = UserDefaults.standard.object(forKey: Setting.iCloudSync.key) as? Bool
                ?? Setting.iCloudSync.defaultValue
            let storeName: String? = nil
            #endif
            container = try PageStore.makeContainer(inMemory: isTest, named: storeName)
            let context = container.mainContext
            try PageStore.seedDefaultListsIfNeeded(in: context)
            try context.mergeDuplicateDefaultLists()
            #if DEBUG
            if arguments.contains("-seedSampleData") {
                try PageStore.seedSampleData(in: context)
            }
            #endif
            #if DEBUG
            // iCloud learns a field the first time a record uses it, and only on
            // its development side. This writes one task with every field filled
            // in, so that the layout is whole before it is deployed to production.
            if syncs, arguments.contains("-fillCloudSchema"), let first = try context.lists().first,
               let task = context.addTask("Every field, for iCloud's schema", to: first) {
                task.struckDate = .now
                task.strokeData = Stroke.encode(Stroke.generated(lines: 1, seed: 1))
                task.struckBy = "schema"
                task.addedBy = "schema"
                task.editedBy = "schema"
                task.repeats = "daily"
                task.dueDay = "2026-01-01"
                task.series = "schema"
                task.circledDate = .now
                try context.save()
            }
            #endif
            // The widgets and the Live Activity follow the page from here on.
            PageMirror.shared.start(context: context)
            // And iCloud, for the user's other devices and for shared lists.
            if syncs, !isTest { CloudSync.shared.start(context: context) }
            #if !DEBUG
            // With the iCloud sync line struck, what is changed is noted, to
            // be sent when it is back. Not in a development build, whose
            // synced store is another one.
            if !syncs, !isTest { CloudSync.shared.noteChangesWithoutSync(context: context) }
            #endif
            #if DEBUG
            // Tries the first step of sharing and says in the console how it went.
            // With `-previewShare`, the last list is one someone else shared, to
            // look at the other person's side of sharing without iCloud.
            if arguments.contains("-previewShare"), let joined = try context.lists().last {
                joined.zoneOwner = "_preview"
                joined.isShared = true
                for task in joined.tasks ?? [] { task.addedBy = "Ada" }
            }
            // Many changes a second for half a minute, with iCloud's development
            // side listening: what stopped build 21 at every launch.
            if syncs, arguments.contains("-stressSync"), let first = try context.lists().first {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(4))
                    NSLog("SYNC stress: begins")
                    var made: [TaskItem] = []
                    for round in 0..<240 {
                        if let task = context.addTask("stress \(round)", to: first) { made.append(task) }
                        if round % 3 == 1, let task = made.dropLast().last { context.strike(task) }
                        if round % 5 == 4, made.count > 6 { context.delete(made.removeFirst()) }
                        if round % 7 == 0, let task = made.last { task.text += " edited" }
                        if round % 40 == 0 { NSLog("SYNC stress: round \(round)") }
                        try? await Task.sleep(for: .milliseconds(120))
                    }
                    for task in made { context.delete(task) }
                    try? await Task.sleep(for: .seconds(8))
                    NSLog("SYNC stress: done, running \(CloudSync.shared.isRunning)")
                }
            }
            if syncs, arguments.contains("-tryShare"), let first = try context.lists().first {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(6))
                    do {
                        let share = try await CloudSync.shared.share(for: first)
                        NSLog("SYNC share: made, url \(share.url?.absoluteString ?? "none")")
                    } catch {
                        NSLog("SYNC share: failed \(error)")
                    }
                }
            }
            #endif
        } catch {
            fatalError("Could not open the store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: MacWindow.minSize.width, minHeight: MacWindow.minSize.height)
                #endif
        }
        .modelContainer(container)
        .commands { PageMenuCommands() }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(MacWindow.defaultSize)
        .windowResizability(.contentMinSize)
        #endif
    }
}

#if os(macOS)
/// Window sizes from the brief (Mac specifics) and Figma frame 06 Mac window.
enum MacWindow {
    static let minSize = CGSize(width: 360, height: 480)
    static let defaultSize = CGSize(width: 560, height: 640)
}
#endif
