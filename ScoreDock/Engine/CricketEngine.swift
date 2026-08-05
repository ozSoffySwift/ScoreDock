import Foundation

/// The cricket board (§6.3): runs / wickets / overs.balls, innings, run rates, target, partnership.
///
/// **§17 risk 12 lives here.** Every delivery is an event, so a T20 innings is 120-odd events before
/// extras and a Test is thousands — by a wide margin the largest log the app produces. Two things
/// keep that manageable, and both are already in the shared plumbing rather than special-cased:
/// `SpecialisedStore` snapshots every 50 events, so a replay never walks more than fifty deliveries,
/// and each event is four small columns rather than a serialised state.
///
/// The one thing this engine must never do is derive the ball count by counting events: a wide is a
/// delivery but not a *ball*, so `legalBalls` is tracked explicitly.
enum CricketEngine {
    static func initialState(rules: CricketRules, sideCount: Int) -> CricketState {
        CricketState(firstBattingSlot: 0)
    }

    /// Balls available per innings, or nil when the format does not limit them.
    static func ballLimit(_ rules: CricketRules) -> Int? {
        guard rules.format != .test, rules.oversPerInnings > 0 else { return nil }
        return rules.oversPerInnings * max(1, rules.ballsPerOver)
    }

    static func totalInnings(_ rules: CricketRules) -> Int {
        max(1, rules.inningsPerSide) * 2
    }

    // MARK: - Apply

    static func apply(
        _ action: EngineAction,
        to state: inout CricketState,
        rules: CricketRules,
        at now: Date
    ) {
        guard state.innings.indices.contains(state.currentInnings) else { return }
        guard !state.innings[state.currentInnings].isClosed else { return }

        switch action {
        case let .specialised(.delivery(runs, extra)):
            record(runs: runs, extra: extra, in: &state, rules: rules)

        case let .specialised(.wicket(kind)):
            _ = kind
            var innings = state.innings[state.currentInnings]
            innings.wickets += 1
            // A new pair is a new partnership, whatever the previous one had made.
            innings.partnership = 0
            // A dismissal off a legal delivery still costs a ball. Run-outs off a wide are the
            // exception a scorer handles by entering the wide first, then the wicket.
            innings.legalBalls += 1
            state.innings[state.currentInnings] = innings
            closeIfComplete(&state, rules: rules)

        case .specialised(.endInnings):
            state.innings[state.currentInnings].isClosed = true
            openNextInnings(&state, rules: rules)

        default:
            break
        }
    }

    private static func record(
        runs: Int,
        extra: CricketExtra?,
        in state: inout CricketState,
        rules: CricketRules
    ) {
        var innings = state.innings[state.currentInnings]

        let penalty = extra?.penaltyRuns ?? 0
        let total = max(0, runs) + penalty

        innings.runs += total
        innings.partnership += total

        // Byes and leg-byes are runs the batter did not make, and wides and no-balls are the
        // bowler's penalty — all four go in the extras column, but only the first two count as a
        // ball of the over.
        if let extra {
            innings.extras += extra == .bye || extra == .legBye ? max(0, runs) : penalty
            if extra.countsAsBall { innings.legalBalls += 1 }
        } else {
            innings.legalBalls += 1
        }

        state.innings[state.currentInnings] = innings
        closeIfComplete(&state, rules: rules)
    }

    /// Closes the innings when it is out of wickets, out of balls, or the chase is complete.
    private static func closeIfComplete(_ state: inout CricketState, rules: CricketRules) {
        var innings = state.innings[state.currentInnings]

        let allOut = innings.wickets >= max(1, rules.wicketsPerInnings)
        let outOfBalls = ballLimit(rules).map { innings.legalBalls >= $0 } ?? false

        // A chase ends the moment the target is passed — the remaining balls are not bowled.
        var chased = false
        if state.currentInnings == totalInnings(rules) - 1,
           let target = target(for: state.currentInnings, in: state, rules: rules) {
            chased = innings.runs >= target
        }

        guard allOut || outOfBalls || chased else { return }
        innings.isClosed = true
        state.innings[state.currentInnings] = innings
        openNextInnings(&state, rules: rules)
    }

    private static func openNextInnings(_ state: inout CricketState, rules: CricketRules) {
        let next = state.currentInnings + 1
        guard next < totalInnings(rules) else { return }

        // Sides alternate, so the batting order over four innings is 0, 1, 0, 1.
        let previousSlot = state.innings[state.currentInnings].battingSlot
        state.innings.append(CricketInningsState(battingSlot: previousSlot == 0 ? 1 : 0))
        state.currentInnings = next
    }

    static func closeAll(_ state: inout CricketState) {
        for index in state.innings.indices { state.innings[index].isClosed = true }
    }

    // MARK: - Targets

    /// Runs needed to win the innings at `index`, when it is the last one of the match.
    ///
    /// Written as an aggregate rather than "the other side's total plus one" so a Test's fourth
    /// innings target comes out right: the chasing side has already batted once, and that innings
    /// counts.
    static func target(for index: Int, in state: CricketState, rules: CricketRules) -> Int? {
        guard index == totalInnings(rules) - 1, state.innings.indices.contains(index) else { return nil }
        let slot = state.innings[index].battingSlot

        var opponentRuns = 0
        var ownEarlierRuns = 0
        for (position, innings) in state.innings.enumerated() where position < index {
            if innings.battingSlot == slot { ownEarlierRuns += innings.runs } else { opponentRuns += innings.runs }
        }
        // Nobody has batted yet, so there is nothing to chase.
        guard opponentRuns > 0 || ownEarlierRuns > 0 else { return nil }
        return opponentRuns - ownEarlierRuns + 1
    }

    // MARK: - Derived

    static func derived(
        _ state: CricketState,
        rules: CricketRules,
        sideCount: Int,
        isFinished: Bool,
        at now: Date
    ) -> DerivedCricketBoard {
        let index = min(state.currentInnings, max(0, state.innings.count - 1))
        let innings = state.innings.indices.contains(index)
            ? state.innings[index]
            : CricketInningsState()

        let ballsPerOver = max(1, rules.ballsPerOver)
        let oversBowled = Double(innings.legalBalls) / Double(ballsPerOver)
        let limit = ballLimit(rules)
        let ballsRemaining = limit.map { max(0, $0 - innings.legalBalls) }

        let target = target(for: index, in: state, rules: rules)
        let runsNeeded = target.map { max(0, $0 - innings.runs) }

        var requiredRate: Double?
        if rules.showRequiredRate, let runsNeeded, let ballsRemaining, ballsRemaining > 0 {
            requiredRate = Double(runsNeeded) / (Double(ballsRemaining) / Double(ballsPerOver))
        }

        let completed = state.innings.enumerated().filter { $0.offset < index }.map { _, done in
            DerivedCricketBoard.InningsLine(
                battingSlot: done.battingSlot,
                runs: done.runs,
                wickets: done.wickets,
                oversText: oversText(done.legalBalls, ballsPerOver: ballsPerOver),
                isAllOut: done.wickets >= max(1, rules.wicketsPerInnings)
            )
        }

        return DerivedCricketBoard(
            battingSlot: innings.battingSlot,
            bowlingSlot: innings.battingSlot == 0 ? 1 : 0,
            runs: innings.runs,
            wickets: innings.wickets,
            isAllOut: innings.wickets >= max(1, rules.wicketsPerInnings),
            oversText: oversText(innings.legalBalls, ballsPerOver: ballsPerOver),
            extras: innings.extras,
            partnership: innings.partnership,
            runRate: oversBowled > 0 ? Double(innings.runs) / oversBowled : 0,
            requiredRate: requiredRate,
            target: target,
            runsNeeded: runsNeeded,
            ballsRemaining: ballsRemaining,
            inningsNumber: index + 1,
            completedInnings: completed,
            isFinished: isFinished
        )
    }

    /// `overs.balls`, which is base-`ballsPerOver` and not a decimal: 12.5 plus one ball is 13.0.
    static func oversText(_ legalBalls: Int, ballsPerOver: Int) -> String {
        let per = max(1, ballsPerOver)
        return "\(legalBalls / per).\(legalBalls % per)"
    }

    // MARK: - Outcome

    static func outcome(
        _ state: CricketState,
        rules: CricketRules,
        at now: Date
    ) -> MatchOutcome? {
        var totals: [Int: Int] = [:]
        for innings in state.innings {
            totals[innings.battingSlot, default: 0] += innings.runs
        }
        guard let best = totals.values.max(), !totals.isEmpty else { return nil }

        let winners = totals.filter { $0.value == best }.map(\.key).sorted()
        var ranks: [Int: Int] = [:]
        for (slot, runs) in totals {
            ranks[slot] = totals.values.count { $0 > runs } + 1
        }

        return MatchOutcome(
            winningSlots: winners.count == totals.count ? [] : winners,
            isDraw: winners.count == totals.count,
            rankBySlot: ranks
        )
    }
}
