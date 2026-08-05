import Foundation
import SwiftData
import Testing
import UIKit

@testable import ScoreDock

/// §5.2 and §5.5.
///
/// **These tests deliberately stop short of the exit criterion.** §5.5 is explicit that the
/// simulator does not faithfully reproduce external-display scene-role behaviour or AirPlay
/// latency, so "board runs on an Apple TV while the panel stays live on the phone" can only be
/// signed off on physical hardware. What is asserted here is everything that *can* be checked
/// without a second screen: that the routing is correct, that connection state tracks, and that one
/// store feeds both surfaces.
@Suite("External display wiring (§5.2)")
@MainActor
struct ExternalDisplayTests {
    @Test("Only the external-display role gets the external delegate")
    func sceneRouting() {
        #expect(
            AppDelegate.delegateClass(for: .windowExternalDisplayNonInteractive)
                === ExternalDisplaySceneDelegate.self
        )
        // Everything else falls through so SwiftUI keeps managing the main window.
        #expect(AppDelegate.delegateClass(for: .windowApplication) == nil)
    }

    @Test("Connection state tracks scene lifecycle")
    func connectionState() {
        let display = ExternalDisplay.shared
        display.sceneDisconnected()
        #expect(!display.isConnected)

        display.sceneConnected()
        #expect(display.isConnected)

        display.sceneDisconnected()
        #expect(!display.isConnected)
    }

    /// §5.2's core requirement: one source of truth, two renderers — never two copies of the state.
    @Test("The external scene reads the same store the panel is driving")
    func sharedStore() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let match = Match(
            presetSlug: "basketball",
            rulesSnapshot: .team(BuiltInCatalog.bySlug["basketball"]?.rules.teamRules ?? TeamRules()),
            themeSnapshot: BuiltInThemes.theme(id: "dark")
        )
        context.insert(match)
        for slot in 0 ..< 2 {
            let side = MatchSide(slotIndex: slot, displayName: "Side \(slot)")
            side.match = match
            context.insert(side)
        }
        let store = try #require(LiveMatchStore(match: match, context: context))

        let active = ActiveMatch.shared
        active.begin(.team(store))
        defer { active.end() }

        // The external scene resolves to the identical object, not a copy — which is what makes the
        // TV and the panel one source of truth rather than two.
        guard case let .team(published)? = active.store else {
            Issue.record("expected a team store on the external scene")
            return
        }
        #expect(published === store)

        store.perform(.score(slot: 0, points: 3))
        #expect(published.state.sides[0].score == 3)

        active.end()
        #expect(active.store == nil, "ending a match releases the TV back to idle")
    }

    @Test("Board mode defaults to the full board and resets when a match ends")
    func boardModeLifecycle() {
        let active = ActiveMatch.shared
        active.end()
        #expect(active.boardMode == .full)

        active.boardMode = .shotClockOnly
        active.end()
        #expect(active.boardMode == .full, "a new match should not inherit the last one's TV mode")
    }

    // MARK: The scene configuration (§5.2)

    /// **The bug this exists for.** The external-display scene was configured in
    /// `AppDelegate.application(_:configurationForConnecting:options:)` to avoid naming the delegate
    /// class as a string in `Info.plist`, on the reasoning that a string breaks silently on a module
    /// rename. The reasoning was sound and the conclusion was wrong: in a SwiftUI-lifecycle app that
    /// delegate method is **never called** — SwiftUI installs its own delegate for scene management —
    /// so the app never claimed the display and an AirPlay session simply went on mirroring the
    /// phone. Confirmed on hardware, then reproduced with a simulated external display.
    ///
    /// The configuration now lives in the plist, where it works, and the string risk is handled
    /// here: this resolves the exact value the bundle ships. A silent break a test catches beats a
    /// feature that never runs.
    @Test("The external display scene is declared, and its delegate class name resolves")
    func sceneConfigurationResolves() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let plist = try #require(bundle.bundleURL.appendingPathComponent("Info.plist") as URL?)
        let data = try Data(contentsOf: plist)
        let info = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        let manifest = try #require(
            info["UIApplicationSceneManifest"] as? [String: Any],
            "no scene manifest — the system will never offer an external-display scene"
        )
        #expect(
            manifest["UIApplicationSupportsMultipleScenes"] as? Bool == true,
            "without this the external scene is never offered at all"
        )

        let configurations = try #require(
            manifest["UISceneConfigurations"] as? [String: Any],
            "no UISceneConfigurations — the scene is offered but never configured, so the TV mirrors"
        )
        let external = try #require(
            configurations["UIWindowSceneSessionRoleExternalDisplayNonInteractive"] as? [[String: Any]],
            "the non-interactive external display role is not declared"
        )
        let entry = try #require(external.first)

        let className = try #require(entry["UISceneDelegateClassName"] as? String)
        #expect(className.hasSuffix(".ExternalDisplaySceneDelegate"), "\(className) does not name the delegate")

        // The whole point: the string in the plist has to still resolve to the real class.
        let resolved: AnyClass = try #require(
            NSClassFromString(className),
            "\(className) resolves to nothing — a rename broke the plist"
        )
        #expect(resolved === ExternalDisplaySceneDelegate.self)
    }

    /// Only the external role is declared; the main window is SwiftUI's to configure.
    @Test("The application scene role is left to SwiftUI")
    func applicationRoleIsNotOverridden() throws {
        let bundle = Bundle(for: AppDelegate.self)
        let data = try Data(contentsOf: bundle.bundleURL.appendingPathComponent("Info.plist"))
        let info = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        let manifest = try #require(info["UIApplicationSceneManifest"] as? [String: Any])
        let configurations = manifest["UISceneConfigurations"] as? [String: Any] ?? [:]

        #expect(
            configurations["UIWindowSceneSessionRoleApplication"] == nil,
            "declaring the application role here would take the main window away from SwiftUI"
        )
    }
}
