import Foundation
import Testing

@testable import ScoreDock

/// §6.2. The M4 exit criterion is "tennis and volleyball matches run correctly", so those two get
/// the most attention — but all three notations are exercised, because they share one engine and a
/// change to any of them can break the others.
@Suite("Set-match engine (§6.2)")
struct SetMatchEngineTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.t0.addingTimeInterval(seconds) }

    private func rules(_ slug: String) throws -> SetMatchRules {
        try #require(BuiltInCatalog.bySlug[slug]?.rules.setMatchRules)
    }

    private func newState(_ rules: SetMatchRules) -> SetMatchState {
        SetMatchEngine.initialState(rules: rules, sideCount: 2)
    }

    /// Awards `count` points to `slot`, one at a time — rally scoring never jumps.
    private func award(
        _ count: Int,
        to slot: Int,
        _ state: inout SetMatchState,
        _ rules: SetMatchRules
    ) {
        for _ in 0 ..< count {
            SetMatchEngine.apply(.score(slot: slot, points: 1), to: &state, rules: rules, at: at(0))
        }
    }

    private func points(_ state: SetMatchState, _ rules: SetMatchRules, _ slot: Int) -> String {
        SetMatchEngine.pointsText(state, rules: rules, slot: slot)
    }

    // MARK: - Volleyball

    @Test("Volleyball: a set is won at 25 with a two-point margin")
    func volleyballSet() throws {
        let rules = try rules("volleyball")
        var state = newState(rules)

        award(24, to: 0, &state, rules)
        award(20, to: 1, &state, rules)
        #expect(state.sides[0].setsWon == 0)

        award(1, to: 0, &state, rules)
        #expect(state.sides[0].setsWon == 1)
        #expect(state.completedSets == [[25, 20]], "the set score is kept for the history strip")
        #expect(state.sides[0].points == 0, "points reset for the next set")
    }

    @Test("Volleyball: 24-all runs on until someone leads by two")
    func volleyballDeuce() throws {
        let rules = try rules("volleyball")
        var state = newState(rules)

        award(24, to: 0, &state, rules)
        award(24, to: 1, &state, rules)

        award(1, to: 0, &state, rules)   // 25-24 — not enough
        #expect(state.sides[0].setsWon == 0)

        award(1, to: 1, &state, rules)   // 25-25
        award(1, to: 1, &state, rules)   // 26-25 — still not enough
        #expect(state.sides[1].setsWon == 0)

        award(1, to: 1, &state, rules)   // 27-25
        #expect(state.sides[1].setsWon == 1)
        #expect(state.completedSets == [[25, 27]])
    }

    /// §8 confirms the deciding fifth set is played to 15, not 25.
    @Test("Volleyball: the deciding set is to 15")
    func volleyballDecidingSet() throws {
        let rules = try rules("volleyball")
        var state = newState(rules)
        state.sides[0].setsWon = 2
        state.sides[1].setsWon = 2

        #expect(SetMatchEngine.isDecidingSet(state, rules: rules))

        award(15, to: 0, &state, rules)
        award(10, to: 1, &state, rules)
        #expect(state.sides[0].setsWon == 3)
        #expect(state.isFinished, "three sets takes the match")
    }

    @Test("Volleyball: best of five needs three sets")
    func volleyballMatch() throws {
        let rules = try rules("volleyball")
        var state = newState(rules)

        for _ in 0 ..< 3 {
            award(25, to: 0, &state, rules)
        }
        #expect(state.sides[0].setsWon == 3)
        #expect(state.isFinished)

        // A finished match ignores further points.
        award(5, to: 1, &state, rules)
        #expect(state.sides[1].points == 0)
    }

    // MARK: - Tennis

    @Test("Tennis: points read 0, 15, 30, 40")
    func tennisPointNames() throws {
        let rules = try rules("tennis")
        var state = newState(rules)

        #expect(points(state, rules, 0) == "0")
        award(1, to: 0, &state, rules); #expect(points(state, rules, 0) == "15")
        award(1, to: 0, &state, rules); #expect(points(state, rules, 0) == "30")
        award(1, to: 0, &state, rules); #expect(points(state, rules, 0) == "40")
    }

    @Test("Tennis: a game is won from 40 with two clear points")
    func tennisGame() throws {
        let rules = try rules("tennis")
        var state = newState(rules)

        award(4, to: 0, &state, rules)
        #expect(state.sides[0].gamesWon == 1)
        #expect(state.sides[0].points == 0)
    }

    /// Deuce and advantage are not special-cased — they fall out of "win by two".
    @Test("Tennis: deuce, advantage, and back to deuce")
    func tennisDeuce() throws {
        let rules = try rules("tennis")
        var state = newState(rules)

        award(3, to: 0, &state, rules)
        award(3, to: 1, &state, rules)
        #expect(points(state, rules, 0) == "40")
        #expect(points(state, rules, 1) == "40", "deuce")

        award(1, to: 0, &state, rules)
        #expect(points(state, rules, 0) == "AD")
        #expect(points(state, rules, 1) == "40")
        #expect(state.sides[0].gamesWon == 0, "advantage is not a game")

        award(1, to: 1, &state, rules)
        #expect(points(state, rules, 0) == "40")
        #expect(points(state, rules, 1) == "40", "back to deuce")

        award(2, to: 1, &state, rules)
        #expect(state.sides[1].gamesWon == 1)
    }

    @Test("Tennis: a set is won at six games by two")
    func tennisSet() throws {
        let rules = try rules("tennis")
        var state = newState(rules)

        for _ in 0 ..< 6 { award(4, to: 0, &state, rules) }
        #expect(state.sides[0].setsWon == 1)
        #expect(state.completedSets == [[6, 0]])
    }

    @Test("Tennis: 5-5 goes on to 7-5 rather than ending at six")
    func tennisSevenFive() throws {
        let rules = try rules("tennis")
        var state = newState(rules)

        for _ in 0 ..< 5 { award(4, to: 0, &state, rules) }
        for _ in 0 ..< 5 { award(4, to: 1, &state, rules) }
        award(4, to: 0, &state, rules)   // 6-5, only one clear
        #expect(state.sides[0].setsWon == 0)

        award(4, to: 0, &state, rules)   // 7-5
        #expect(state.sides[0].setsWon == 1)
        #expect(state.completedSets == [[7, 5]])
    }

    @Test("Tennis: six-all starts a tiebreak, scored in plain numbers")
    func tennisTiebreak() throws {
        let rules = try rules("tennis")
        var state = newState(rules)

        for _ in 0 ..< 6 { award(4, to: 0, &state, rules) }
        // side 0 has taken the set at 6-0; play a fresh set to 6-6.
        state = newState(rules)
        for _ in 0 ..< 6 { award(4, to: 0, &state, rules) }
        state = newState(rules)

        for _ in 0 ..< 5 { award(4, to: 0, &state, rules) }
        for _ in 0 ..< 6 { award(4, to: 1, &state, rules) }
        award(4, to: 0, &state, rules)   // 6-6
        #expect(state.isTiebreak)
        #expect(points(state, rules, 0) == "0", "a tiebreak is scored in plain numbers")

        award(7, to: 0, &state, rules)
        #expect(state.sides[0].setsWon == 1)
        #expect(state.completedSets == [[7, 6]], "the tiebreak counts as a game")
        #expect(!state.isTiebreak)
    }

    @Test("Tennis: a tiebreak also needs a two-point margin")
    func tennisTiebreakMargin() throws {
        let rules = try rules("tennis")
        var state = newState(rules)
        state.isTiebreak = true

        award(6, to: 0, &state, rules)
        award(6, to: 1, &state, rules)
        award(1, to: 0, &state, rules)   // 7-6
        #expect(state.sides[0].setsWon == 0)

        award(1, to: 0, &state, rules)   // 8-6
        #expect(state.sides[0].setsWon == 1)
    }

    @Test("Tennis: an optional match tiebreak replaces the deciding set")
    func tennisMatchTiebreak() throws {
        var rules = try rules("tennis")
        rules.matchTiebreak = true
        rules.matchTiebreakPoints = 10

        var state = newState(rules)
        for _ in 0 ..< 6 { award(4, to: 0, &state, rules) }   // set 1 to side 0
        for _ in 0 ..< 6 { award(4, to: 1, &state, rules) }   // set 1 each

        #expect(SetMatchEngine.isDecidingSet(state, rules: rules))
        #expect(state.isTiebreak, "the deciding set starts as a match tiebreak")
        #expect(SetMatchEngine.isMatchTiebreak(state, rules: rules))

        award(9, to: 0, &state, rules)
        #expect(!state.isFinished, "nine is not ten")
        award(1, to: 0, &state, rules)
        #expect(state.isFinished)
        #expect(state.sides[0].setsWon == 2)
    }

    // MARK: - Other rally presets

    @Test("Badminton: the hard cap ends a runaway set at 30")
    func badmintonCap() throws {
        let rules = try rules("badminton")
        #expect(rules.hardCap == 30)

        var state = newState(rules)
        // Alternating keeps the margin at one, so the set runs past 21 without ever being won —
        // which is the only way to reach the cap.
        for _ in 0 ..< 29 {
            award(1, to: 0, &state, rules)
            award(1, to: 1, &state, rules)
        }
        #expect(state.sides[0].setsWon == 0, "29-29, still no two-point margin")

        award(1, to: 0, &state, rules)   // 30-29: one clear, but the cap decides it
        #expect(state.sides[0].setsWon == 1)
        #expect(state.completedSets == [[30, 29]])
    }

    @Test("Table tennis: serve alternates every two points")
    func tableTennisServe() throws {
        let rules = try rules("table-tennis-ping-pong")
        #expect(rules.servesPerRotation == 2)

        var state = newState(rules)
        #expect(state.servingSlot == 0)

        award(1, to: 0, &state, rules)
        #expect(state.servingSlot == 0, "still the first server's pair")
        award(1, to: 1, &state, rules)
        #expect(state.servingSlot == 1, "serve passes after two points, whoever won them")
        award(2, to: 0, &state, rules)
        #expect(state.servingSlot == 0)
    }

    @Test("Rally serve: with one serve each, the point winner serves next")
    func rallyServeFollowsWinner() throws {
        let rules = try rules("volleyball")
        var state = newState(rules)

        award(1, to: 1, &state, rules)
        #expect(state.servingSlot == 1)
        award(1, to: 0, &state, rules)
        #expect(state.servingSlot == 0)
    }

    // MARK: - Darts

    @Test("Darts: a visit subtracts from the remaining score")
    func dartsCountdown() throws {
        let rules = try rules("darts")
        var state = newState(rules)
        #expect(state.sides[0].remaining == 501)

        SetMatchEngine.apply(.score(slot: 0, points: 180), to: &state, rules: rules, at: at(0))
        #expect(state.sides[0].remaining == 321)
        #expect(points(state, rules, 0) == "321")
    }

    /// Bust reverts the whole visit — which is why the engine subtracts rather than accumulates.
    @Test("Darts: going past zero busts and the score is unchanged")
    func dartsBustPastZero() throws {
        let rules = try rules("darts")
        var state = newState(rules)
        state.sides[0].remaining = 40

        SetMatchEngine.apply(.score(slot: 0, points: 45), to: &state, rules: rules, at: at(0))
        #expect(state.sides[0].remaining == 40, "the visit did not count")
        #expect(state.lastVisitBusted)
    }

    @Test("Darts: leaving one busts when the leg must finish on a double")
    func dartsBustOnOne() throws {
        let rules = try rules("darts")
        #expect(rules.doubleOut)

        var state = newState(rules)
        state.sides[0].remaining = 40
        SetMatchEngine.apply(.score(slot: 0, points: 39), to: &state, rules: rules, at: at(0))

        #expect(state.sides[0].remaining == 40)
        #expect(state.lastVisitBusted)
    }

    @Test("Darts: checking out wins a leg and resets both players")
    func dartsLeg() throws {
        let rules = try rules("darts")
        var state = newState(rules)
        state.sides[0].remaining = 40
        state.sides[1].remaining = 120

        SetMatchEngine.apply(.score(slot: 0, points: 40), to: &state, rules: rules, at: at(0))

        #expect(state.sides[0].legsWon == 1)
        #expect(state.sides[0].remaining == 501)
        #expect(state.sides[1].remaining == 501, "both players start the next leg fresh")
        #expect(!state.lastVisitBusted)
    }

    @Test("Darts: legs roll up into sets")
    func dartsSets() throws {
        var rules = try rules("darts")
        rules.legsPerSet = 2
        rules.setsToWin = 1

        var state = newState(rules)
        for _ in 0 ..< 2 {
            state.sides[0].remaining = 40
            SetMatchEngine.apply(.score(slot: 0, points: 40), to: &state, rules: rules, at: at(0))
        }

        #expect(state.sides[0].setsWon == 1)
        #expect(state.isFinished)
    }

    // MARK: Checkout suggestions

    @Test("Checkout suggestions are real finishes")
    func checkouts() {
        #expect(DartsCheckout.suggestion(for: 170, doubleOut: true) == "T20 T20 BULL")
        #expect(DartsCheckout.suggestion(for: 40, doubleOut: true) == "D20")
        #expect(DartsCheckout.suggestion(for: 50, doubleOut: true) == "BULL")

        // Nothing above 170 is checkable in three darts.
        #expect(DartsCheckout.suggestion(for: 171, doubleOut: true) == nil)
        // One cannot be finished on a double.
        #expect(DartsCheckout.suggestion(for: 1, doubleOut: true) == nil)
    }

    /// Every checkable score must produce a suggestion whose segments genuinely sum to it and end
    /// on a double — a plausible-looking but wrong suggestion is worse than none.
    @Test("Every suggestion between 2 and 170 is arithmetically valid")
    func checkoutsAreValid() throws {
        for target in 2 ... DartsCheckout.maximumCheckout {
            guard let suggestion = DartsCheckout.suggestion(for: target, doubleOut: true) else {
                // A handful of scores genuinely have no three-dart finish, e.g. 169, 168, 166.
                #expect([159, 162, 163, 165, 166, 168, 169].contains(target), "no checkout for \(target)")
                continue
            }

            let parts = suggestion.split(separator: " ").map(String.init)
            #expect(parts.count <= 3, "\(target) needs more than three darts")

            let total = parts.reduce(0) { $0 + Self.value(of: $1) }
            #expect(total == target, "\(suggestion) sums to \(total), not \(target)")

            let last = try #require(parts.last)
            #expect(last.hasPrefix("D") || last == "BULL", "\(suggestion) does not finish on a double")
        }
    }

    private static func value(of label: String) -> Int {
        if label == "BULL" { return 50 }
        if label == "25" { return 25 }
        if label.hasPrefix("T") { return (Int(label.dropFirst()) ?? 0) * 3 }
        if label.hasPrefix("D") { return (Int(label.dropFirst()) ?? 0) * 2 }
        return Int(label) ?? 0
    }

    // MARK: Outcome

    @Test("Outcome reports the match winner by sets")
    func outcome() throws {
        let rules = try rules("volleyball")
        var state = newState(rules)
        #expect(SetMatchEngine.outcome(state, rules: rules, at: at(0)) == nil, "not finished yet")

        for _ in 0 ..< 3 { award(25, to: 0, &state, rules) }
        let result = try #require(SetMatchEngine.outcome(state, rules: rules, at: at(0)))

        #expect(result.winningSlots == [0])
        #expect(result.outcome(forSlot: 0) == .win)
        #expect(result.outcome(forSlot: 1) == .loss)
    }

    @Test("State survives a Codable round trip")
    func stateRoundTrip() throws {
        let rules = try rules("tennis")
        var state = newState(rules)
        award(3, to: 0, &state, rules)
        award(2, to: 1, &state, rules)

        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SetMatchState.self, from: data) == state)
    }
}
