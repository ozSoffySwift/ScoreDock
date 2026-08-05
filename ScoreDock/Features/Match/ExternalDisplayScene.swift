import OSLog
import SwiftUI
import UIKit

/// Hosts the board on an attached external display (§5.2).
///
/// SwiftUI has no external-display scene role, so this is the UIKit interop the spec calls for: a
/// `UIWindow` on the external `UIWindowScene` whose root is a `UIHostingController` wrapping
/// `ExternalBoardView`, reading the *same* `ActiveMatch.shared.store` the control panel is driving.
///
/// The scene is `NonInteractive` — a TV has no touch input, and the operator keeps their controls on
/// the device.
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "external-display")

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        Self.logger.info("External display connected: \(windowScene.effectiveGeometry.coordinateSpace.bounds.size.debugDescription, privacy: .public)")

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: ExternalBoardView())
        // A TV should show only the board — no status bar, no chrome.
        window.isHidden = false
        self.window = window

        MainActor.assumeIsolated {
            ExternalDisplay.shared.sceneConnected()
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Self.logger.info("External display disconnected")
        window = nil
        MainActor.assumeIsolated {
            ExternalDisplay.shared.sceneDisconnected()
        }
    }
}
