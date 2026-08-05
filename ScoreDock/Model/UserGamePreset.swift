import Foundation
import SwiftData

/// A game format the user saved themselves.
///
/// User presets are the *only* presets that live in the store. The 37 built-ins are bundled catalog
/// data decoded at launch, never seeded rows — see the reasoning in §7.4 and `GameCatalog`.
@Model
final class UserGamePreset {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "🏆"

    // Engine and category are real columns, not fields inside `rules`, because they must be
    // predicate-queryable (§7.3). The blob buys schema stability; these two buy filtering.
    var engineRaw: String = EngineKind.team.rawValue
    var categoryRaw: String = PresetCategory.team.rawValue

    /// Set when this was created by duplicating a built-in, which is what "Duplicate and edit"
    /// produces when a user tries to edit a read-only built-in (§7.4).
    var derivedFromSlug: String?

    /// Engine-tagged Codable blob. Adding a rule is a versioned decoder change rather than a store
    /// migration — the trade-off being that nothing inside here is predicate-queryable (§7.3).
    ///
    /// Held as `Data` and read through `rules`; see `CodableBlob` for why.
    var rulesData: Data?

    var defaultThemeID: String = "dark"
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String = "",
        emoji: String = "🏆",
        engine: EngineKind = .team,
        category: PresetCategory = .team,
        derivedFromSlug: String? = nil,
        rules: AnyRuleSet? = nil,
        defaultThemeID: String = "dark",
        sortIndex: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.engineRaw = engine.rawValue
        self.categoryRaw = category.rawValue
        self.derivedFromSlug = derivedFromSlug
        self.rulesData = CodableBlob.encode(rules)
        self.defaultThemeID = defaultThemeID
        self.sortIndex = sortIndex
        self.createdAt = createdAt
    }
}

extension UserGamePreset {
    var rules: AnyRuleSet? {
        get { CodableBlob.decode(rulesData) }
        set { rulesData = CodableBlob.encode(newValue) }
    }

    var engine: EngineKind {
        get { EngineKind(storedRaw: engineRaw) }
        set { engineRaw = newValue.rawValue }
    }

    var category: PresetCategory {
        get { PresetCategory(storedRaw: categoryRaw) }
        set { categoryRaw = newValue.rawValue }
    }
}
