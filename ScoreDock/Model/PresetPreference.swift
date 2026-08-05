import Foundation
import SwiftData

/// Favourite and recency state for a *built-in* preset, keyed by slug.
///
/// Small, and safe to sync: it holds a reference to catalog data rather than a copy of it, so a
/// device on an older build receiving a preference for a preset it does not have simply ignores it
/// — which is exactly the failure mode that seeding all 37 presets as rows would not have (§7.4).
@Model
final class PresetPreference {
    /// The built-in slug, e.g. `"basketball-nba"`. Not `@Attribute(.unique)` — unique constraints
    /// are unsupported under CloudKit (§7.5), so `PresetPreferenceStore` enforces one-per-slug in
    /// application logic.
    var slug: String = ""

    var isFavorite: Bool = false
    var lastUsedAt: Date?
    var sortIndex: Int = 0

    /// Whether the "Rules vary by league — check yours" hint has been shown for this preset (§8.5).
    /// Shown on first use, then dismissed for good.
    var hasSeenRulesHint: Bool = false

    /// Whether per-player attribution was left on the last time this preset was played (§4.1).
    /// Remembered per preset, so a coach who always wants it gets it without a second thought.
    var attributionEnabled: Bool = false

    init(
        slug: String = "",
        isFavorite: Bool = false,
        lastUsedAt: Date? = nil,
        sortIndex: Int = 0,
        hasSeenRulesHint: Bool = false,
        attributionEnabled: Bool = false
    ) {
        self.slug = slug
        self.isFavorite = isFavorite
        self.lastUsedAt = lastUsedAt
        self.sortIndex = sortIndex
        self.hasSeenRulesHint = hasSeenRulesHint
        self.attributionEnabled = attributionEnabled
    }
}
