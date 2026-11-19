#if os(iOS)
import CloudKit
import UIKit

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
