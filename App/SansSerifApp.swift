import SwiftData
import SwiftUI

@main
struct SansSerifApp: App {
    private let container: ModelContainer

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
            WorkHoursActivity.isAllowed = !isTest
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-initCloudKitSchema") || arguments.contains("-printCloudKitSchema") {
                do {
                    try PageStore.initializeCloudKitSchema(printOnly: arguments.contains("-printCloudKitSchema"))
                    print("CloudKit schema initialised for \(PageStore.cloudContainer)")
                } catch {
                    print("CloudKit schema could not be initialised: \(error)")
                }
            }
            #endif
            // The iCloud sync line in settings. Struck, the lists stay on this device.
            // It is read once, here: a change takes effect the next time the app opens.
            let syncs = UserDefaults.standard.object(forKey: Setting.iCloudSync.key) as? Bool
                ?? Setting.iCloudSync.defaultValue
            container = try PageStore.makeContainer(inMemory: isTest, syncs: syncs)
            let context = container.mainContext
            try PageStore.seedDefaultListsIfNeeded(in: context)
            try context.mergeDuplicateDefaultLists()
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-seedSampleData") {
                try PageStore.seedSampleData(in: context)
            }
            #endif
            // The widgets and the Live Activity follow the page from here on.
            PageMirror.shared.start(context: context)
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
