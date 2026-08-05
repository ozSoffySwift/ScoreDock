import Foundation
import Testing

@testable import ScoreDock

/// §6.3 — the American football board, sequenced third at M6.
@Suite("American football (§6.3)")
struct AmericanFootballTests {
    static let tip = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.tip.addingTimeInterval(seconds) }

    private func rules() throws -> AmericanFootballRules {
        let preset = try #require(BuiltInCatalog.bySlug["american-football"])
        return try #require(preset.rules.specialisedRules?.americanFootball)
    }

    private func apply(
        _ action: EngineAction,
        _ state: inout AmericanFootballState,
        _ rules: AmericanFootballRules,
        at now: Date = tip
    ) {
        AmericanFootballEngine.apply(action, to: &state, rules: rules, at: now)
    }

    private func board(
        _ state: AmericanFootballState,
        _ rules: AmericanFootballRules,
        at now: Date = tip
    ) -> DerivedFootballBoard {
        AmericanFootballEngine.derived(state, rules: rules, isFinished: false, at: now)
    }

    // MARK: Down and distance

    @Test("Down and distance reads the way a scoreboard writes it")
    func downAndDistanceText() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.specialised(.setDownAndDistance(down: 3, yardsToGo: 7)), &state, rules)
        #expect(board(state, rules).downAndDistance == "3RD & 7")

        apply(.specialised(.setDownAndDistance(down: 1, yardsToGo: 10)), &state, rules)
        #expect(board(state, rules).downAndDistance == "1ST & 10")
    }

    /// "And goal" is not a distance of ten or less — it is the line to gain *being* the goal line.
    @Test("Inside the ten it becomes and goal")
    func andGoal() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.specialised(.setBallOn(yardLine: 94)), &state, rules)     // six yards out
        apply(.specialised(.setDownAndDistance(down: 1, yardsToGo: 6)), &state, rules)
        #expect(board(state, rules).downAndDistance == "1ST & GOAL")

        // Same six yards to go, but from midfield the line to gain is not the goal line.
        apply(.specialised(.setBallOn(yardLine: 50)), &state, rules)
        #expect(board(state, rules).downAndDistance == "1ST & 6")
    }

    @Test("A first down inside the ten is short of ten yards")
    func firstDownDistanceNearGoal() throws {
        let rules = try rules()
        #expect(AmericanFootballEngine.firstDownDistance(from: 25, rules: rules) == 10)
        #expect(AmericanFootballEngine.firstDownDistance(from: 94, rules: rules) == 6)
        #expect(AmericanFootballEngine.firstDownDistance(from: 100, rules: rules) == 0)
    }

    @Test("The down is clamped to the number of downs the rules allow")
    func downIsClamped() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.specialised(.setDownAndDistance(down: 9, yardsToGo: 3)), &state, rules)
        #expect(state.down == 4)

        apply(.specialised(.setDownAndDistance(down: 0, yardsToGo: 3)), &state, rules)
        #expect(state.down == 1)
    }

    // MARK: The ball spot

    /// The field's painted numbers count up to midfield and back down again.
    @Test("The painted yard line is not the offence's yard line")
    func paintedYardLine() throws {
        let rules = try rules()
        #expect(AmericanFootballEngine.paintedYardLine(25, rules: rules) == 25)
        #expect(AmericanFootballEngine.paintedYardLine(50, rules: rules) == 50)
        #expect(AmericanFootballEngine.paintedYardLine(70, rules: rules) == 30, "the 70 is the 30 on the turf")
        #expect(AmericanFootballEngine.paintedYardLine(95, rules: rules) == 5)
    }

    /// The ball does not move on a turnover, but the frame it is measured in flips.
    @Test("A turnover mirrors the ball spot and starts a fresh set of downs")
    func turnoverMirrorsTheSpot() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.setPossession(0), &state, rules)
        apply(.specialised(.setBallOn(yardLine: 30)), &state, rules)
        apply(.specialised(.setDownAndDistance(down: 4, yardsToGo: 8)), &state, rules)

        apply(.setPossession(1), &state, rules)

        #expect(state.ballOn == 70, "the same spot on the field, from the other end")
        #expect(AmericanFootballEngine.paintedYardLine(state.ballOn, rules: rules) == 30, "and the turf number is unchanged")
        #expect(state.down == 1)
        #expect(state.yardsToGo == 10)
    }

    @Test("Setting possession for the first time does not mirror anything")
    func firstPossessionDoesNotMirror() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.specialised(.setBallOn(yardLine: 35)), &state, rules)
        apply(.setPossession(0), &state, rules)

        #expect(state.ballOn == 35)
    }

    @Test("The ball spot is clamped to the field")
    func ballSpotIsClamped() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.specialised(.setBallOn(yardLine: 140)), &state, rules)
        #expect(state.ballOn == 100)

        apply(.specialised(.setBallOn(yardLine: -5)), &state, rules)
        #expect(state.ballOn == 0)
    }

    // MARK: Clocks

    @Test("The play clock resets to 40 on a tap and 25 on a long press")
    func playClockResets() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.toggleShotClock, &state, rules, at: at(0))
        #expect(board(state, rules, at: at(12)).playClock.value == 28)

        apply(.resetShotClock(full: false), &state, rules, at: at(12))
        #expect(board(state, rules, at: at(12)).playClock.value == 25)
        #expect(board(state, rules, at: at(12)).playClock.isRunning, "a reset does not stop a running play clock")

        apply(.resetShotClock(full: true), &state, rules, at: at(20))
        #expect(board(state, rules, at: at(20)).playClock.value == 40)
    }

    @Test("The play clock reads bare seconds, never minutes")
    func playClockStyle() throws {
        let rules = try rules()
        let state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)
        #expect(board(state, rules).playClock.formatted == "40", "not 00:40")
    }

    @Test("The game clock runs down and shows tenths in the last minute")
    func gameClock() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.toggleClock, &state, rules, at: at(0))
        #expect(board(state, rules, at: at(60)).gameClock.value == 840)
        #expect(!board(state, rules, at: at(60)).gameClock.showsTenths)

        #expect(board(state, rules, at: at(870)).gameClock.showsTenths, "inside the last minute")
        #expect(board(state, rules, at: at(1000)).gameClock.value == 0, "never negative")
        #expect(board(state, rules, at: at(1000)).gameClock.hasExpired)
    }

    // MARK: Timeouts and quarters

    @Test("Timeouts come back at half time and at no other break")
    func timeoutsResetAtHalf() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.timeout(slot: 0, delta: 1), &state, rules)
        apply(.timeout(slot: 0, delta: 1), &state, rules)
        #expect(board(state, rules).sides[0].timeoutsRemaining == 1)

        apply(.advancePeriod, &state, rules)                 // Q2 — still the first half
        #expect(board(state, rules).sides[0].timeoutsRemaining == 1)

        apply(.advancePeriod, &state, rules)                 // Q3 — second half
        #expect(board(state, rules).sides[0].timeoutsRemaining == 3)
    }

    @Test("Timeouts cannot go past the allocation or below zero")
    func timeoutsAreBounded() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        for _ in 0 ..< 6 { apply(.timeout(slot: 1, delta: 1), &state, rules) }
        #expect(state.sides[1].timeoutsUsed == 3)

        for _ in 0 ..< 6 { apply(.timeout(slot: 1, delta: -1), &state, rules) }
        #expect(state.sides[1].timeoutsUsed == 0)
    }

    @Test("Periods are labelled Q1 to Q4, then overtime")
    func quarterLabels() throws {
        let rules = try rules()
        #expect(AmericanFootballEngine.quarterLabel(1, rules: rules) == "Q1")
        #expect(AmericanFootballEngine.quarterLabel(4, rules: rules) == "Q4")
        #expect(AmericanFootballEngine.quarterLabel(5, rules: rules) == "OT")
        #expect(AmericanFootballEngine.quarterLabel(6, rules: rules) == "OT2")
    }

    // MARK: Scoring and result

    @Test("A drive is scored the way football scores")
    func scoring() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.score(slot: 0, points: 6), &state, rules)     // touchdown
        apply(.score(slot: 0, points: 1), &state, rules)     // extra point
        apply(.score(slot: 1, points: 3), &state, rules)     // field goal
        apply(.score(slot: 1, points: 2), &state, rules)     // safety

        #expect(board(state, rules).sides.map(\.score) == [7, 5])
    }

    @Test("A score cannot be pushed below zero")
    func scoreNeverNegative() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.score(slot: 0, points: -6), &state, rules)
        #expect(state.sides[0].score == 0)
    }

    @Test("The higher score wins, and equal scores are a tie")
    func outcome() throws {
        let rules = try rules()
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)

        apply(.score(slot: 0, points: 24), &state, rules)
        apply(.score(slot: 1, points: 17), &state, rules)

        let result = try #require(AmericanFootballEngine.outcome(state, rules: rules, at: at(0)))
        #expect(result.winningSlots == [0])
        #expect(result.rankBySlot == [0: 1, 1: 2])

        apply(.score(slot: 1, points: 7), &state, rules)
        let tied = try #require(AmericanFootballEngine.outcome(state, rules: rules, at: at(0)))
        #expect(tied.isDraw)
        #expect(tied.winningSlots.isEmpty)
    }

    // MARK: Through the shared engine

    @Test("The dispatcher routes to the football board and stops both clocks")
    func throughSpecialisedEngine() throws {
        var specialised = SpecialisedRules(board: .americanFootball)
        specialised.americanFootball = try rules()

        var state = SpecialisedEngine.initialState(rules: specialised, sideCount: 2)
        SpecialisedEngine.apply(.toggleClock, to: &state, rules: specialised, at: at(0))
        SpecialisedEngine.apply(.toggleShotClock, to: &state, rules: specialised, at: at(0))
        SpecialisedEngine.apply(.score(slot: 0, points: 6), to: &state, rules: specialised, at: at(1))
        SpecialisedEngine.apply(
            .specialised(.setDownAndDistance(down: 2, yardsToGo: 4)),
            to: &state, rules: specialised, at: at(1)
        )

        guard case let .americanFootball(board) = SpecialisedEngine.derived(state, rules: specialised, at: at(10)) else {
            Issue.record("expected a football board")
            return
        }
        #expect(board.sides[0].score == 6)
        #expect(board.downAndDistance == "2ND & 4")
        #expect(board.gameClock.value == 890)
        #expect(board.playClock.value == 30)

        SpecialisedEngine.apply(.finishMatch, to: &state, rules: specialised, at: at(10))
        #expect(state.isFinished)
        #expect(SpecialisedEngine.derived(state, rules: specialised, at: at(900)) == SpecialisedEngine.derived(state, rules: specialised, at: at(10)))
    }
}
