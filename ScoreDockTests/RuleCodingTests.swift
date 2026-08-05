import Foundation
import Testing

@testable import ScoreDock

/// §7.3's promise is that adding a rule is a versioned decoder change rather than a store
/// migration. These tests hold that promise to account.
@Suite("Rule coding (§7.3)")
struct RuleCodingTests {
    private func roundTrip(_ rules: AnyRuleSet) throws -> AnyRuleSet {
        let data = try JSONEncoder().encode(rules)
        return try JSONDecoder().decode(AnyRuleSet.self, from: data)
    }

    @Test("Every engine round-trips unchanged")
    func roundTripsAllEngines() throws {
        var team = TeamRules()
        team.periodCount = 3
        team.shotClockEnabled = true
        team.bonusThreshold = 4
        team.possessionLabel = "POSS"

        var setMatch = SetMatchRules()
        setMatch.hardCap = 30
        setMatch.notation = .tennis

        var list = ListRules()
        list.style = .standings
        list.columns = [.played, .points]

        var specialised = SpecialisedRules(board: .cricket)
        specialised.cricket = CricketRules()

        for original in [
            AnyRuleSet.team(team),
            .setMatch(setMatch),
            .list(list),
            .specialised(specialised),
        ] {
            #expect(try roundTrip(original) == original)
        }
    }

    @Test("Every built-in preset's rules round-trip")
    func catalogRulesRoundTrip() throws {
        for preset in BuiltInCatalog.presets {
            #expect(try roundTrip(preset.rules) == preset.rules, "\(preset.slug) did not round-trip")
        }
    }

    /// The core §7.3 guarantee: a blob written by an older build, missing keys a newer build knows
    /// about, decodes to the documented defaults instead of throwing.
    @Test("A payload missing new fields decodes to defaults")
    func missingFieldsDecodeToDefaults() throws {
        let sparse = Data(#"{"version":1,"engine":"team","payload":{"periodCount":2}}"#.utf8)
        let decoded = try JSONDecoder().decode(AnyRuleSet.self, from: sparse)
        let rules = try #require(decoded.teamRules)

        #expect(rules.periodCount == 2)
        // Everything else falls back rather than failing.
        #expect(rules.periodLength == TeamRules().periodLength)
        #expect(rules.shotClockFull == TeamRules().shotClockFull)
        #expect(rules.scoreIncrements == TeamRules().scoreIncrements)
    }

    @Test("An entirely empty payload still decodes")
    func emptyPayloadDecodes() throws {
        let empty = Data(#"{"version":1,"engine":"setMatch","payload":{}}"#.utf8)
        let decoded = try JSONDecoder().decode(AnyRuleSet.self, from: empty)
        #expect(decoded.setMatchRules == SetMatchRules())
    }

    /// A blob written before the envelope carried a version.
    @Test("A payload with no version is treated as version 1")
    func missingVersionDefaultsToOne() throws {
        let legacy = Data(#"{"engine":"team","payload":{"periodCount":4}}"#.utf8)
        let decoded = try JSONDecoder().decode(AnyRuleSet.self, from: legacy)
        #expect(decoded.teamRules?.periodCount == 4)
    }

    /// Forward incompatibility is reported clearly rather than crashing or silently mis-decoding —
    /// the caller can then tell the user their match was saved by a newer version.
    @Test("A future format version is refused with a legible error")
    func futureVersionThrows() {
        let future = Data(#"{"version":99,"engine":"team","payload":{}}"#.utf8)
        #expect(throws: AnyRuleSet.DecodingProblem.self) {
            try JSONDecoder().decode(AnyRuleSet.self, from: future)
        }
    }

    /// Consistent with storing enums as raw strings (§7.5): an unknown value degrades rather than
    /// failing to decode.
    @Test("An unknown engine degrades to the fallback")
    func unknownEngineFallsBack() throws {
        let unknown = Data(#"{"version":1,"engine":"quidditch","payload":{"periodCount":7}}"#.utf8)
        let decoded = try JSONDecoder().decode(AnyRuleSet.self, from: unknown)
        #expect(decoded.engine == EngineKind.fallback)
        #expect(decoded.teamRules?.periodCount == 7)
    }

    @Test("Unknown standings columns are dropped, not fatal")
    func unknownColumnsAreDropped() throws {
        let payload = Data(
            #"{"version":1,"engine":"list","payload":{"style":"standings","columns":["played","teleports","points"]}}"#.utf8
        )
        let decoded = try JSONDecoder().decode(AnyRuleSet.self, from: payload)
        #expect(decoded.listRules?.columns == [.played, .points])
    }

    // MARK: Stored-enum degradation

    @Test("Unknown stored enum values fall back rather than trapping")
    func storedEnumFallbacks() {
        #expect(EngineKind(storedRaw: "nonsense") == .team)
        #expect(EngineKind(storedRaw: nil) == .team)
        #expect(IdentityMark(storedRaw: "nonsense") == .initials)
        #expect(MatchStatus(storedRaw: "nonsense") == .setup)
        #expect(EventKind(storedRaw: "nonsense") == .correction)
        #expect(SideOutcome(storedRaw: "nonsense") == .unfinished)
        #expect(PeriodLabelStyle(storedRaw: "nonsense") == .period)

        // Known values still decode normally.
        #expect(EngineKind(storedRaw: "setMatch") == .setMatch)
        #expect(EventKind(storedRaw: "periodAdvance") == .periodAdvance)
    }

    // MARK: Period labelling

    @Test("Period labels cover regulation, overtime and custom")
    func periodLabels() {
        var rules = TeamRules()
        rules.periodLabelStyle = .quarter
        rules.periodCount = 4
        #expect(rules.label(forPeriod: 1) == "Q1")
        #expect(rules.label(forPeriod: 4) == "Q4")
        #expect(rules.label(forPeriod: 5) == "OT")

        rules.periodLabelStyle = .custom
        rules.customPeriodLabels = ["First", "Second"]
        rules.periodCount = 2
        #expect(rules.label(forPeriod: 1) == "First")
        #expect(rules.label(forPeriod: 2) == "Second")
        // Past the supplied labels it still returns something sensible.
        #expect(rules.label(forPeriod: 3) == "OT")
    }

    @Test("Tenths appear only below the configured threshold")
    func tenthsThreshold() {
        var rules = TeamRules()
        rules.showTenths = true
        rules.tenthsThreshold = 60

        #expect(rules.showsTenths(atRemaining: 59))
        #expect(!rules.showsTenths(atRemaining: 60))
        #expect(!rules.showsTenths(atRemaining: 600))

        rules.showTenths = false
        #expect(!rules.showsTenths(atRemaining: 1))
    }
}
