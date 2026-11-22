import CoreData
import SwiftData
import SwiftUI

struct ContentView: View {
    @Query(sort: TaskList.rowOrder) private var lists: [TaskList]

    /// The list this window is showing. Each window remembers its own.
    @SceneStorage("currentList") private var currentID: String?
    @Environment(\.modelContext) private var context
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Setting.guideDone.key) private var guideDone = Setting.guideDone.defaultValue
    @AppStorage(Setting.guideReplay.key) private var guideReplay = Setting.guideReplay.defaultValue

    /// With Dark paper on, the paper is dark whenever the system is. Struck, it stays light.
    @AppStorage(Setting.darkPaper.key) private var darkPaper = Setting.darkPaper.defaultValue

    /// The list shown as a Live Activity, if one is.
    @AppStorage(LiveView.listKey) private var liveList = ""
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
    #endif

    var body: some View {
        page
            .preferredColorScheme(darkPaper ? nil : .light)
            // Lists arriving from another device can bring a second life, work and home.
            // The notice comes on a thread of its own, so it is taken on the main one.
            .onReceive(
                NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange).receive(on: RunLoop.main)
            ) { _ in
                try? context.mergeDuplicateDefaultLists()
            }
            // The widgets and the Live Activity show the list that is open, and
            // catch up whenever the app comes forward or steps back.
            .onChange(of: shownID, initial: true) { _, new in PageMirror.shared.current = new }
            .onChange(of: scenePhase) { _, _ in
                try? context.save()
                PageMirror.shared.refresh()
                CloudSync.shared.catchUp()
            }
            // While the app is open it keeps asking iCloud for what others have written.
            .onChange(of: scenePhase, initial: true) { _, phase in CloudSync.shared.watch(phase == .active) }
            .onChange(of: liveList) { _, _ in PageMirror.shared.refresh() }
            // A tap on a widget opens its list: sansserif://list/<id>.
            .onOpenURL { url in
                guard url.host() == "list", let id = UUID(uuidString: url.lastPathComponent),
                      lists.contains(where: { $0.id == id })
                else { return }
                currentID = id.uuidString
            }
    }

    /// This window's undo becomes the store's.
    private func takeUndo() {
        guard context.undoManager !== undoManager else { return }
        // Nothing unsaved is left for undo to trip over: see `GuideView.end`.
        try? context.save()
        context.undoManager = undoManager
    }

    /// The list on the page now.
    private var shownID: UUID? {
        (lists.first(where: { $0.id.uuidString == currentID }) ?? lists.first)?.id
    }

    @ViewBuilder private var page: some View {
        if !lists.isEmpty, !guideDone || guideReplay {
            // The first page teaches the app, and plays again from the Gestures line in settings.
            GuideView(lists: lists, isReplay: guideDone) {
                withAnimation(reduceMotion ? nil : .ink) {
                    guideDone = true
                    guideReplay = false
                }
            }
            .transition(.opacity)
        } else if let current = lists.first(where: { $0.id.uuidString == currentID }) ?? lists.first {
            PageView(list: current, lists: lists) { currentID = $0.id.uuidString }
                // Shake on iPhone and Cmd+Z on Mac undo the last change, a deleted task included.
                .onChange(of: undoManager, initial: true) { _, _ in takeUndo() }
                // With two windows there is one store and an undo manager for
                // each window. The store follows the window in front: before,
                // it kept the last window's, and undo did nothing in the others.
                .onChange(of: scenePhase) { _, phase in if phase == .active { takeUndo() } }
                #if os(macOS)
                .onChange(of: controlActiveState) { _, state in if state == .key { takeUndo() } }
                #endif
        } else {
            Color.paper.ignoresSafeArea()
        }
    }
}

#if DEBUG
#Preview {
    let container = try! PageStore.makeContainer(inMemory: true)
    try! PageStore.seedDefaultListsIfNeeded(in: container.mainContext)
    try! PageStore.seedSampleData(in: container.mainContext)
    return ContentView().modelContainer(container)
}
#endif
