import Foundation
import Testing

@testable import ScoreDock

/// The M0 exit criterion is "all 37 presets browsable". This is what proves it.
@Suite("Built-in catalog (§7.4, §8)")
struct CatalogTests {
    private let presets = BuiltInCatalog.presets

    @Test("The bundled catalog decodes")
    func catalogDecodes() throws {
        // Guards the graceful-degradation path in `BuiltInCatalog.presets`: if this passes, that
        // path is unreachable in a correctly built app.
        let loaded = try BuiltInCatalog.load()
        #expect(loaded.count == 37)
    }

    @Test("Thirty-seven presets, in the documented distribution")
    func presetCounts() {
        #expect(presets.count == 37)
        #expect(presets.count { $0.engine == .team } == 20)
        #expect(presets.count { $0.engine == .setMatch } == 8)
        #expect(presets.count { $0.engine == .specialised } == 5)
        #expect(presets.count { $0.engine == .list } == 4)
    }

    @Test("Slugs are unique")
    func slugsAreUnique() {
        #expect(Set(presets.map(\.slug)).count == presets.count)
        #expect(BuiltInCatalog.bySlug.count == presets.count)
    }

    /// The slugs §8 names explicitly. A rename here silently orphans every `Match.presetSlug` and
    /// `PresetPreference.slug` already written, so it should be a deliberate, visible change.
    @Test("Documented slugs are present")
    func documentedSlugs() {
        let required = [
            "custom-scoreboard", "soccer", "basketball-nba", "basketball", "ice-hockey",
            "field-hockey", "handball", "rugby", "waterpolo", "futsal", "lacrosse", "netball",
            "boxing", "wrestling", "kabaddi", "simple", "basketball-shot-clock", "stopwatch",
            "half-time-clock", "click-counter",
            "match", "tennis", "table-tennis-ping-pong", "badminton", "volleyball", "squash",
            "pickleball", "darts",
            "american-football", "cricket", "baseball", "chess-clock", "race-timer",
            "leaderboard", "standings", "tournament", "scoresheet",
        ]
        for slug in required {
            #expect(BuiltInCatalog.bySlug[slug] != nil, "missing preset: \(slug)")
        }
    }

    @Test("Every preset ships both locales (§10)")
    func localisedNames() {
        for preset in presets {
            #expect(preset.localizedNames["en"]?.isEmpty == false, "\(preset.slug) has no English name")
            #expect(preset.localizedNames["he"]?.isEmpty == false, "\(preset.slug) has no Hebrew name")
        }
    }

    @Test("Every preset names a real theme and carries an emoji")
    func presetPresentation() {
        for preset in presets {
            #expect(
                BuiltInThemes.byID[preset.defaultThemeID] != nil,
                "\(preset.slug) references unknown theme \(preset.defaultThemeID)"
            )
            #expect(!preset.emoji.isEmpty, "\(preset.slug) has no emoji")
        }
    }

    @Test("Rule payloads match their declared engine")
    func rulesMatchEngine() {
        for preset in presets {
            #expect(
                preset.rules.engine == preset.engine,
                "\(preset.slug) declares \(preset.engine) but carries \(preset.rules.engine) rules"
            )
        }
    }

    @Test("Every preset produces a non-empty rule summary")
    func ruleSummaries() {
        for preset in presets {
            #expect(
                !RuleSummary.rows(for: preset.rules).isEmpty,
                "\(preset.slug) summarises to nothing"
            )
        }
    }

    /// Sanity checks on the headline parameters §8.1–8.4 confirm. These are the values a referee
    /// would notice immediately if they were wrong.
    @Test("Confirmed headline parameters are correct")
    func headlineParameters() throws {
        func teamRules(_ slug: String) throws -> TeamRules {
            try #require(BuiltInCatalog.bySlug[slug]?.rules.teamRules, "\(slug) is not a team preset")
        }

        let soccer = try teamRules("soccer")
        #expect(soccer.periodCount == 2)
        #expect(soccer.periodLength == 45 * 60)
        #expect(soccer.countsUp)

        let nba = try teamRules("basketball-nba")
        #expect(nba.periodCount == 4)
        #expect(nba.periodLength == 12 * 60)
        #expect(nba.shotClockFull == 24)
        #expect(nba.shotClockShort == 14)

        let fiba = try teamRules("basketball")
        #expect(fiba.periodCount == 4)
        #expect(fiba.periodLength == 10 * 60)
        #expect(fiba.possessionArrowEnabled)

        let hockey = try teamRules("ice-hockey")
        #expect(hockey.periodCount == 3)
        #expect(hockey.periodLength == 20 * 60)

        let waterPolo = try teamRules("waterpolo")
        #expect(waterPolo.periodCount == 4)
        #expect(waterPolo.periodLength == 8 * 60)
        #expect(waterPolo.shotClockFull == 30)

        let volleyball = try #require(BuiltInCatalog.bySlug["volleyball"]?.rules.setMatchRules)
        #expect(volleyball.setsToWin == 3)
        #expect(volleyball.pointsPerSet == 25)
        #expect(volleyball.decidingSetPoints == 15)

        let badminton = try #require(BuiltInCatalog.bySlug["badminton"]?.rules.setMatchRules)
        #expect(badminton.pointsPerSet == 21)
        #expect(badminton.hardCap == 30)

        let tennis = try #require(BuiltInCatalog.bySlug["tennis"]?.rules.setMatchRules)
        #expect(tennis.notation == .tennis)
        #expect(tennis.tiebreakPoints == 7)

        let darts = try #require(BuiltInCatalog.bySlug["darts"]?.rules.setMatchRules)
        #expect(darts.notation == .dartsCountdown)
        #expect(darts.startScore == 501)
    }

    @Test("Score increments always offer at least one option")
    func scoreIncrements() {
        for preset in presets {
            guard let rules = preset.rules.teamRules else { continue }
            #expect(!rules.scoreIncrements.isEmpty, "\(preset.slug) has no score buttons")
            let allPositive = rules.scoreIncrements.allSatisfy { $0 > 0 }
            #expect(allPositive, "\(preset.slug) has a non-positive increment")
        }
    }

    /// §8.5 forbids guessing. Every value must therefore be *either* cited *or* explicitly flagged
    /// for review — silence is the failure mode this catches.
    @Test("Every source entry carries a citation")
    func sourcesAreCited() {
        for preset in presets {
            #expect(!preset.sources.isEmpty, "\(preset.slug) records no provenance at all")
            for (key, source) in preset.sources {
                #expect(!source.cite.isEmpty, "\(preset.slug).\(key) has an empty citation")
            }
        }
    }

    /// Not an assertion of zero — it is a visible count of what still has to be checked against a
    /// governing body before submission (§8.5, §17 risk 5). Tighten this number as they are cleared.
    @Test("Unverified rule values are tracked, not hidden")
    func unverifiedValuesAreTracked() {
        let flagged = presets.filter { !$0.unverifiedRuleKeys.isEmpty }
        let total = presets.reduce(0) { $0 + $1.unverifiedRuleKeys.count }

        #expect(total == 25, "the needsReview count changed — update this test deliberately")
        #expect(flagged.count == 16)

        // Anything with no flags at all should genuinely be settled, not merely unexamined.
        for preset in presets where preset.unverifiedRuleKeys.isEmpty {
            #expect(!preset.sources.isEmpty, "\(preset.slug) claims to be verified but cites nothing")
        }
    }
}
