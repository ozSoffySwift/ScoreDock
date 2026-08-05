import Foundation
import Testing

@testable import ScoreDock

/// §6.5. Four boards over one engine, so each style gets its own section — and the bracket gets the
/// most, because flat index arithmetic over a tree is the part most likely to be quietly wrong.
@Suite("List and table engine (§6.5)")
struct ListEngineTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.t0.addingTimeInterval(seconds) }

    private func rules(_ slug: String) throws -> ListRules {
        try #require(BuiltInCatalog.bySlug[slug]?.rules.listRules)
    }

    private func apply(
        _ action: EngineAction,
        _ state: inout ListState,
        _ rules: ListRules
    ) {
        ListEngine.apply(action, to: &state, rules: rules, at: at(0))
    }

    private func board(_ state: ListState, _ rules: ListRules) -> DerivedListBoard {
        ListEngine.derived(state, rules: rules, at: at(0))
    }

    // MARK: - Leaderboard

    @Test("Leaderboard totals accumulate and rank highest first")
    func leaderboardRanking() throws {
        let rules = try rules("leaderboard")
        var state = ListEngine.initialState(rules: rules, sideCount: 3)

        apply(.score(slot: 0, points: 10), &state, rules)
        apply(.score(slot: 1, points: 25), &state, rules)
        apply(.score(slot: 2, points: 5), &state, rules)

        let rows = board(state, rules).rows
        #expect(rows.map(\.slotIndex) == [1, 0, 2], "sorted into display order")
        #expect(rows.map(\.rank) == [1, 2, 3])
        #expect(rows.map(\.total) == [25, 10, 5])
    }

    /// §6.5 wants ties "handled explicitly": they share a position *and* are flagged, so the board
    /// can say so rather than silently picking an order.
    @Test("Tied leaderboard entries share a rank and are marked")
    func leaderboardTies() throws {
        let rules = try rules("leaderboard")
        var state = ListEngine.initialState(rules: rules, sideCount: 3)

        apply(.score(slot: 0, points: 10), &state, rules)
        apply(.score(slot: 1, points: 10), &state, rules)
        apply(.score(slot: 2, points: 4), &state, rules)

        let rows = board(state, rules).rows
        // Standard competition ranking: two firsts, then third — not second.
        #expect(rows.map(\.rank) == [1, 1, 3])
        #expect(rows[0].isTiedRank)
        #expect(rows[1].isTiedRank)
        #expect(!rows[2].isTiedRank)
    }

    @Test("Lowest-first ranking suits golf and race times")
    func leaderboardLowestFirst() throws {
        var rules = try rules("leaderboard")
        rules.higherIsBetter = false
        var state = ListEngine.initialState(rules: rules, sideCount: 3)

        apply(.score(slot: 0, points: 72), &state, rules)
        apply(.score(slot: 1, points: 68), &state, rules)
        apply(.score(slot: 2, points: 75), &state, rules)

        #expect(board(state, rules).rows.map(\.slotIndex) == [1, 0, 2])
    }

    @Test("A tie order is stable rather than shuffling between refreshes")
    func leaderboardTieOrderIsStable() throws {
        let rules = try rules("leaderboard")
        var state = ListEngine.initialState(rules: rules, sideCount: 4)
        for slot in 0 ..< 4 { apply(.score(slot: slot, points: 7), &state, rules) }

        let first = board(state, rules).rows.map(\.slotIndex)
        let second = board(state, rules).rows.map(\.slotIndex)
        #expect(first == second)
        #expect(first == [0, 1, 2, 3], "falls back to entry order")
    }

    // MARK: - Standings

    @Test("Standings points come from the record and the configured values")
    func standingsPoints() throws {
        let rules = try rules("standings")
        #expect(rules.pointsForWin == 3)

        var state = ListEngine.initialState(rules: rules, sideCount: 2)
        apply(.adjustRecord(slot: 0, field: .won, delta: 3), &state, rules)
        apply(.adjustRecord(slot: 0, field: .drawn, delta: 1), &state, rules)
        apply(.adjustRecord(slot: 0, field: .lost, delta: 1), &state, rules)

        let row = try #require(board(state, rules).rows.first { $0.slotIndex == 0 })
        #expect(row.played == 5)
        #expect(row.points == 10, "3 wins x 3 + 1 draw x 1")
    }

    /// Played, goal difference and points are computed, never stored — so they cannot drift out of
    /// step with the results that produced them.
    @Test("Goal difference is derived, not entered")
    func standingsGoalDifference() throws {
        let rules = try rules("standings")
        var state = ListEngine.initialState(rules: rules, sideCount: 2)

        apply(.adjustRecord(slot: 0, field: .goalsFor, delta: 12), &state, rules)
        apply(.adjustRecord(slot: 0, field: .goalsAgainst, delta: 4), &state, rules)

        let row = try #require(board(state, rules).rows.first { $0.slotIndex == 0 })
        #expect(row.goalDifference == 8)
        #expect(row.value(for: .goalDifference) == 8)
    }

    @Test("Standings sort on points, then goal difference, then goals scored")
    func standingsOrdering() throws {
        let rules = try rules("standings")
        var state = ListEngine.initialState(rules: rules, sideCount: 3)

        // All three on 3 points; separated only by GD, then GF.
        for slot in 0 ..< 3 { apply(.adjustRecord(slot: slot, field: .won, delta: 1), &state, rules) }
        apply(.adjustRecord(slot: 0, field: .goalsFor, delta: 2), &state, rules)   // GD +2
        apply(.adjustRecord(slot: 1, field: .goalsFor, delta: 5), &state, rules)   // GD +5
        apply(.adjustRecord(slot: 2, field: .goalsFor, delta: 5), &state, rules)
        apply(.adjustRecord(slot: 2, field: .goalsAgainst, delta: 3), &state, rules) // GD +2, GF 5

        let order = board(state, rules).rows.map(\.slotIndex)
        #expect(order == [1, 2, 0], "GD first, then goals scored breaks the +2 tie")
    }

    @Test("Records never go negative")
    func standingsFloor() throws {
        let rules = try rules("standings")
        var state = ListEngine.initialState(rules: rules, sideCount: 2)
        apply(.adjustRecord(slot: 0, field: .won, delta: -5), &state, rules)
        #expect(state.entries[0].won == 0)
    }

    // MARK: - Bracket

    @Test("A bracket of eight has seven matches over three rounds")
    func bracketShape() throws {
        var rules = try rules("tournament")
        rules.bracketSize = 8
        let state = ListEngine.initialState(rules: rules, sideCount: 8)
        let bracket = try #require(state.bracket)

        #expect(bracket.size == 8)
        #expect(bracket.winners.count == 7)
        #expect(bracket.roundCount == 3)
        #expect(bracket.matchCount(inRound: 0) == 4)
        #expect(bracket.matchCount(inRound: 1) == 2)
        #expect(bracket.matchCount(inRound: 2) == 1)
        #expect(bracket.firstMatchIndex(inRound: 1) == 4)
        #expect(bracket.firstMatchIndex(inRound: 2) == 6)
    }

    @Test("A non-power-of-two size rounds up, leaving byes")
    func bracketRoundsUp() {
        #expect(BracketState(size: 5).size == 8)
        #expect(BracketState(size: 12).size == 16)
        #expect(BracketState(size: 1).size == 2)
    }

    @Test("First-round pairs follow the listed order")
    func bracketFirstRoundPairs() throws {
        var rules = try rules("tournament")
        rules.bracketSize = 8
        let state = ListEngine.initialState(rules: rules, sideCount: 8)
        let bracket = try #require(state.bracket)

        #expect(bracket.participants(inMatch: 0) == (0, 1))
        #expect(bracket.participants(inMatch: 1) == (2, 3))
        #expect(bracket.participants(inMatch: 3) == (6, 7))
    }

    @Test("A winner feeds the correct next-round match")
    func bracketAdvances() throws {
        var rules = try rules("tournament")
        rules.bracketSize = 8
        var state = ListEngine.initialState(rules: rules, sideCount: 8)

        apply(.setBracketWinner(match: 0, slot: 0), &state, rules)
        apply(.setBracketWinner(match: 1, slot: 3), &state, rules)

        let bracket = try #require(state.bracket)
        // Match 4 is the first of round 1, fed by matches 0 and 1.
        #expect(bracket.participants(inMatch: 4) == (0, 3))
    }

    /// Changing an earlier result must not leave a stale finalist standing in a later round.
    @Test("Changing a result clears everything downstream of it")
    func bracketClearsDownstream() throws {
        var rules = try rules("tournament")
        rules.bracketSize = 8
        var state = ListEngine.initialState(rules: rules, sideCount: 8)

        // Fill a path to the final.
        apply(.setBracketWinner(match: 0, slot: 0), &state, rules)
        apply(.setBracketWinner(match: 1, slot: 2), &state, rules)
        apply(.setBracketWinner(match: 4, slot: 0), &state, rules)
        apply(.setBracketWinner(match: 6, slot: 0), &state, rules)
        #expect(state.bracket?.winners[6] == 0)

        // Revisit the very first match.
        apply(.setBracketWinner(match: 0, slot: 1), &state, rules)

        let bracket = try #require(state.bracket)
        #expect(bracket.winners[0] == 1)
        #expect(bracket.winners[4] == nil, "the semi it fed is cleared")
        #expect(bracket.winners[6] == nil, "and so is the final")
        #expect(bracket.winners[1] == 2, "an unrelated match is untouched")
    }

    @Test("An unfilled place is a bye and advances on its own")
    func bracketByes() throws {
        var rules = try rules("tournament")
        rules.bracketSize = 8
        // Five entrants in an eight-place bracket.
        var state = ListEngine.initialState(rules: rules, sideCount: 5)
        state.bracket = BracketState(size: 8)

        let matches = board(state, rules).bracketMatches
        let third = try #require(matches.first { $0.index == 2 })   // pairs slots 4 and 5

        #expect(third.isBye)
        #expect(third.upperSlot == 4)
        #expect(third.lowerSlot == nil, "slot 5 has no entrant")
        #expect(third.winnerSlot == 4, "the lone entrant advances unplayed")

        // An entirely empty place is *not* a bye — it is the unused half of an oversized bracket.
        // Labelling it "BYE" on the board (which it was) claims a walkover for nobody.
        let fourth = try #require(matches.first { $0.index == 3 })   // pairs slots 6 and 7
        #expect(!fourth.isBye)
        #expect(fourth.upperSlot == nil)
        #expect(fourth.lowerSlot == nil)
        #expect(fourth.winnerSlot == nil, "an empty place produces no winner")
    }

    @Test("The final's winner is the champion")
    func bracketChampion() throws {
        var rules = try rules("tournament")
        rules.bracketSize = 4
        var state = ListEngine.initialState(rules: rules, sideCount: 4)

        apply(.setBracketWinner(match: 0, slot: 1), &state, rules)
        apply(.setBracketWinner(match: 1, slot: 2), &state, rules)
        #expect(board(state, rules).champion == nil, "the final has not been played")

        apply(.setBracketWinner(match: 2, slot: 1), &state, rules)
        #expect(board(state, rules).champion == 1)

        apply(.finishMatch, &state, rules)
        let result = try #require(ListEngine.outcome(state, rules: rules, at: at(0)))
        #expect(result.winningSlots == [1])
        #expect(result.outcome(forSlot: 1) == .win)
    }

    // MARK: - Score sheet

    @Test("Score sheet points land in the current round")
    func scoreSheetRounds() throws {
        var rules = try rules("scoresheet")
        rules.roundCount = 3
        var state = ListEngine.initialState(rules: rules, sideCount: 2)

        apply(.score(slot: 0, points: 5), &state, rules)
        apply(.advancePeriod, &state, rules)
        apply(.score(slot: 0, points: 8), &state, rules)

        #expect(state.entries[0].rounds == [5, 8, 0])
        #expect(state.currentRound == 1)
    }

    /// The total is always the sum of the rounds, never a separate number — so the two can never
    /// disagree, which is the failure a paper score sheet actually has.
    @Test("The total is always the sum of the rounds")
    func scoreSheetTotalIsDerived() throws {
        var rules = try rules("scoresheet")
        rules.roundCount = 4
        var state = ListEngine.initialState(rules: rules, sideCount: 1)

        apply(.score(slot: 0, points: 3), &state, rules)
        apply(.advancePeriod, &state, rules)
        apply(.score(slot: 0, points: 7), &state, rules)
        apply(.score(slot: 0, points: -2), &state, rules)

        #expect(state.entries[0].rounds == [3, 5, 0, 0])
        #expect(state.entries[0].total == 8)
    }

    @Test("Round navigation stays inside the sheet")
    func scoreSheetRoundBounds() throws {
        var rules = try rules("scoresheet")
        rules.roundCount = 2
        var state = ListEngine.initialState(rules: rules, sideCount: 2)

        apply(.previousPeriod, &state, rules)
        #expect(state.currentRound == 0, "cannot go before the first round")

        apply(.advancePeriod, &state, rules)
        apply(.advancePeriod, &state, rules)
        #expect(state.currentRound == 1, "cannot go past the last")
    }

    // MARK: - Cross-cutting

    @Test("Actions from other engines are ignored rather than mis-applied")
    func ignoresForeignActions() throws {
        let rules = try rules("leaderboard")
        var state = ListEngine.initialState(rules: rules, sideCount: 2)
        let before = state

        // A replayed log from another engine must not corrupt this state.
        apply(.toggleClock, &state, rules)
        apply(.foul(slot: 0, delta: 1), &state, rules)
        apply(.resetShotClock(full: true), &state, rules)
        apply(.startBreak(600), &state, rules)

        #expect(state == before)
    }

    @Test("A finished board ignores further changes")
    func finishedIsImmutable() throws {
        let rules = try rules("leaderboard")
        var state = ListEngine.initialState(rules: rules, sideCount: 2)
        apply(.score(slot: 0, points: 5), &state, rules)
        apply(.finishMatch, &state, rules)

        apply(.score(slot: 0, points: 99), &state, rules)
        #expect(state.entries[0].total == 5)
    }

    @Test("Bracket and record actions survive the event round trip")
    func actionCoding() {
        let cases: [EngineAction] = [
            .setBracketWinner(match: 4, slot: 2),
            .setBracketWinner(match: 0, slot: nil),
            .adjustRecord(slot: 1, field: .won, delta: 1),
            .adjustRecord(slot: 0, field: .goalsAgainst, delta: -1),
        ]

        for action in cases {
            let rebuilt = EngineAction.from(
                kind: action.eventKind,
                slotIndex: action.eventSlotIndex,
                value: action.eventValue,
                playerID: action.eventPlayerID,
                note: action.eventNote
            )
            #expect(rebuilt == action, "\(action) did not round-trip")
        }
    }

    @Test("State survives a Codable round trip")
    func stateRoundTrip() throws {
        var rules = try rules("tournament")
        rules.bracketSize = 4
        var state = ListEngine.initialState(rules: rules, sideCount: 4)
        apply(.setBracketWinner(match: 0, slot: 1), &state, rules)

        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(ListState.self, from: data) == state)
    }

    @Test("All four styles derive a board without crashing")
    func allStylesRender() throws {
        for slug in ["leaderboard", "standings", "tournament", "scoresheet"] {
            let rules = try rules(slug)
            var state = ListEngine.initialState(rules: rules, sideCount: 4)
            apply(.score(slot: 0, points: 3), &state, rules)
            let derived = board(state, rules)
            #expect(derived.style == rules.style)
            #expect(derived.rows.count == 4)
        }
    }
}
