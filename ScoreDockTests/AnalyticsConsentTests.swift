import Foundation
import Testing

@testable import ScoreDock

/// §16 — the analytics opt-out has to be real.
///
/// A privacy switch is worth less than no switch at all if it only appears to work, so these cover
/// the two ways that happens in practice: the choice not surviving relaunch, and the default being
/// quietly wrong.
@Suite("Analytics consent (§16)")
@MainActor
struct AnalyticsConsentTests {
    /// Each test gets its own suite name so nothing leaks between them or into the real app's
    /// preferences on the simulator.
    private func isolatedDefaults(_ name: String = UUID().uuidString) -> UserDefaults {
        UserDefaults(suiteName: name)!
    }

    @Test("Analytics is on by default")
    func defaultsToEnabled() {
        let settings = AppSettings(defaults: isolatedDefaults())
        #expect(settings.analyticsEnabled, "the store listing and PRIVACY.md both describe collection as the default")
    }

    /// The failure this exists for: the toggle writes to an in-memory property, the user believes
    /// they have opted out, and the next launch reads the default and starts collecting again.
    @Test("Opting out survives a relaunch")
    func optOutPersists() {
        let suite = UUID().uuidString
        let defaults = isolatedDefaults(suite)

        let first = AppSettings(defaults: defaults)
        first.analyticsEnabled = false

        // A second instance over the same storage is what a cold start actually looks like.
        let relaunched = AppSettings(defaults: defaults)
        #expect(!relaunched.analyticsEnabled, "the opt-out was lost between launches")
    }

    @Test("Opting back in survives a relaunch too")
    func optInPersists() {
        let suite = UUID().uuidString
        let defaults = isolatedDefaults(suite)

        let first = AppSettings(defaults: defaults)
        first.analyticsEnabled = false
        first.analyticsEnabled = true

        #expect(AppSettings(defaults: defaults).analyticsEnabled)
    }

    /// The preference is the single source of truth the launch path re-applies, so it has to be
    /// readable without Firebase having been configured — which it is not, under test.
    @Test("The stored preference is readable without a configured Firebase app")
    func readableWithoutFirebase() {
        let defaults = isolatedDefaults()
        let settings = AppSettings(defaults: defaults)

        settings.analyticsEnabled = false
        #expect(defaults.bool(forKey: AppSettings.Key.analyticsEnabled) == false)

        settings.analyticsEnabled = true
        #expect(defaults.bool(forKey: AppSettings.Key.analyticsEnabled) == true)
    }
}
