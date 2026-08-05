import Foundation

/// The baseball board (§6.3): inning-by-inning line score, R / H / E, balls / strikes / outs, base
/// occupancy, top and bottom.
///
/// **The score only changes when the operator says so, or when the rules leave no choice.** A pitch
/// moves the count, the outs and the bases; runs come from the explicit Run control or from a
/// *forced* runner crossing the plate — which is not a judgement call. Everything else a scorer
/// might want (a runner taking an extra base, a double, a runner thrown out stretching) is set
/// directly through the bases control, because guessing at baserunning would put invented runs into
/// a game that is decided by them.
enum BaseballEngine {
    static func initialState(rules: BaseballRules, sideCount: Int) -> BaseballState {
        BaseballState(sideCount: sideCount)
    }

    // MARK: - Apply

    static func apply(
        _ action: EngineAction,
        to state: inout BaseballState,
        rules: BaseballRules,
        at now: Date
    ) {
        switch action {
        case let .specialised(.pitch(outcome)):
            pitch(outcome, in: &state, rules: rules)

        case let .specialised(.setBases(first, second, third)):
            state.bases = BaseOccupancy(first: first, second: second, third: third)

        case .specialised(.advanceHalfInning):
            advanceHalfInning(&state, rules: rules)

        case let .score(slot, points, _):
            // The generic score action still works, so a scorer can correct a total directly.
            addRuns(points, to: slot, in: &state)

        default:
            break
        }
    }

    private static func pitch(
        _ outcome: PitchOutcome,
        in state: inout BaseballState,
        rules: BaseballRules
    ) {
        switch outcome {
        case .ball:
            state.balls += 1
            guard state.balls >= max(1, rules.ballsPerWalk) else { return }
            walk(&state)

        case .strike:
            state.strikes += 1
            guard state.strikes >= max(1, rules.strikesPerOut) else { return }
            recordOut(&state, rules: rules)

        case .foul:
            // A foul is a strike except that it can never be the third one.
            state.strikes = min(state.strikes + 1, max(0, rules.strikesPerOut - 1))

        case .out:
            recordOut(&state, rules: rules)

        case .hit:
            state.sides[state.battingSlot].hits += 1
            addRuns(state.bases.forceAdvance(), to: state.battingSlot, in: &state)
            resetCount(&state)

        case .error:
            // An error is charged to the side in the field, and puts the batter on.
            state.sides[state.fieldingSlot].errors += 1
            addRuns(state.bases.forceAdvance(), to: state.battingSlot, in: &state)
            resetCount(&state)

        case .run:
            addRuns(1, to: state.battingSlot, in: &state)
        }
    }

    private static func walk(_ state: inout BaseballState) {
        addRuns(state.bases.forceAdvance(), to: state.battingSlot, in: &state)
        resetCount(&state)
    }

    private static func recordOut(_ state: inout BaseballState, rules: BaseballRules) {
        state.outs += 1
        resetCount(&state)
        guard state.outs >= max(1, rules.outsPerHalfInning) else { return }
        advanceHalfInning(&state, rules: rules)
    }

    private static func resetCount(_ state: inout BaseballState) {
        state.balls = 0
        state.strikes = 0
    }

    private static func advanceHalfInning(_ state: inout BaseballState, rules: BaseballRules) {
        if state.isTop {
            state.isTop = false
        } else {
            state.inning += 1
            state.isTop = true
        }
        state.outs = 0
        state.bases = BaseOccupancy()
        resetCount(&state)
    }

    /// Adds runs to the current inning's cell, growing the line score to reach it.
    private static func addRuns(_ runs: Int, to slot: Int, in state: inout BaseballState) {
        guard runs != 0, state.sides.indices.contains(slot) else { return }
        let index = max(0, state.inning - 1)
        while state.sides[slot].runsByInning.count <= index {
            state.sides[slot].runsByInning.append(0)
        }
        state.sides[slot].runsByInning[index] = max(0, state.sides[slot].runsByInning[index] + runs)
    }

    // MARK: - Derived

    static func derived(
        _ state: BaseballState,
        rules: BaseballRules,
        isFinished: Bool,
        at now: Date
    ) -> DerivedBaseballBoard {
        // Enough columns for the scheduled game, and more once it goes to extras.
        let inningsPlayed = max(rules.inningCount, state.inning)

        let sides = state.sides.enumerated().map { index, side in
            DerivedBaseballBoard.Side(
                slotIndex: index,
                runs: side.runs,
                hits: side.hits,
                errors: side.errors,
                lineScore: (0 ..< inningsPlayed).map { inning in
                    // An inning this side has not batted is nil, not zero — the home team leading
                    // after the top of the ninth never bats, and printing a 0 there would be wrong.
                    hasBatted(side: index, inning: inning + 1, state: state)
                        ? (side.runsByInning.indices.contains(inning) ? side.runsByInning[inning] : 0)
                        : nil
                },
                isBatting: index == state.battingSlot && !isFinished
            )
        }

        return DerivedBaseballBoard(
            sides: sides,
            inning: state.inning,
            isTop: state.isTop,
            inningsPlayed: inningsPlayed,
            balls: state.balls,
            strikes: state.strikes,
            outs: state.outs,
            bases: state.bases,
            showsHitsAndErrors: rules.showHitsAndErrors,
            isFinished: isFinished
        )
    }

    /// Whether a side has come to bat in an inning yet. Slot 0 is home and bats second (§7.1).
    static func hasBatted(side: Int, inning: Int, state: BaseballState) -> Bool {
        if inning < state.inning { return true }
        if inning > state.inning { return false }
        // The current inning: the visitors are batting or have batted; the home side only once the
        // top is over.
        return side == 1 ? true : !state.isTop
    }

    // MARK: - Outcome

    /// Whether the game has reached its natural end.
    ///
    /// Deliberately *not* enforced by `apply`. A baseball ending has more conditions than a
    /// scoreboard should assume — a walk-off ends play mid-inning, and the home side never bats the
    /// bottom of the ninth when it is already ahead — so this reports and the operator decides.
    static func isComplete(_ state: BaseballState, rules: BaseballRules) -> Bool {
        guard state.sides.count >= 2 else { return false }
        let home = state.sides[0].runs
        let away = state.sides[1].runs

        // Regulation is not over until the scheduled innings are.
        guard state.inning > rules.inningCount || (state.inning == rules.inningCount && !state.isTop)
        else { return false }

        if home != away { return true }
        return !rules.allowsExtraInnings
    }

    static func outcome(
        _ state: BaseballState,
        rules: BaseballRules,
        at now: Date
    ) -> MatchOutcome? {
        let scores = state.sides.map(\.runs)
        guard let best = scores.max() else { return nil }
        let winners = scores.indices.filter { scores[$0] == best }

        var ranks: [Int: Int] = [:]
        for (slot, runs) in scores.enumerated() {
            ranks[slot] = scores.count { $0 > runs } + 1
        }

        return MatchOutcome(
            winningSlots: winners.count == scores.count ? [] : winners,
            isDraw: winners.count == scores.count,
            rankBySlot: ranks
        )
    }
}
