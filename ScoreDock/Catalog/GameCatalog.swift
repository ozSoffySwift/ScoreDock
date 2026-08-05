import Foundation
import SwiftData

/// Where a preset came from.
///
/// Callers should rarely need this — the point of `GameCatalog` is that the rest of the app queries
/// one list and never cares which side a preset came from (§7.4). It matters only for editability
/// and for addressing a preset in `Match.presetSlug`.
enum PresetOrigin: Hashable, Sendable {
    case builtIn(slug: String)
    case user(id: UUID)

    /// The stable string written to `Match.presetSlug` and `PresetPreference.slug`. Built-ins use
    /// their slug; user presets use their UUID string. Both key the same preference table.
    var storageKey: String {
        switch self {
        case let .builtIn(slug): slug
        case let .user(id): id.uuidString
        }
    }
}

/// A preset as the UI sees it, regardless of origin.
struct GamePreset: Identifiable, Hashable, Sendable {
    var origin: PresetOrigin
    var name: String
    var emoji: String
    var engine: EngineKind
    var category: PresetCategory
    var rules: AnyRuleSet
    var defaultThemeID: String
    var sortIndex: Int

    var isFavorite: Bool = false
    var lastUsedAt: Date?

    /// Rule values still awaiting verification against a governing body (§8.5). Empty for user presets.
    var unverifiedRuleKeys: [String] = []

    var id: String { origin.storageKey }

    var isBuiltIn: Bool {
        if case .builtIn = origin { return true }
        return false
    }

    /// Built-ins are read-only in the UI. Editing one offers "Duplicate and edit", which creates a
    /// `UserGamePreset` with `derivedFromSlug` set (§7.4).
    var isEditable: Bool { !isBuiltIn }
}

// MARK: - Catalog

/// Vends built-in and user presets as one list (§7.4).
///
/// A value type built from already-fetched inputs rather than a service holding a `ModelContext`.
/// That keeps the merge and filter logic pure and unit-testable, and lets views drive it straight
/// from `@Query` so SwiftUI handles change tracking. Mutations live in `PresetPreferenceStore`.
struct GameCatalog: Sendable {
    var presets: [GamePreset]

    init(
        builtIns: [CatalogPreset] = BuiltInCatalog.presets,
        userPresets: [UserGamePreset] = [],
        preferences: [PresetPreference] = []
    ) {
        // No unique constraint is available under CloudKit (§7.5), so two devices can both create a
        // preference for the same slug offline. De-duplication is application logic: keep one per
        // slug, preferring a favourite so a user's flag is never the copy that loses.
        var preferenceBySlug: [String: PresetPreference] = [:]
        for preference in preferences {
            if let existing = preferenceBySlug[preference.slug] {
                let winner = Self.preferredPreference(existing, preference)
                preferenceBySlug[preference.slug] = winner
            } else {
                preferenceBySlug[preference.slug] = preference
            }
        }

        let builtInPresets = builtIns.map { catalog -> GamePreset in
            let preference = preferenceBySlug[catalog.slug]
            return GamePreset(
                origin: .builtIn(slug: catalog.slug),
                name: catalog.name,
                emoji: catalog.emoji,
                engine: catalog.engine,
                category: catalog.category,
                rules: catalog.rules,
                defaultThemeID: catalog.defaultThemeID,
                sortIndex: catalog.sortIndex,
                isFavorite: preference?.isFavorite ?? false,
                lastUsedAt: preference?.lastUsedAt,
                unverifiedRuleKeys: catalog.unverifiedRuleKeys
            )
        }

        let userMade = userPresets.map { stored -> GamePreset in
            let preference = preferenceBySlug[stored.id.uuidString]
            return GamePreset(
                origin: .user(id: stored.id),
                name: stored.name,
                emoji: stored.emoji,
                engine: stored.engine,
                category: stored.category,
                // A user preset with no rules yet falls back to its engine's defaults rather than
                // being dropped from the list, which would look like data loss.
                rules: stored.rules ?? GameCatalog.defaultRules(for: stored.engine),
                defaultThemeID: stored.defaultThemeID,
                sortIndex: stored.sortIndex,
                isFavorite: preference?.isFavorite ?? false,
                lastUsedAt: preference?.lastUsedAt
            )
        }

        presets = builtInPresets + userMade
    }

    private static func preferredPreference(
        _ lhs: PresetPreference,
        _ rhs: PresetPreference
    ) -> PresetPreference {
        if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite ? lhs : rhs }
        switch (lhs.lastUsedAt, rhs.lastUsedAt) {
        case let (l?, r?): return l >= r ? lhs : rhs
        case (_?, nil): return lhs
        case (nil, _?): return rhs
        case (nil, nil): return lhs
        }
    }

    static func defaultRules(for engine: EngineKind) -> AnyRuleSet {
        switch engine {
        case .team: .team(TeamRules())
        case .setMatch: .setMatch(SetMatchRules())
        case .list: .list(ListRules())
        case .specialised: .specialised(SpecialisedRules())
        }
    }
}

// MARK: - Queries

extension GameCatalog {
    func preset(withID id: String) -> GamePreset? {
        presets.first { $0.id == id }
    }

    /// User presets first within each category — a format someone saved themselves is the one they
    /// are most likely reaching for.
    func presets(in category: PresetCategory) -> [GamePreset] {
        presets
            .filter { $0.category == category }
            .sorted { lhs, rhs in
                if lhs.isBuiltIn != rhs.isBuiltIn { return !lhs.isBuiltIn }
                if lhs.sortIndex != rhs.sortIndex { return lhs.sortIndex < rhs.sortIndex }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
    }

    /// Every category that has at least one preset, in picker order.
    func groupedByCategory() -> [(category: PresetCategory, presets: [GamePreset])] {
        let order: [PresetCategory] = [.team, .setMatch, .specialised, .list]
        return order.compactMap { category in
            let matches = presets(in: category)
            return matches.isEmpty ? nil : (category, matches)
        }
    }

    var favourites: [GamePreset] {
        presets
            .filter(\.isFavorite)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Most recently played first. Presets never played are excluded rather than sorted last.
    func recent(limit: Int = 6) -> [GamePreset] {
        presets
            .compactMap { preset in preset.lastUsedAt.map { (preset, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    /// Diacritic- and case-insensitive search over names, so "פוטבול" and "futbol" both behave.
    func matching(_ query: String) -> [GamePreset] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return presets
            .filter { $0.name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Mutations

/// Writes preference and preset changes. Separated from `GameCatalog` so the catalog itself stays
/// a pure value type.
@MainActor
struct PresetPreferenceStore {
    let context: ModelContext

    /// Fetches the preference for a preset, creating it on first use.
    ///
    /// Handles the duplicate case explicitly rather than assuming one row per slug — see the note
    /// in `GameCatalog.init` on why uniqueness cannot be enforced by the store (§7.5).
    func preference(for key: String) -> PresetPreference {
        let descriptor = FetchDescriptor<PresetPreference>(
            predicate: #Predicate { $0.slug == key }
        )
        if let existing = try? context.fetch(descriptor), let first = existing.first {
            return first
        }
        let created = PresetPreference(slug: key)
        context.insert(created)
        return created
    }

    func toggleFavourite(_ preset: GamePreset) {
        let preference = preference(for: preset.origin.storageKey)
        preference.isFavorite.toggle()
    }

    /// Records a play, which is what feeds the Recent section.
    func markUsed(_ preset: GamePreset, at date: Date = .now) {
        preference(for: preset.origin.storageKey).lastUsedAt = date
    }

    /// "Duplicate and edit" — the only way to change a built-in (§7.4).
    @discardableResult
    func duplicate(_ preset: GamePreset, named name: String? = nil) -> UserGamePreset {
        let copy = UserGamePreset(
            name: name ?? String(localized: "\(preset.name) copy", comment: "Duplicated preset name"),
            emoji: preset.emoji,
            engine: preset.engine,
            category: preset.category,
            derivedFromSlug: preset.isBuiltIn ? preset.origin.storageKey : nil,
            rules: preset.rules,
            defaultThemeID: preset.defaultThemeID,
            sortIndex: preset.sortIndex
        )
        context.insert(copy)
        return copy
    }
}
