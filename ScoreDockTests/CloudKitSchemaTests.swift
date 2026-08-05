import Foundation
import SwiftData
import Testing

@testable import ScoreDock

/// Enforces the §7.5 CloudKit rules statically, with no entitlement, no iCloud account and no
/// network — so they hold in CI and on every commit.
///
/// **What this cannot check:** "every stored property is optional or has a default value". A Swift
/// default (`var name: String = ""`) lives in the generated initialiser, not in the schema metadata,
/// so there is nothing to introspect. That rule is covered by launching with
/// `AppModelContainer.cloudKitValidationArgument`, which opens the store against the CloudKit
/// development environment and refuses on violation. Both halves are needed; neither is sufficient.
@Suite("CloudKit schema rules (§7.5)")
struct CloudKitSchemaTests {
    private var entities: [Schema.Entity] { AppModelContainer.schema.entities }

    @Test("All nine models are registered")
    func schemaIsComplete() {
        let names = Set(entities.map(\.name))
        #expect(names == [
            "Player", "Team", "TeamMembership",
            "UserGamePreset", "PresetPreference",
            "Match", "MatchSide", "ScoreEvent",
            "ThemePreset",
        ])
    }

    /// Unique constraints are unsupported with CloudKit. De-duplication has to be application logic
    /// — see `GameCatalog.init` for the preference case.
    @Test("No attribute declares a unique constraint")
    func noUniqueAttributes() {
        for entity in entities {
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
            }
        }
    }

    /// A to-one relationship can always be nil at sync time, so CloudKit requires every one of them
    /// to be optional.
    @Test("Every relationship is optional")
    func relationshipsAreOptional() {
        for entity in entities {
            for relationship in entity.relationships {
                #expect(
                    relationship.isOptional,
                    "\(entity.name).\(relationship.name) is not optional"
                )
            }
        }
    }

    /// Relationships without an inverse are unsupported. This is why `MatchSide.match` and
    /// `ScoreEvent.match` exist at all, and why `Player`/`Team` carry `matchAppearances`.
    @Test("Every relationship declares an inverse")
    func relationshipsDeclareInverses() {
        for entity in entities {
            for relationship in entity.relationships {
                #expect(
                    relationship.inverseName != nil,
                    "\(entity.name).\(relationship.name) has no declared inverse"
                )
            }
        }
    }

    /// Only `.cascade` and `.nullify` are supported.
    @Test("No .deny delete rules")
    func noDenyDeleteRules() {
        for entity in entities {
            for relationship in entity.relationships {
                #expect(
                    relationship.deleteRule != .deny,
                    "\(entity.name).\(relationship.name) uses .deny"
                )
            }
        }
    }

    /// History must outlive the roster: deleting a team or player nullifies its link to past
    /// matches rather than cascading the matches away with it.
    @Test("Match appearances nullify rather than cascade")
    func matchAppearancesNullify() throws {
        for entityName in ["Player", "Team"] {
            let entity = try #require(entities.first { $0.name == entityName })
            let appearances = try #require(
                entity.relationships.first { $0.name == "matchAppearances" }
            )
            #expect(appearances.deleteRule == .nullify)
        }
    }

    /// The store opens, every model materialises, and nothing is seeded — the 37 built-ins are
    /// bundled data, not rows (§7.4).
    @Test("Container opens with an empty store")
    @MainActor
    func containerOpensEmpty() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        #expect(try context.fetchCount(FetchDescriptor<UserGamePreset>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PresetPreference>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ThemePreset>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Match>()) == 0)
    }

    /// Every Codable blob must survive an actual save/fetch cycle.
    ///
    /// `containerOpensEmpty` passing is *not* sufficient: SwiftData accepts a `Codable` property
    /// into the schema and only traps when a value is written. Storing `AnyRuleSet` directly
    /// compiled, opened the store, and validated against CloudKit — then crashed on the first save
    /// with "unknown property payload for composite description". Hence `CodableBlob`, and hence
    /// this test writing real values rather than only opening the store.
    @Test("Codable blobs round-trip through a real save")
    @MainActor
    func codableBlobsRoundTrip() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        var rules = TeamRules()
        rules.periodCount = 4
        rules.shotClockEnabled = true
        rules.bonusThreshold = 5

        let match = Match(
            presetSlug: "basketball",
            rulesSnapshot: .team(rules),
            themeSnapshot: BuiltInThemes.theme(id: "amber"),
            title: "Round 3"
        )
        context.insert(match)
        context.insert(UserGamePreset(name: "My league", rules: .team(rules)))
        context.insert(ThemePreset(id: "custom", name: "Custom", spec: BuiltInThemes.theme(id: "neon")))

        try context.save()

        let fetched = try #require(try context.fetch(FetchDescriptor<Match>()).first)
        #expect(fetched.rulesSnapshot?.teamRules == rules)
        #expect(fetched.themeSnapshot?.id == "amber")

        let fetchedPreset = try #require(try context.fetch(FetchDescriptor<UserGamePreset>()).first)
        #expect(fetchedPreset.rules?.teamRules?.bonusThreshold == 5)

        let fetchedTheme = try #require(try context.fetch(FetchDescriptor<ThemePreset>()).first)
        #expect(fetchedTheme.spec?.id == "neon")
    }

    /// Deleting a team keeps the match it played in, with the side's snapshotted identity intact.
    @Test("Deleting a team preserves match history")
    @MainActor
    func deletingTeamPreservesHistory() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let team = Team(name: "Wolves", shortName: "WOL", emoji: "🐺", primaryColorHex: "#2E7D32")
        let match = Match(presetSlug: "basketball", status: .finished)
        let side = MatchSide.from(team: team, slotIndex: 0)
        side.finalScore = 62
        side.match = match

        context.insert(team)
        context.insert(match)
        context.insert(side)
        try context.save()

        context.delete(team)
        try context.save()

        let matches = try context.fetch(FetchDescriptor<Match>())
        #expect(matches.count == 1)

        let survivor = try #require(matches.first?.orderedSides.first)
        #expect(survivor.linkedTeam == nil)
        // Identity was copied at kickoff, so the finished match still renders correctly.
        #expect(survivor.displayName == "Wolves")
        #expect(survivor.emoji == "🐺")
        #expect(survivor.colorHex == "#2E7D32")
        #expect(survivor.finalScore == 62)
    }

    /// Deleting a match takes its sides and events with it — that side is cascade.
    @Test("Deleting a match cascades to sides and events")
    @MainActor
    func deletingMatchCascades() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)

        let match = Match(presetSlug: "soccer", status: .finished)
        let side = MatchSide(slotIndex: 0, displayName: "Home")
        side.match = match
        let event = ScoreEvent(index: 0, kind: .score, slotIndex: 0, value: 1)
        event.match = match

        context.insert(match)
        context.insert(side)
        context.insert(event)
        try context.save()

        context.delete(match)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<MatchSide>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ScoreEvent>()) == 0)
    }
}
