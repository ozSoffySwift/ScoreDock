import Foundation
import Testing

@testable import ScoreDock

/// §6.3 — the baseball board, the last of the five.
@Suite("Baseball (§6.3)")
struct BaseballTests {
    static let tip = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.tip.addingTimeInterval(seconds) }

    private func rules() throws -> BaseballRules {
        let preset = try #require(BuiltInCatalog.bySlug["baseball"])
        return try #require(preset.rules.specialisedRules?.baseball)
    }

    private func pitch(
        _ outcome: PitchOutcome,
        _ state: inout BaseballState,
        _ rules: BaseballRules,
        times: Int = 1
    ) {
        for _ in 0 ..< times {
            BaseballEngine.apply(.specialised(.pitch(outcome)), to: &state, rules: rules, at: Self.tip)
        }
    }

    private func board(_ state: BaseballState, _ rules: BaseballRules) -> DerivedBaseballBoard {
        BaseballEngine.derived(state, rules: rules, isFinished: false, at: Self.tip)
    }

    // MARK: The count

    @Test("Four balls is a walk and clears the count")
    func walk() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        pitch(.ball, &state, rules, times: 3)
        #expect(board(state, rules).countText == "3-0")

        pitch(.ball, &state, rules)
        #expect(board(state, rules).countText == "0-0")
        #expect(state.bases.first)
        #expect(state.outs == 0)
    }

    @Test("Three strikes is an out and clears the count")
    func strikeout() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        pitch(.strike, &state, rules, times: 3)
        #expect(state.outs == 1)
        #expect(board(state, rules).countText == "0-0")
    }

    /// The rule that makes a foul different from a strike.
    @Test("A foul can never be the third strike")
    func foulCannotStrikeOut() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        pitch(.strike, &state, rules, times: 2)
        pitch(.foul, &state, rules, times: 8)

        #expect(state.strikes == 2, "the count stays at two")
        #expect(state.outs == 0, "and nobody is out")
    }

    // MARK: Baserunning

    @Test("A walk moves only the runners who are forced")
    func forcedAdvanceOnly() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        // Runners on first and third: the runner on third is not forced by a walk.
        state.bases = BaseOccupancy(first: true, second: false, third: true)

        pitch(.ball, &state, rules, times: 4)

        #expect(state.bases == BaseOccupancy(first: true, second: true, third: true))
        #expect(state.sides[1].runs == 0, "nobody was forced home")
    }

    /// A forced run is not a judgement call, so it is the one thing that scores by itself.
    @Test("A walk with the bases loaded forces in a run")
    func basesLoadedWalk() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        state.bases = BaseOccupancy(first: true, second: true, third: true)

        pitch(.ball, &state, rules, times: 4)

        #expect(state.sides[1].runs == 1)
        #expect(state.bases == BaseOccupancy(first: true, second: true, third: true), "still loaded")
    }

    @Test("A hit is credited to the batting side and puts the batter on")
    func hit() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        pitch(.hit, &state, rules)
        #expect(state.sides[1].hits == 1)
        #expect(state.bases.first)
        #expect(state.sides[0].hits == 0)
    }

    @Test("An error is charged to the side in the field")
    func errorGoesToTheFieldingSide() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        // Top of the first: the visitors bat, so the home side is in the field.
        pitch(.error, &state, rules)
        #expect(state.sides[0].errors == 1)
        #expect(state.sides[1].errors == 0)
        #expect(state.bases.first, "and the batter reaches")
    }

    @Test("Setting the bases directly overrides whatever the engine assumed")
    func setBases() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        pitch(.hit, &state, rules)
        BaseballEngine.apply(
            .specialised(.setBases(first: false, second: true, third: false)),
            to: &state, rules: rules, at: Self.tip
        )
        #expect(state.bases == BaseOccupancy(first: false, second: true, third: false))
    }

    // MARK: Half-innings

    @Test("Three outs ends the half-inning and clears the bases")
    func threeOutsEndTheHalf() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        pitch(.hit, &state, rules)
        pitch(.out, &state, rules, times: 3)

        #expect(state.inning == 1)
        #expect(!state.isTop, "the home side comes in")
        #expect(state.outs == 0)
        #expect(state.bases.isEmpty, "runners do not carry over")
        #expect(state.battingSlot == 0)
    }

    @Test("The bottom of an inning is followed by the top of the next")
    func inningRollover() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        pitch(.out, &state, rules, times: 3)     // top of 1 over
        pitch(.out, &state, rules, times: 3)     // bottom of 1 over

        #expect(state.inning == 2)
        #expect(state.isTop)
        #expect(state.battingSlot == 1, "the visitors bat the top")
    }

    // MARK: The line score

    @Test("Runs land in the inning they were scored in")
    func lineScore() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        pitch(.run, &state, rules, times: 2)     // visitors, top of 1
        pitch(.out, &state, rules, times: 3)
        pitch(.run, &state, rules)               // home, bottom of 1
        pitch(.out, &state, rules, times: 3)
        pitch(.run, &state, rules, times: 3)     // visitors, top of 2

        let derived = board(state, rules)
        #expect(derived.sides[1].lineScore.prefix(2).map { $0 } == [2, 3])
        #expect(derived.sides[0].lineScore.prefix(2).map { $0 } == [1, nil])
        #expect(derived.sides[1].runs == 5)
        #expect(derived.sides[0].runs == 1)
    }

    /// A blank cell and a zero are different facts, and a line score that confuses them is wrong.
    @Test("An inning a side has not batted is blank, not zero")
    func unplayedInningIsBlank() throws {
        let rules = try rules()
        let state = BaseballEngine.initialState(rules: rules, sideCount: 2)

        let derived = board(state, rules)
        #expect(derived.sides[1].lineScore[0] == .some(0), "the visitors are batting the first")
        #expect(derived.sides[0].lineScore[0] == nil, "the home side has not batted yet")
        #expect(derived.inningsPlayed == 9)
    }

    @Test("Extra innings add columns")
    func extraInnings() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        state.inning = 11

        #expect(board(state, rules).inningsPlayed == 11)
    }

    @Test("The inning label reads top or bottom")
    func inningLabel() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        state.inning = 5

        #expect(board(state, rules).inningLabel == "T5")
        state.isTop = false
        #expect(board(state, rules).inningLabel == "B5")
    }

    // MARK: Completion and result

    @Test("A game is not complete until the scheduled innings are")
    func completionRequiresRegulation() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        state.sides[1].runsByInning = [7]

        state.inning = 3
        #expect(!BaseballEngine.isComplete(state, rules: rules), "a big lead is not a finished game")

        state.inning = 9
        state.isTop = false
        #expect(BaseballEngine.isComplete(state, rules: rules))
    }

    @Test("A tie goes to extra innings when the rules allow it")
    func tiesGoToExtras() throws {
        var rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        state.inning = 9
        state.isTop = false
        state.sides[0].runsByInning = [3]
        state.sides[1].runsByInning = [3]

        #expect(!BaseballEngine.isComplete(state, rules: rules))

        rules.allowsExtraInnings = false
        #expect(BaseballEngine.isComplete(state, rules: rules), "a tie stands when extras are off")
    }

    @Test("The side with more runs wins")
    func outcome() throws {
        let rules = try rules()
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        state.sides[0].runsByInning = [1, 0, 4]
        state.sides[1].runsByInning = [2, 0, 0]

        let result = try #require(BaseballEngine.outcome(state, rules: rules, at: at(0)))
        #expect(result.winningSlots == [0])
        #expect(result.rankBySlot == [0: 1, 1: 2])
    }

    // MARK: Through the shared engine

    @Test("The dispatcher routes to the baseball board")
    func throughSpecialisedEngine() throws {
        var specialised = SpecialisedRules(board: .baseball)
        specialised.baseball = try rules()

        var state = SpecialisedEngine.initialState(rules: specialised, sideCount: 2)
        SpecialisedEngine.apply(.specialised(.pitch(.hit)), to: &state, rules: specialised, at: at(0))
        SpecialisedEngine.apply(.specialised(.pitch(.ball)), to: &state, rules: specialised, at: at(1))
        SpecialisedEngine.apply(.specialised(.pitch(.strike)), to: &state, rules: specialised, at: at(2))

        guard case let .baseball(board) = SpecialisedEngine.derived(state, rules: specialised, at: at(3)) else {
            Issue.record("expected a baseball board")
            return
        }
        #expect(board.countText == "1-1")
        #expect(board.sides[1].hits == 1)
        #expect(board.bases.first)
        #expect(board.inningLabel == "T1")
    }

    @Test("Every board this build knows about is implemented")
    func allBoardsImplemented() {
        #expect(SpecialisedEngine.implementedBoards == Set(SpecialisedBoard.allCases))
    }
}
