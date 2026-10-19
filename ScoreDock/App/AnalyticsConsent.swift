import FirebaseAnalytics
import Foundation
import OSLog

/// The single place Firebase is told whether it may collect anything (§16).
///
/// **Why this exists rather than a one-line call in the settings screen.** Opting out has to hold
/// in three different situations, and they are easy to get wrong separately:
///
/// 1. The moment the switch is flipped, so events stop immediately rather than at next launch.
/// 2. At every launch afterwards, because `FirebaseApp.configure()` re-enables collection from the
///    SDK's own default unless it is told otherwise.
/// 3. When the user opts back in, which has to actually resume collection.
///
/// Routing all three through one type means `AppSettings` needs no Firebase import and stays
/// testable without a configured `FirebaseApp`, and there is one place to read to know what the
/// app promises its users.
enum AnalyticsConsent {
    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "privacy")

    /// Applies the user's choice to the SDK.
    ///
    /// `setAnalyticsCollectionEnabled(false)` is persisted by Firebase itself and also clears
    /// collection for the current session, so this is safe to call before or after `configure()`.
    static func apply(enabled: Bool) {
        Analytics.setAnalyticsCollectionEnabled(enabled)
        logger.notice("Analytics collection \(enabled ? "enabled" : "disabled", privacy: .public) by user preference.")
    }

    /// Re-applies the stored preference at launch.
    ///
    /// Called straight after `FirebaseApp.configure()`. Without this, an opted-out user would be
    /// silently opted back in by the SDK's default on every cold start — the exact bug that makes a
    /// privacy toggle a lie.
    @MainActor
    static func applyStoredPreference() {
        apply(enabled: AppSettings.shared.analyticsEnabled)
    }
}
