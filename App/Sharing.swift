#if os(iOS)
import CloudKit
import SwiftUI
import UIKit

/// A list's share, ready to show: who is on it, and the way to invite more.
struct ListShare: Identifiable {
    let id = UUID()
    let share: CKShare
    let list: TaskList
}

/// The system's own sheet for sharing through iCloud: invite by Messages or
/// Mail, see who has joined, stop sharing, or leave.
struct ShareSheet: UIViewControllerRepresentable {
    let item: ListShare

    func makeCoordinator() -> Coordinator {
        Coordinator(item: item)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: item.share, container: CloudSync.shared.cloudContainer)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let item: ListShare

        init(item: ListShare) {
            self.item = item
        }

        func itemTitle(for controller: UICloudSharingController) -> String? {
            item.list.name
        }

        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: any Error) {}

        func cloudSharingControllerDidStopSharing(_ controller: UICloudSharingController) {
            // For the owner the list stays, private again. For someone who
            // left, iCloud takes the list away and the engine removes it here.
            if !item.list.isSomeoneElses { CloudSync.shared.sharingStopped(for: item.list) }
        }
    }
}

/// An invitation to a list opens the app. With SwiftUI's own app life cycle
/// that arrives at a scene delegate, so the app has one, for this only.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        // The app was not running when the invitation was opened.
        if let metadata = options.cloudKitShareMetadata {
            Task { await CloudSync.shared.accept(metadata) }
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await CloudSync.shared.accept(metadata) }
    }
}
#endif
