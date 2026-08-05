import Foundation

/// The workhorse engine — 20 of the 37 presets (§6.1).
///
/// Pure static functions over values. No UI, no SwiftData, no ambient clock: every time-dependent
/// answer takes `now` from the caller, which is what makes the clock behaviour reproducibly
/// testable rather than something you observe by staring at a device for ten minutes.
enum TeamEngine: ScoreEngine {
    static var kind: EngineKind { .team }

    static func initialState(rules: TeamRules, sideCount: Int) -> TeamState {
        var state = TeamState(
            sideCount: sideCount > 0 ? sideCount : rules.sideCount,
            shotClockDuration: rules.shotClockFull
        )
        state.breakDuration = rules.breakDuration
        return state
    }

    // MARK: - Apply

    static func apply(_ action: EngineAction, to state: inout TeamState, rules: TeamRules, at now: Date) {
        // A finished match is immutable. Undo reopens one by replaying the log from the start
        // rather than mutating a finished state, so this never blocks a correction.
        guard !state.isFinished else { return }

        switch action {
        case let .score(slot, points, _):
            guard state.sides.indices.contains(slot) else { return }
            // Never negative: a long-press on a zero score is a mis-tap, not a debt.
            state.sides[slot].score = max(0, state.sides[slot].score + points)

        case let .foul(slot, delta):
            guard state.sides.indices.contains(slot), rules.foulTrackingEnabled else { return }
            state.sides[slot].fouls = max(0, state.sides[slot].fouls + delta)

        case let .timeout(slot, delta):
            guard state.sides.indices.contains(slot) else { return }
            let used = state.sides[slot].timeoutsUsed + delta
            state.sides[slot].timeoutsUsed = min(max(0, used), rules.timeoutCount)

        case .advancePeriod:
            advance(&state, rules: rules, at: now)

        case .previousPeriod:
            guard state.period > 1 else { return }
            state.period -= 1
            state.clock.reset(to: 0, at: now)
            state.shotClock.reset(to: 0, at: now)
            state.shotClockDuration = rules.shotClockFull
            // Going back a period is a correction, so the label override is dropped with it.
            state.periodLabelOverride = nil

        case let .setPeriodLabel(label):
            state.periodLabelOverride = label?.isEmpty == true ? nil : label

        case .toggleClock:
            // A break owns the display while it runs; toggling the clock drives the break instead,
            // so the operator's usual tap keeps working without them having to think about it.
            if state.breakClock != nil {
                state.breakClock?.toggle(at: now)
            } else {
                state.clock.toggle(at: now)
            }

        case let .setClockElapsed(value):
            if state.breakClock != nil {
                state.breakClock?.setElapsed(value, at: now)
            } else {
                state.clock.setElapsed(value, at: now)
            }

        case .toggleShotClock:
            guard rules.shotClockEnabled else { return }
            state.shotClock.toggle(at: now)

        case let .resetShotClock(full):
            guard rules.shotClockEnabled else { return }
            state.shotClockDuration = full ? rules.shotClockFull : rules.shotClockShort
            // Resetting keeps it running if it was running — the shot clock restarts on a live ball.
            state.shotClock.reset(to: 0, running: state.shotClock.isRunning, at: now)

        case let .setPossession(slot):
            guard rules.possessionArrowEnabled else { return }
            if let slot, state.sides.indices.contains(slot) {
                state.possessionSlot = slot
            } else {
                state.possessionSlot = nil
            }

        case let .startBreak(duration):
            // Bank the main clock at exactly its current value; `endBreak` hands control back there.
            state.clock.stop(at: now)
            state.shotClock.stop(at: now)
            state.breakDuration = duration > 0 ? duration : rules.breakDuration
            state.breakClock = MatchClock(accumulated: 0, startedAt: now)

        case .endBreak:
            state.breakClock = nil

        case .setBracketWinner, .adjustRecord, .specialised:
            // List-board (§6.5) and bespoke-board (§6.3) actions have no meaning on a team
            // scoreboard. Handled explicitly rather than by a `default`, so the exhaustiveness check
            // keeps forcing every engine to decide what a newly added action means to it.
            break

        case .finishMatch:
            state.clock.stop(at: now)
            state.shotClock.stop(at: now)
            state.breakClock = nil
            state.isFinished = true
        }
    }

    private static func advance(_ state: inout TeamState, rules: TeamRules, at now: Date) {
        state.period += 1
        state.clock.reset(to: 0, at: now)
        state.shotClock.reset(to: 0, at: now)
        state.shotClockDuration = rules.shotClockFull
        state.breakClock = nil
        state.periodLabelOverride = nil

        if rules.foulsResetPerPeriod {
            for index in state.sides.indices { state.sides[index].fouls = 0 }
        }

        // Half-time is the boundary *after* half the periods, so a 4-quarter game resets entering
        // Q3 and a 2-half game entering H2.
        if rules.timeoutsResetAtHalf, state.period == (rules.periodCount / 2) + 1 {
            for index in state.sides.indices { state.sides[index].timeoutsUsed = 0 }
        }
    }

    // MARK: - Derived

    static func derived(_ state: TeamState, rules: TeamRules, at now: Date) -> DerivedBoard {
        let sides = state.sides.enumerated().map { index, side in
            DerivedSide(
                slotIndex: index,
                score: side.score,
                fouls: rules.foulTrackingEnabled ? side.fouls : nil,
                timeoutsRemaining: rules.timeoutCount > 0
                    ? max(0, rules.timeoutCount - side.timeoutsUsed)
                    : nil,
                isInBonus: rules.foulTrackingEnabled
                    && rules.bonusThreshold.map { side.fouls >= $0 } == true,
                hasFouledOut: rules.foulTrackingEnabled
                    && rules.foulLimit > 0
                    && side.fouls >= rules.foulLimit
            )
        }

        return DerivedBoard(
            sides: sides,
            primaryClock: primaryClock(state, rules: rules, at: now),
            periodLabel: state.periodLabelOverride ?? rules.label(forPeriod: state.period),
            period: state.period,
            shotClock: shotClockDisplay(state, rules: rules, at: now),
            possessionSlot: rules.possessionArrowEnabled ? state.possessionSlot : nil,
            isBreak: state.isOnBreak,
            isFinished: state.isFinished
        )
    }

    private static func primaryClock(
        _ state: TeamState,
        rules: TeamRules,
        at now: Date
    ) -> ClockDisplay {
        // A break replaces the main timer entirely while it runs (§6.1).
        if let breakClock = state.breakClock {
            let remaining = state.breakDuration - breakClock.elapsed(at: now)
            return ClockDisplay(
                value: max(0, remaining),
                isRunning: breakClock.isRunning,
                showsTenths: false,
                hasExpired: remaining <= 0
            )
        }

        let elapsed = state.clock.elapsed(at: now)
        let remaining = rules.periodLength - elapsed
        let hasExpired = rules.periodLength > 0 && elapsed >= rules.periodLength

        // A count-up clock keeps running past the period length — that is added time, not an
        // overrun, so it is never clamped.
        let value = rules.countsUp ? elapsed : max(0, remaining)

        return ClockDisplay(
            value: value,
            isRunning: state.clock.isRunning,
            // Tenths are keyed off time *remaining* in both directions, so a count-up clock still
            // gets them in the closing seconds.
            showsTenths: rules.periodLength > 0 && rules.showsTenths(atRemaining: max(0, remaining)),
            hasExpired: hasExpired
        )
    }

    private static func shotClockDisplay(
        _ state: TeamState,
        rules: TeamRules,
        at now: Date
    ) -> ClockDisplay? {
        guard rules.shotClockEnabled else { return nil }
        let remaining = state.shotClockDuration - state.shotClock.elapsed(at: now)
        return ClockDisplay(
            value: max(0, remaining),
            isRunning: state.shotClock.isRunning,
            // A shot clock shows tenths in its last five seconds, which is when they matter.
            showsTenths: remaining < 5,
            hasExpired: remaining <= 0,
            style: .secondsOnly
        )
    }

    // MARK: - Outcome

    static func outcome(_ state: TeamState, rules: TeamRules, at now: Date) -> MatchOutcome? {
        guard state.isFinished else { return nil }

        let scores = state.sides.map(\.score)
        guard let best = scores.max() else { return nil }
        let winners = scores.indices.filter { scores[$0] == best }

        // Standard competition ranking: two sides tied on 40 both rank 1, and the next distinct
        // score ranks 3. Ties share a rank rather than being broken arbitrarily (§6.5).
        var rankBySlot: [Int: Int] = [:]
        for (slot, score) in scores.enumerated() {
            rankBySlot[slot] = scores.count { $0 > score } + 1
        }

        return MatchOutcome(
            winningSlots: winners.count == scores.count ? [] : winners,
            isDraw: winners.count == scores.count,
            rankBySlot: rankBySlot
        )
    }
}
