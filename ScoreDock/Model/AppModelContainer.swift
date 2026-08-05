import Foundation
import SwiftData

/// Builds the app's SwiftData stack.
///
/// v1 ships with `cloudKitDatabase: .none` (§7.5). The schema is nonetheless CloudKit-safe from the
/// first commit, because retrofitting those constraints onto a populated store means a migration on
/// every user's device, while adopting them up front costs almost nothing.
///
/// Note what is *absent* here: no seeding. The 37 built-in presets and 12 built-in themes are
/// bundled value types, not rows (§7.4) — which is what makes "two devices first-launch before sync
/// settles and each insert their own 37" structurally impossible rather than something to defend
/// against.
enum AppModelContainer {
    static let schema = Schema([
        Player.self,
        Team.self,
        TeamMembership.self,
        UserGamePreset.self,
        PresetPreference.self,
        Match.self,
        MatchSide.self,
        ScoreEvent.self,
        ThemePreset.self,
    ])

    /// Launch argument that flips the store to `.automatic` so the schema is pushed to the CloudKit
    /// *development* environment and every model is validated against it (§7.5, M0 exit criterion).
    ///
    /// Requires a signed build with the iCloud entitlement and a signed-in iCloud account. The
    /// static rule checks in `CloudKitSchemaTests` cover the same constraints with no account at
    /// all, and are what runs in CI; this is the belt-and-braces confirmation on real hardware.
    static let cloudKitValidationArgument = "-validate-cloudkit-schema"

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            // The in-memory store is only ever reached as a fallback after the real one failed, so
            // it deliberately ignores the CloudKit mode. Applying `.automatic` here too meant that
            // a schema violation failed the fallback as well and took the app down with it — which
            // defeated the entire point of having a fallback. Caught by the §7.5 negative control.
            cloudKitDatabase: inMemory ? .none : cloudKitDatabaseMode
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private static var cloudKitDatabaseMode: ModelConfiguration.CloudKitDatabase {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(cloudKitValidationArgument) {
            return .automatic
        }
        #endif
        // Sync is not a v1 feature (§16). Enabling it later is this one argument.
        return .none
    }
}
