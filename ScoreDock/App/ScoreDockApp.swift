import OSLog
import SwiftData
import SwiftUI

/// App entry point.
///
/// The product name is now committed to throughout — target, module, bundle identifier and types.
/// This resolves §19.1 question 1 in favour of ScoreDock, and supersedes the earlier stance of
/// keeping the name out of the codebase so a rename would stay cheap.
///
/// **§17 risk 1 is not closed by this.** Five similarly-named apps were already on the App Store as
/// of July 2026, alongside the established scorecounter.com brand, so this remains a naming
/// collision and an ASO problem. What still has to happen before submission (M8): search the App
/// Store, check trademark registries in US/EU/IL, and confirm the domain. If the name has to change
/// after all, it is now a project-wide rename rather than a two-file edit — that cost was accepted
/// deliberately, not overlooked.
@main
struct ScoreDockApp: App {
    /// Present solely to widen the supported interface orientations — see `AppDelegate` and §5.1.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The same instance the external display scene reads (§5.2).
    @State private var settings = AppSettings.shared
    @State private var storeFailure: String?

    private let container: ModelContainer

    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "app")

    init() {
        // Falling back to an in-memory store beats crashing at launch: a scoreboard that opens
        // without history is still a usable scoreboard, and the operator finds out at the scorer's
        // table rather than losing the app entirely. The banner makes the degradation visible.
        do {
            container = try AppModelContainer.make()
        } catch {
            Self.logger.fault("Persistent store failed to open: \(String(describing: error), privacy: .public)")
            _storeFailure = State(initialValue: error.localizedDescription)
            container = try! AppModelContainer.make(inMemory: true)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(storeFailure: storeFailure)
                .environment(settings)
        }
        .modelContainer(container)
    }
}
