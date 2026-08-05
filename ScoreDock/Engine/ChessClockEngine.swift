import Foundation

/// Two independent clocks with an increment, a move counter and flag detection (§6.3).
///
/// Sequenced first at M6 as the least difficult of the five, and it is the one board where the
/// date-anchored rule of §6.4 is most obviously load-bearing: a blitz game is decided by tenths, so
/// a clock that drifted even slightly per tick would be worthless.
///
/// Each side stores **time spent**, counting up, and remaining time is derived:
///
///     remaining = baseTime + bonus − spent
///
/// which means nothing ever decrements, and a backgrounded app returns with both clocks correct.
enum ChessClockEngine {
    static func initialState(rules: ChessClockRules, sideCount: Int) -> ChessClockState {
        ChessClockState(sideCount: sideCount)
    }

    /// Time left for one side. The only way to read this clock.
    static func remaining(
        _ side: ChessClockSideState,
        rules: ChessClockRules,
        at now: Date
    ) -> TimeInterval {
        rules.baseTime + side.bonus - side.spent.elapsed(at: now)
    }

    // MARK: - Apply

    static func apply(
        _ action: EngineAction,
        to state: inout ChessClockState,
        rules: ChessClockRules,
        at now: Date
    ) {
        switch action {
        case let .specialised(.pressClock(slot)):
            press(slot, in: &state, rules: rules, at: now)

        case .toggleClock:
            toggle(&state, at: now)

        case let .setClockElapsed(value):
            // On a chess clock the only number anyone thinks in is *time left*, so that is what this
            // sets — the arbiter adding two minutes back is the case it exists for. `spent` is
            // solved for rather than assigned, which keeps the date anchor intact.
            guard let slot = state.activeSlot, state.sides.indices.contains(slot) else { return }
            let limit = rules.baseTime + state.sides[slot].bonus
            state.sides[slot].spent.setElapsed(max(0, limit - value), at: now)
            if value > 0 { state.sides[slot].hasFlagged = false }

        default:
            break
        }
    }

    private static func press(
        _ slot: Int,
        in state: inout ChessClockState,
        rules: ChessClockRules,
        at now: Date
    ) {
        guard state.sides.indices.contains(slot) else { return }

        // Once play has begun, only the side whose turn it is can press — the same as a physical
        // clock, where the opponent's button is already down. This is what stops a fumbled
        // double-tap from handing away a move's worth of time.
        if state.hasStarted, let active = state.activeSlot, active != slot { return }

        let spentBefore = state.turnStartSpent ?? state.sides[slot].spent.elapsed(at: now)
        state.sides[slot].spent.stop(at: now)
        let moveTime = max(0, state.sides[slot].spent.elapsed(at: now) - spentBefore)

        // A move played entirely on a fallen flag earns nothing; the game is already lost on time.
        if remaining(state.sides[slot], rules: rules, at: now) > 0 {
            state.sides[slot].bonus += increment(forMoveTime: moveTime, rules: rules)
        } else {
            state.sides[slot].hasFlagged = true
        }
        state.sides[slot].moves += 1

        let next = (slot + 1) % state.sides.count
        state.sides[next].spent.start(at: now)
        state.activeSlot = next
        state.turnStartSpent = state.sides[next].spent.elapsed(at: now)
        state.hasStarted = true
    }

    /// Fischer and Bronstein differ only in *how much* is added back, which is why one accumulator
    /// serves both: Bronstein's delay is exactly "return the lesser of the delay and the time used".
    private static func increment(forMoveTime moveTime: TimeInterval, rules: ChessClockRules) -> TimeInterval {
        switch rules.incrementMode {
        case .fischer: rules.incrementSeconds
        case .bronstein: min(rules.incrementSeconds, moveTime)
        case .none: 0
        }
    }

    private static func toggle(_ state: inout ChessClockState, at now: Date) {
        guard let slot = state.activeSlot, state.sides.indices.contains(slot) else {
            // Nobody is on the clock yet, so this starts the game with the first side to move.
            guard !state.sides.isEmpty else { return }
            state.sides[0].spent.start(at: now)
            state.activeSlot = 0
            state.turnStartSpent = state.sides[0].spent.elapsed(at: now)
            state.hasStarted = true
            return
        }

        // Pausing does not disturb `turnStartSpent`: `spent` stops accruing while paused, so the
        // move time Bronstein reads back already excludes the interruption.
        state.sides[slot].spent.toggle(at: now)
    }

    static func stopAll(_ state: inout ChessClockState, at now: Date) {
        for index in state.sides.indices { state.sides[index].spent.stop(at: now) }
    }

    // MARK: - Derived

    static func derived(
        _ state: ChessClockState,
        rules: ChessClockRules,
        isFinished: Bool,
        at now: Date
    ) -> DerivedChessClockBoard {
        let remainingBySlot = state.sides.map { max(0, remaining($0, rules: rules, at: now)) }
        let flaggedSlot = remainingBySlot.firstIndex(of: 0)

        let sides = state.sides.enumerated().map { index, side in
            DerivedChessClockBoard.Side(
                slotIndex: index,
                remaining: remainingBySlot[index],
                isActive: state.activeSlot == index && side.spent.isRunning,
                hasFlagged: remainingBySlot[index] <= 0,
                moves: side.moves
            )
        }

        return DerivedChessClockBoard(
            sides: sides,
            activeSlot: state.activeSlot,
            hasStarted: state.hasStarted,
            isRunning: state.sides.contains { $0.spent.isRunning },
            flaggedSlot: flaggedSlot,
            incrementLabel: timeControlLabel(rules),
            isFinished: isFinished
        )
    }

    /// The time control as players write it — "5|3", "1|0".
    ///
    /// The increment is always written, even when it is zero: a bare "1" next to a move count reads
    /// as a number rather than as a time control.
    static func timeControlLabel(_ rules: ChessClockRules) -> String {
        let minutes = Int((rules.baseTime / 60).rounded(.down))
        let seconds = Int(rules.baseTime.truncatingRemainder(dividingBy: 60).rounded())
        let base = seconds == 0 ? "\(minutes)" : "\(minutes):\(String(format: "%02d", seconds))"

        switch rules.incrementMode {
        case .none:
            return "\(base)|0"
        case .fischer:
            return "\(base)|\(Int(rules.incrementSeconds.rounded()))"
        case .bronstein:
            return String(
                localized: "\(base)|\(Int(rules.incrementSeconds.rounded())) Bronstein",
                comment: "Chess time control"
            )
        }
    }

    // MARK: - Outcome

    /// A flag decides the game; nothing else here can.
    ///
    /// ScoreDock is a clock, not an arbiter — it has no idea whether a position was mated,
    /// resigned or agreed drawn. So a game that ends without a flag returns **nil**, and every side
    /// is recorded `.unfinished`, which is the truth. Inventing a draw would put a made-up result
    /// into the player's history.
    static func outcome(
        _ state: ChessClockState,
        rules: ChessClockRules,
        at now: Date
    ) -> MatchOutcome? {
        let remainingBySlot = state.sides.map { max(0, remaining($0, rules: rules, at: now)) }
        guard let flagged = remainingBySlot.firstIndex(of: 0) else { return nil }

        let winners = state.sides.indices.filter { $0 != flagged }
        var ranks: [Int: Int] = [:]
        for index in state.sides.indices { ranks[index] = index == flagged ? 2 : 1 }

        return MatchOutcome(winningSlots: winners, isDraw: false, rankBySlot: ranks)
    }
}
