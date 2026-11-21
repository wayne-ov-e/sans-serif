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

    /// An iPhone stays upright: on its side the page is short and wide, and
    /// the rows of words at the bottom get complicated (Wayne, Nov 21, 2026).
    /// The one exception is an iPhone Duo, open: its inner screen is wide
    /// enough to be turned. There is no asking the system whether a phone is
    /// a Duo, so it is known by its screen: no other iPhone's is this wide.
    /// Closed, a Duo shows its outer screen and is upright like the rest.
    func application(
        _ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
        let screen = (window?.windowScene?.screen ?? UIScreen.main).bounds.size
        return Self.turns(phoneScreen: screen) ? .allButUpsideDown : .portrait
    }

    /// Whether a phone with this screen may be turned on its side. The widest
    /// ordinary iPhone is 440 points across.
    static func turns(phoneScreen size: CGSize) -> Bool {
        min(size.width, size.height) >= 500
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

    /// A Duo was opened or closed: which ways it may be turned has changed.
    func windowScene(
        _ windowScene: UIWindowScene, didUpdate previousCoordinateSpace: any UICoordinateSpace,
        interfaceOrientation previousInterfaceOrientation: UIInterfaceOrientation,
        traitCollection previousTraitCollection: UITraitCollection
    ) {
        for window in windowScene.windows {
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}
#elseif os(macOS)
import AppKit
import CloudKit

/// On the Mac an invitation to a list comes to the app's own delegate.
/// Without one, a link opened there joined nothing.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        Task { await CloudSync.shared.accept(metadata) }
    }
}
#endif
