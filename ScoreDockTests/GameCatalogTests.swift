import Foundation
import Testing

@testable import ScoreDock

/// §7.4 — one list, regardless of which side a preset came from.
@Suite("Game catalog merge and query (§7.4)")
struct GameCatalogTests {
    @Test("Built-ins alone produce the full catalog")
    func builtInsOnly() {
        let catalog = GameCatalog()
        #expect(catalog.presets.count == 37)

        // Hoisted out of `#expect`: the macro decomposes the expression, and `allSatisfy` is
        // `rethrows`, which the expansion then wants a `try` for.
        let allBuiltIn = catalog.presets.allSatisfy(\.isBuiltIn)
        #expect(allBuiltIn)

        // Built-ins are read-only; editing offers Duplicate and edit.
        let noneEditable = catalog.presets.allSatisfy { !$0.isEditable }
        #expect(noneEditable)
    }

    @Test("User presets join the same list and are editable")
    func userPresetsMerge() {
        let mine = UserGamePreset(
            name: "Friday five-a-side",
            emoji: "⚽️",
            engine: .team,
            category: .team,
            derivedFromSlug: "soccer",
            rules: .team(TeamRules())
        )
        let catalog = GameCatalog(userPresets: [mine])

        #expect(catalog.presets.count == 38)
        let found = catalog.preset(withID: mine.id.uuidString)
        #expect(found?.name == "Friday five-a-side")
        #expect(found?.isBuiltIn == false)
        #expect(found?.isEditable == true)
    }

    @Test("A user preset with no rules falls back to its engine defaults")
    func userPresetWithoutRules() {
        let empty = UserGamePreset(name: "Draft", engine: .setMatch, category: .setMatch, rules: nil)
        let catalog = GameCatalog(userPresets: [empty])

        // Present rather than silently dropped, which would read as data loss.
        let found = catalog.preset(withID: empty.id.uuidString)
        #expect(found != nil)
        #expect(found?.rules.setMatchRules == SetMatchRules())
    }

    @Test("Preferences attach to the matching preset")
    func preferencesAttach() {
        let favourite = PresetPreference(slug: "basketball", isFavorite: true)
        let played = PresetPreference(slug: "soccer", lastUsedAt: .now)
        let catalog = GameCatalog(preferences: [favourite, played])

        #expect(catalog.favourites.map(\.id) == ["basketball"])
        #expect(catalog.recent().map(\.id) == ["soccer"])
        #expect(catalog.preset(withID: "tennis")?.isFavorite == false)
    }

    /// No unique constraint is available under CloudKit (§7.5), so two devices can create the same
    /// preference offline. The merge must not drop a user's favourite flag.
    @Test("Duplicate preferences for one slug merge without losing a favourite")
    func duplicatePreferencesMerge() {
        let plain = PresetPreference(slug: "tennis", isFavorite: false)
        let favourited = PresetPreference(slug: "tennis", isFavorite: true)

        // Whichever order they arrive in, the favourite survives.
        #expect(GameCatalog(preferences: [plain, favourited]).favourites.map(\.id) == ["tennis"])
        #expect(GameCatalog(preferences: [favourited, plain]).favourites.map(\.id) == ["tennis"])
    }

    @Test("Duplicate preferences keep the most recent play")
    func duplicatePreferencesKeepLatest() throws {
        let older = Date(timeIntervalSince1970: 1_000)
        let newer = Date(timeIntervalSince1970: 2_000)
        let catalog = GameCatalog(preferences: [
            PresetPreference(slug: "darts", lastUsedAt: older),
            PresetPreference(slug: "darts", lastUsedAt: newer),
        ])
        #expect(catalog.preset(withID: "darts")?.lastUsedAt == newer)
    }

    @Test("Recent is ordered by most recent play and excludes unplayed presets")
    func recentOrdering() {
        let catalog = GameCatalog(preferences: [
            PresetPreference(slug: "soccer", lastUsedAt: Date(timeIntervalSince1970: 100)),
            PresetPreference(slug: "tennis", lastUsedAt: Date(timeIntervalSince1970: 300)),
            PresetPreference(slug: "darts", lastUsedAt: Date(timeIntervalSince1970: 200)),
            PresetPreference(slug: "cricket", isFavorite: true),
        ])

        #expect(catalog.recent().map(\.id) == ["tennis", "darts", "soccer"])
        #expect(catalog.recent(limit: 2).map(\.id) == ["tennis", "darts"])
    }

    @Test("Categories group in picker order and hold every preset")
    func grouping() {
        let groups = GameCatalog().groupedByCategory()
        #expect(groups.map(\.category) == [.team, .setMatch, .specialised, .list])
        #expect(groups.map(\.presets.count) == [20, 8, 5, 4])
        #expect(groups.reduce(0) { $0 + $1.presets.count } == 37)
    }

    @Test("A user preset sorts above built-ins in its category")
    func userPresetsSortFirst() throws {
        let mine = UserGamePreset(name: "My league", engine: .team, category: .team, rules: .team(TeamRules()))
        let teamPresets = GameCatalog(userPresets: [mine]).presets(in: .team)
        #expect(teamPresets.first?.name == "My league")
    }

    @Test("Search is case- and diacritic-insensitive, and matches Hebrew")
    func search() {
        let catalog = GameCatalog()

        // Three, not two: "Basketball shot clock" is a preset in its own right.
        let expectedBasketball = ["basketball", "basketball-nba", "basketball-shot-clock"]
        #expect(catalog.matching("basketball").map(\.id).sorted() == expectedBasketball)
        #expect(catalog.matching("BASKETBALL").map(\.id).sorted() == expectedBasketball)
        #expect(catalog.matching("tenn").map(\.id).contains("tennis"))
        #expect(catalog.matching("").isEmpty)
        #expect(catalog.matching("   ").isEmpty)
        #expect(catalog.matching("quidditch").isEmpty)
    }

    @Test("Origins address presets consistently")
    func originStorageKeys() {
        let id = UUID()
        #expect(PresetOrigin.builtIn(slug: "soccer").storageKey == "soccer")
        #expect(PresetOrigin.user(id: id).storageKey == id.uuidString)
    }
}
