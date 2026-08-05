import SwiftUI
import UIKit

/// Owns which interface orientations the app will accept (§5.1).
///
/// `Info.plist` declaring all four orientations is **not** sufficient. The SwiftUI hosting
/// controller narrows what it reports, and `requestGeometryUpdate` is then refused with
/// *"None of the requested orientations are supported by the view controller. Requested:
/// landscapeLeft, landscapeRight; Supported: portrait"*. Implementing this delegate method is what
/// actually widens the mask.
///
/// That matters more here than in most apps: §5.1 makes the full-screen button the *mandatory*
/// mitigation for rotation lock, because a large share of users keep Portrait Orientation Lock on
/// permanently and rotate-to-board silently does nothing for them. Rotation is the delight; this is
/// the guarantee, so it has to actually work.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Narrowed to `.landscape` while the board is presented full screen, restored to `.all`
    /// afterwards so the rest of the app rotates normally.
    static var supportedOrientations: UIInterfaceOrientationMask = .all

    nonisolated func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        MainActor.assumeIsolated { Self.supportedOrientations }
    }

    /// Routes an attached external display to `ExternalDisplaySceneDelegate` (§5.2).
    ///
    /// **This is a fallback, and on current iOS it is never called.** It was originally the *only*
    /// wiring, chosen over a `UISceneConfigurations` entry in `Info.plist` because that has to name
    /// the delegate as the string `"$(PRODUCT_MODULE_NAME).ExternalDisplaySceneDelegate"`, which
    /// breaks silently on a module rename. The reasoning was sound and the conclusion was wrong: in
    /// a SwiftUI-lifecycle app, SwiftUI installs its own delegate for scene management and this
    /// method is not consulted — so the app never claimed the display and AirPlay went on mirroring
    /// the phone. Verified by attaching a simulated external display and finding
    /// `ExternalDisplaySceneDelegate.scene(_:willConnectTo:)` had never run.
    ///
    /// The configuration now lives in the plist, and the string it depends on is asserted by
    /// `ExternalDisplayTests.sceneConfigurationResolves` — which is where that risk belonged all
    /// along. This stays because it costs nothing and would be correct if a future iOS did call it.
    ///
    /// Every other role falls through to the default, so SwiftUI keeps managing the main window.
    nonisolated func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // `UISceneSession.role`, `UISceneConfiguration.init` and `delegateClass` are all main-actor
        // isolated, and UIKit calls this delegate method on the main thread — but the protocol
        // requirement is `nonisolated`, so the compiler cannot see that. Same `assumeIsolated` as
        // `supportedInterfaceOrientationsFor` above, for the same reason.
        MainActor.assumeIsolated {
            let role = connectingSceneSession.role
            let configuration = UISceneConfiguration(name: nil, sessionRole: role)
            configuration.delegateClass = Self.delegateClass(for: role)
            return configuration
        }
    }

    /// The routing decision, pulled out so it can be tested without a `UISceneSession` — which
    /// cannot be constructed outside UIKit. §5.5 warns the simulator does not faithfully reproduce
    /// scene-role behaviour, so being able to assert the *wiring* without hardware is worth the
    /// extra indirection.
    ///
    /// Returning nil for every other role leaves SwiftUI managing the main window.
    nonisolated static func delegateClass(for role: UISceneSession.Role) -> AnyClass? {
        role == .windowExternalDisplayNonInteractive ? ExternalDisplaySceneDelegate.self : nil
    }
}

extension AppDelegate {
    /// Forces the scene into `mask`, widening the supported set first so the request is not refused.
    ///
    /// **Sequencing matters, and is easy to get subtly wrong.** `setNeedsUpdateOfSupportedInterface`
    /// `Orientations()` only marks the controller dirty; it re-queries on the next layout pass.
    /// Requesting the geometry change in the same turn therefore evaluates it against the *stale*
    /// mask and is refused — the scene then usually rotates anyway on the following pass, so the
    /// feature appears to work while logging an error every time. Deferring the request by one
    /// main-actor hop makes it actually succeed rather than succeed by accident.
    static func setOrientation(
        _ mask: UIInterfaceOrientationMask,
        onFailure: ((any Error) -> Void)? = nil
    ) {
        supportedOrientations = mask

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }

        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()

        Task { @MainActor in
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                onFailure?(error)
            }
        }
    }
}
