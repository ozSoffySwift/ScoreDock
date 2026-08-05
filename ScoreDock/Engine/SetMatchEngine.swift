import Foundation

/// The set-match engine — 8 presets, rally scoring (§6.2).
///
/// Three notations share one engine because they share one shape: points roll into a unit, units
/// roll into sets, sets decide the match. What differs is the size of each rung.
///
/// | Notation | Point → | → Set |
/// |---|---|---|
/// | `numeric` | points accumulate in the set directly | first to `pointsPerSet`, win by two, hard cap |
/// | `tennis` | 0/15/30/40/Ad → a game | first to 6 games by two, or a tiebreak at 6–6 |
/// | `dartsCountdown` | a visit subtracts from 501 → a leg | `legsPerSet` legs |
///
/// Pure value logic, like `TeamEngine` — no UI, no store, no ambient clock.
enum SetMatchEngine: ScoreEngine {
    static var kind: EngineKind { .setMatch }

    static func initialState(rules: SetMatchRules, sideCount: Int) -> SetMatchState {
        var state = SetMatchState(
            sideCount: sideCount > 0 ? sideCount : 2,
            startScore: rules.startScore
        )
        // A best-of-1 "deciding set" that is itself a match tiebreak starts as one.
        state.isTiebreak = rules.matchTiebreak && rules.setsToWin == 1
        return state
    }

    // MARK: - Apply

    static func apply(_ action: EngineAction, to state: inout SetMatchState, rules: SetMatchRules, at now: Date) {
        guard !state.isFinished else { return }

        switch action {
        case let .score(slot, points, _):
            guard state.sides.indices.contains(slot) else { return }
            switch rules.notation {
            case .numeric: awardNumeric(slot: slot, points: points, to: &state, rules: rules)
            case .tennis: awardTennis(slot: slot, points: points, to: &state, rules: rules)
            case .dartsCountdown: awardDarts(slot: slot, visit: points, to: &state, rules: rules)
            }

        case let .setPossession(slot):
            // Possession *is* serve in this engine — the same operator gesture, a different word.
            guard rules.serveTracking else { return }
            if let slot, state.sides.indices.contains(slot) {
                state.servingSlot = slot
                state.servesInRotation = 0
            } else {
                state.servingSlot = nil
            }

        case .finishMatch:
            state.isFinished = true

        default:
            // Clocks, fouls, timeouts and periods have no meaning here. Ignored rather than
            // mis-applied — a stray team-engine action in a replayed log must not corrupt state.
            break
        }
    }

    // MARK: Numeric rally scoring

    private static func awardNumeric(
        slot: Int,
        points: Int,
        to state: inout SetMatchState,
        rules: SetMatchRules
    ) {
        state.sides[slot].points = max(0, state.sides[slot].points + points)
        // A correction adjusts the score but never completes a set or moves the serve.
        guard points > 0 else { return }

        advanceServe(&state, rules: rules, pointWinner: slot)

        let target = setTarget(state, rules: rules)
        let mine = state.sides[slot].points
        let best = bestOpposing(state, excluding: slot)

        let reachedTarget = mine >= target
        let clearedByTwo = !rules.winByTwo || mine - best >= 2
        let hitCap = rules.hardCap.map { mine >= $0 } ?? false

        if reachedTarget, clearedByTwo || hitCap {
            completeSet(&state, rules: rules, winner: slot, scores: state.sides.map(\.points))
        }
    }

    // MARK: Tennis

    private static func awardTennis(
        slot: Int,
        points: Int,
        to state: inout SetMatchState,
        rules: SetMatchRules
    ) {
        state.sides[slot].points = max(0, state.sides[slot].points + points)
        guard points > 0 else { return }

        let target = state.isTiebreak
            ? (isMatchTiebreak(state, rules: rules) ? rules.matchTiebreakPoints : rules.tiebreakPoints)
            : 4

        let mine = state.sides[slot].points
        let best = bestOpposing(state, excluding: slot)

        // Deuce and advantage fall straight out of "win by two": at 3–3 neither side can reach a
        // two-point gap without first going to advantage.
        guard mine >= target, mine - best >= 2 else {
            if state.isTiebreak { advanceServe(&state, rules: rules, pointWinner: slot) }
            return
        }

        completeGame(&state, rules: rules, winner: slot)
    }

    private static func completeGame(_ state: inout SetMatchState, rules: SetMatchRules, winner: Int) {
        let wasTiebreak = state.isTiebreak
        state.sides[winner].gamesWon += 1
        for index in state.sides.indices { state.sides[index].points = 0 }

        // Serve alternates every game.
        if rules.serveTracking, let serving = state.servingSlot {
            state.servingSlot = (serving + 1) % state.sides.count
        }

        if wasTiebreak {
            state.isTiebreak = false
            completeSet(&state, rules: rules, winner: winner, scores: state.sides.map(\.gamesWon))
            return
        }

        let mine = state.sides[winner].gamesWon
        let best = state.sides.enumerated().filter { $0.offset != winner }.map(\.element.gamesWon).max() ?? 0

        if mine >= rules.pointsPerSet, mine - best >= 2 {
            completeSet(&state, rules: rules, winner: winner, scores: state.sides.map(\.gamesWon))
        } else if rules.tiebreakEnabled, mine == rules.pointsPerSet, best == rules.pointsPerSet {
            // 6–6: the set is decided by a tiebreak rather than running on indefinitely.
            state.isTiebreak = true
        }
    }

    // MARK: Darts

    private static func awardDarts(
        slot: Int,
        visit: Int,
        to state: inout SetMatchState,
        rules: SetMatchRules
    ) {
        guard visit > 0 else {
            // A correction adds the points back, e.g. undoing a mis-keyed visit.
            state.sides[slot].remaining = min(rules.startScore, state.sides[slot].remaining - visit)
            return
        }

        let remaining = state.sides[slot].remaining - visit

        // Bust: past zero, or left on one when the leg must finish on a double. The visit does not
        // count and the score reverts — which is why this engine subtracts rather than accumulates.
        if remaining < 0 || (rules.doubleOut && remaining == 1) {
            state.lastVisitBusted = true
            advanceServe(&state, rules: rules, pointWinner: nil)
            return
        }

        state.lastVisitBusted = false

        guard remaining == 0 else {
            state.sides[slot].remaining = remaining
            advanceServe(&state, rules: rules, pointWinner: nil)
            return
        }

        // Leg won.
        state.sides[slot].legsWon += 1
        for index in state.sides.indices { state.sides[index].remaining = rules.startScore }
        advanceServe(&state, rules: rules, pointWinner: nil)

        if state.sides[slot].legsWon >= rules.legsPerSet {
            completeSet(&state, rules: rules, winner: slot, scores: state.sides.map(\.legsWon))
        }
    }

    // MARK: Set and match completion

    private static func completeSet(
        _ state: inout SetMatchState,
        rules: SetMatchRules,
        winner: Int,
        scores: [Int]
    ) {
        state.completedSets.append(scores)
        state.sides[winner].setsWon += 1

        for index in state.sides.indices {
            state.sides[index].points = 0
            state.sides[index].gamesWon = 0
            state.sides[index].legsWon = 0
            state.sides[index].remaining = rules.startScore
        }
        state.isTiebreak = false

        if state.sides[winner].setsWon >= rules.setsToWin {
            state.isFinished = true
            return
        }

        // A deciding set played as a match tiebreak starts in tiebreak mode.
        if rules.matchTiebreak, isDecidingSet(state, rules: rules) {
            state.isTiebreak = true
        }
    }

    // MARK: Helpers

    /// The deciding set is the one where every side is a set away from the match.
    static func isDecidingSet(_ state: SetMatchState, rules: SetMatchRules) -> Bool {
        state.sides.allSatisfy { $0.setsWon == rules.setsToWin - 1 } && rules.setsToWin > 1
    }

    static func isMatchTiebreak(_ state: SetMatchState, rules: SetMatchRules) -> Bool {
        rules.matchTiebreak && state.isTiebreak && isDecidingSet(state, rules: rules)
    }

    private static func setTarget(_ state: SetMatchState, rules: SetMatchRules) -> Int {
        isDecidingSet(state, rules: rules) ? rules.decidingSetPoints : rules.pointsPerSet
    }

    private static func bestOpposing(_ state: SetMatchState, excluding slot: Int) -> Int {
        state.sides.enumerated().filter { $0.offset != slot }.map(\.element.points).max() ?? 0
    }

    /// Moves the serve on.
    ///
    /// Two models, chosen by `servesPerRotation`: alternate every N points (table tennis serves in
    /// pairs), or the winner of the rally serves next (volleyball, badminton, squash).
    private static func advanceServe(
        _ state: inout SetMatchState,
        rules: SetMatchRules,
        pointWinner: Int?
    ) {
        guard rules.serveTracking, state.sides.count > 1 else { return }

        if rules.servesPerRotation > 1 {
            state.servesInRotation += 1
            if state.servesInRotation >= rules.servesPerRotation {
                state.servesInRotation = 0
                state.servingSlot = ((state.servingSlot ?? 0) + 1) % state.sides.count
            }
        } else if let pointWinner {
            state.servingSlot = pointWinner
        } else {
            // Darts and other alternating-throw formats.
            state.servingSlot = ((state.servingSlot ?? 0) + 1) % state.sides.count
        }
    }

    // MARK: - Derived

    static func derived(
        _ state: SetMatchState,
        rules: SetMatchRules,
        at now: Date
    ) -> DerivedSetMatchBoard {
        let sides = state.sides.enumerated().map { index, side -> DerivedSetMatchBoard.Side in
            DerivedSetMatchBoard.Side(
                slotIndex: index,
                setsWon: side.setsWon,
                pointsText: pointsText(state, rules: rules, slot: index),
                gamesWon: rules.notation == .tennis ? side.gamesWon : nil,
                legsWon: rules.notation == .dartsCountdown ? side.legsWon : nil,
                isServing: rules.serveTracking && state.servingSlot == index,
                checkout: rules.notation == .dartsCountdown
                    ? DartsCheckout.suggestion(for: side.remaining, doubleOut: rules.doubleOut)
                    : nil
            )
        }

        return DerivedSetMatchBoard(
            sides: sides,
            completedSets: state.completedSets,
            currentSetNumber: state.currentSetNumber,
            notation: rules.notation,
            isTiebreak: state.isTiebreak,
            isMatchTiebreak: isMatchTiebreak(state, rules: rules),
            isDecidingSet: isDecidingSet(state, rules: rules),
            lastVisitBusted: state.lastVisitBusted,
            isFinished: state.isFinished
        )
    }

    /// The current game's score, in the notation's own language.
    static func pointsText(_ state: SetMatchState, rules: SetMatchRules, slot: Int) -> String {
        guard let side = state.side(slot) else { return "0" }

        switch rules.notation {
        case .numeric:
            return "\(side.points)"

        case .dartsCountdown:
            return "\(side.remaining)"

        case .tennis:
            // A tiebreak is scored in plain numbers even in tennis.
            if state.isTiebreak { return "\(side.points)" }

            let best = state.sides.enumerated()
                .filter { $0.offset != slot }
                .map(\.element.points)
                .max() ?? 0

            if side.points >= 3, best >= 3 {
                if side.points == best { return "40" }
                return side.points > best
                    ? String(localized: "AD", comment: "Tennis advantage")
                    : "40"
            }
            return ["0", "15", "30", "40"][min(max(0, side.points), 3)]
        }
    }

    // MARK: - Outcome

    static func outcome(_ state: SetMatchState, rules: SetMatchRules, at now: Date) -> MatchOutcome? {
        guard state.isFinished else { return nil }

        let sets = state.sides.map(\.setsWon)
        guard let best = sets.max() else { return nil }
        let winners = sets.indices.filter { sets[$0] == best }

        var rankBySlot: [Int: Int] = [:]
        for (slot, won) in sets.enumerated() {
            rankBySlot[slot] = sets.count { $0 > won } + 1
        }

        return MatchOutcome(
            winningSlots: winners.count == sets.count ? [] : winners,
            // A rally-scored match cannot end level unless it was abandoned mid-way.
            isDraw: winners.count == sets.count,
            rankBySlot: rankBySlot
        )
    }
}
