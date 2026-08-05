import Foundation
import Testing

@testable import ScoreDock

/// §6.3 — the cricket board, and §17 risk 12's per-ball event log.
@Suite("Cricket (§6.3)")
struct CricketTests {
    static let tip = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.tip.addingTimeInterval(seconds) }

    private func rules(
        format: CricketRules.Format = .t20,
        overs: Int = 20,
        wickets: Int = 10,
        inningsPerSide: Int = 1
    ) -> CricketRules {
        var rules = CricketRules()
        rules.format = format
        rules.oversPerInnings = overs
        rules.wicketsPerInnings = wickets
        rules.inningsPerSide = inningsPerSide
        return rules
    }

    private func ball(
        _ runs: Int,
        _ extra: CricketExtra? = nil,
        _ state: inout CricketState,
        _ rules: CricketRules
    ) {
        CricketEngine.apply(.specialised(.delivery(runs: runs, extra: extra)), to: &state, rules: rules, at: Self.tip)
    }

    private func wicket(_ state: inout CricketState, _ rules: CricketRules) {
        CricketEngine.apply(.specialised(.wicket(kind: .bowled)), to: &state, rules: rules, at: Self.tip)
    }

    private func board(_ state: CricketState, _ rules: CricketRules) -> DerivedCricketBoard {
        CricketEngine.derived(state, rules: rules, sideCount: 2, isFinished: false, at: Self.tip)
    }

    // MARK: Deliveries and the over

    /// The rule the whole board hangs off: a wide is a delivery but not a *ball*.
    @Test("Wides and no-balls do not count towards the over; byes do")
    func ballsInTheOver() {
        let rules = rules()
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(0, nil, &state, rules)          // legal dot
        ball(0, .wide, &state, rules)        // not a ball
        ball(0, .noBall, &state, rules)      // not a ball
        ball(1, .bye, &state, rules)         // is a ball
        ball(2, .legBye, &state, rules)      // is a ball

        #expect(state.innings[0].legalBalls == 3)
        #expect(board(state, rules).oversText == "0.3")
    }

    @Test("An extra concedes its own run on top of anything run")
    func extraRuns() {
        let rules = rules()
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(0, .wide, &state, rules)        // 1
        ball(4, .noBall, &state, rules)      // 1 + 4 = 5
        ball(2, .bye, &state, rules)         // 2
        ball(6, nil, &state, rules)          // 6

        #expect(state.innings[0].runs == 14)
        // Extras: the wide's 1, the no-ball's 1, and both byes. The four off the no-ball came off
        // the bat and is not an extra.
        #expect(state.innings[0].extras == 4)
    }

    @Test("Overs read as overs and balls, not as a decimal")
    func oversText() {
        #expect(CricketEngine.oversText(0, ballsPerOver: 6) == "0.0")
        #expect(CricketEngine.oversText(17, ballsPerOver: 6) == "2.5")
        #expect(CricketEngine.oversText(18, ballsPerOver: 6) == "3.0", "2.5 plus one ball is 3.0, not 2.6")
        #expect(CricketEngine.oversText(120, ballsPerOver: 6) == "20.0")
    }

    // MARK: Wickets and partnerships

    @Test("A wicket costs a ball and starts a new partnership")
    func wicketResetsPartnership() {
        let rules = rules()
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(4, nil, &state, rules)
        ball(2, nil, &state, rules)
        #expect(state.innings[0].partnership == 6)

        wicket(&state, rules)
        #expect(state.innings[0].wickets == 1)
        #expect(state.innings[0].partnership == 0)
        #expect(state.innings[0].legalBalls == 3, "the dismissal ball still counts")
        #expect(state.innings[0].runs == 6, "and the runs stay on the board")
    }

    @Test("A score reads 180-4, and just 180 once all ten are down")
    func scoreText() {
        let rules = rules(wickets: 2)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(4, nil, &state, rules)
        wicket(&state, rules)
        #expect(board(state, rules).scoreText == "4-1")

        wicket(&state, rules)
        #expect(state.innings[0].isClosed)
    }

    // MARK: Closing an innings

    @Test("An innings ends when the wickets run out")
    func allOut() {
        let rules = rules(wickets: 3)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        wicket(&state, rules)
        wicket(&state, rules)
        #expect(!state.innings[0].isClosed)

        wicket(&state, rules)
        #expect(state.innings[0].isClosed)
        #expect(state.currentInnings == 1, "and the other side comes in")
        #expect(state.innings[1].battingSlot == 1)
    }

    @Test("An innings ends when the overs run out")
    func oversExhausted() {
        let rules = rules(overs: 2)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        // Twelve legal balls, with a wide part-way that must not shorten the innings.
        for index in 0 ..< 11 { ball(index % 3, nil, &state, rules) }
        ball(0, .wide, &state, rules)
        #expect(!state.innings[0].isClosed, "a wide is not a ball")

        ball(1, nil, &state, rules)
        #expect(state.innings[0].isClosed)
        #expect(state.innings[0].legalBalls == 12)
    }

    @Test("A closed innings ignores further deliveries")
    func closedInningsIsInert() {
        let rules = rules(wickets: 1)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        wicket(&state, rules)                 // innings 0 closes, innings 1 opens
        let openedAt = state.currentInnings
        ball(6, nil, &state, rules)

        #expect(state.innings[0].runs == 0, "the runs went to the new innings, not the closed one")
        #expect(state.innings[openedAt].runs == 6)
    }

    @Test("Declaring closes the innings early")
    func declaration() {
        let rules = rules()
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(4, nil, &state, rules)
        CricketEngine.apply(.specialised(.endInnings), to: &state, rules: rules, at: Self.tip)

        #expect(state.innings[0].isClosed)
        #expect(state.currentInnings == 1)
    }

    // MARK: Chasing

    @Test("The chase needs one more than the other side made")
    func target() {
        let rules = rules(wickets: 1)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(6, nil, &state, rules)
        ball(6, nil, &state, rules)
        wicket(&state, rules)                 // 12 all out, innings over

        let chase = board(state, rules)
        #expect(chase.target == 13)
        #expect(chase.runsNeeded == 13)

        ball(4, nil, &state, rules)
        #expect(board(state, rules).runsNeeded == 9)
    }

    @Test("Passing the target ends the match there and then")
    func chaseEndsTheInnings() {
        let rules = rules(overs: 20, wickets: 10)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(4, nil, &state, rules)
        CricketEngine.apply(.specialised(.endInnings), to: &state, rules: rules, at: Self.tip)

        ball(4, nil, &state, rules)
        #expect(!state.innings[1].isClosed, "level is not won")

        ball(1, nil, &state, rules)
        #expect(state.innings[1].isClosed, "the remaining balls are not bowled")
        #expect(state.innings[1].runs == 5)
    }

    @Test("Run rate is per over, and the required rate uses the balls that are left")
    func rates() {
        let rules = rules(overs: 20, wickets: 10)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        // 60 off the first ten overs.
        for _ in 0 ..< 60 { ball(1, nil, &state, rules) }
        #expect(board(state, rules).runRate == 6)

        CricketEngine.apply(.specialised(.endInnings), to: &state, rules: rules, at: Self.tip)
        let chase = board(state, rules)
        #expect(chase.target == 61)
        // 61 needed off 20 overs.
        #expect(chase.requiredRate == 3.05)
    }

    @Test("A Test's fourth-innings target counts the chasing side's first innings")
    func testMatchTarget() {
        let rules = rules(format: .test, overs: 0, wickets: 1, inningsPerSide: 2)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(300, nil, &state, rules); wicket(&state, rules)     // side 0: 300
        ball(250, nil, &state, rules); wicket(&state, rules)     // side 1: 250
        ball(200, nil, &state, rules); wicket(&state, rules)     // side 0: 200

        #expect(state.currentInnings == 3)
        #expect(state.innings[3].battingSlot == 1)
        // 300 + 200 − 250 + 1.
        #expect(board(state, rules).target == 251)
    }

    @Test("An unlimited format never runs out of overs")
    func testMatchHasNoBallLimit() {
        #expect(CricketEngine.ballLimit(rules(format: .test, overs: 0)) == nil)
        #expect(CricketEngine.ballLimit(rules(format: .t20, overs: 20)) == 120)
    }

    // MARK: Result

    @Test("The side with more runs wins, and level scores tie")
    func outcome() throws {
        let rules = rules(wickets: 1)
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)

        ball(120, nil, &state, rules); wicket(&state, rules)
        ball(90, nil, &state, rules); wicket(&state, rules)

        let result = try #require(CricketEngine.outcome(state, rules: rules, at: at(0)))
        #expect(result.winningSlots == [0])
        #expect(result.rankBySlot == [0: 1, 1: 2])
    }

    // MARK: Through the shared engine, and the risk-12 log

    @Test("The dispatcher routes to the cricket board")
    func throughSpecialisedEngine() {
        var specialised = SpecialisedRules(board: .cricket)
        specialised.cricket = rules()

        var state = SpecialisedEngine.initialState(rules: specialised, sideCount: 2)
        SpecialisedEngine.apply(
            .specialised(.delivery(runs: 4, extra: nil)), to: &state, rules: specialised, at: at(0)
        )
        SpecialisedEngine.apply(
            .specialised(.wicket(kind: .caught)), to: &state, rules: specialised, at: at(1)
        )

        guard case let .cricket(board) = SpecialisedEngine.derived(state, rules: specialised, at: at(2)) else {
            Issue.record("expected a cricket board")
            return
        }
        #expect(board.scoreText == "4-1")
        #expect(board.oversText == "0.2")
    }

    /// §17 risk 12: a full T20 innings is the largest log the app produces, and it has to replay
    /// back to exactly the same state.
    @Test("A full innings of deliveries replays to the same score")
    func fullInningsReplays() {
        let rules = rules(overs: 20, wickets: 10)
        var direct = CricketEngine.initialState(rules: rules, sideCount: 2)

        // A wide is a delivery but not a ball, so a full innings needs *more* than 120 deliveries —
        // the log is built by counting balls bowled, not actions taken.
        var actions: [EngineAction] = []
        var legalBalls = 0
        var index = 0
        while legalBalls < 120 {
            if index % 17 == 0 {
                actions.append(.specialised(.delivery(runs: 0, extra: .wide)))
            } else {
                actions.append(.specialised(.delivery(runs: index % 5, extra: nil)))
                legalBalls += 1
            }
            index += 1
        }
        #expect(actions.count == 128, "120 balls took eight extra deliveries")

        for action in actions { CricketEngine.apply(action, to: &direct, rules: rules, at: Self.tip) }

        var replayed = CricketEngine.initialState(rules: rules, sideCount: 2)
        for action in actions { CricketEngine.apply(action, to: &replayed, rules: rules, at: Self.tip) }

        #expect(direct == replayed)
        #expect(direct.innings[0].legalBalls == 120, "the wides did not shorten the innings")
        #expect(direct.innings[0].isClosed)
    }
}
