import Foundation

/// A multi-racer stopwatch with per-racer laps, splits and running order (§6.3).
///
/// Sequenced second at M6. One clock serves the whole field — a race has a single start gun, and
/// every racer's time is a position on that one timeline. Storing **crossing times** rather than lap
/// durations is what makes undo work: a mis-tapped lap is removed and the neighbouring durations
/// fall out correctly, with nothing to recompute.
enum RaceTimerEngine {
    static func initialState(rules: RaceTimerRules, sideCount: Int) -> RaceTimerState {
        RaceTimerState(racerCount: sideCount > 0 ? sideCount : rules.racerCount)
    }

    // MARK: - Apply

    static func apply(
        _ action: EngineAction,
        to state: inout RaceTimerState,
        rules: RaceTimerRules,
        at now: Date
    ) {
        switch action {
        case .toggleClock:
            state.clock.toggle(at: now)

        case let .setClockElapsed(value):
            state.clock.setElapsed(value, at: now)

        case let .specialised(.recordLap(slot)):
            guard state.racers.indices.contains(slot) else { return }
            // A lap before the gun is a mis-tap, not a zero-second lap. Refusing it is kinder than
            // recording a split at 0.000 that the operator then has to find and undo.
            guard state.clock.isRunning || state.clock.elapsed(at: now) > 0 else { return }
            guard state.racers[slot].finishedAt == nil else { return }

            state.racers[slot].splits.append(state.clock.elapsed(at: now))

            // A fixed-distance race finishes a racer on their final lap without a second tap.
            if let laps = rules.lapCount, state.racers[slot].splits.count >= laps {
                state.racers[slot].finishedAt = state.racers[slot].splits.last
            }

        case let .specialised(.finishRacer(slot)):
            guard state.racers.indices.contains(slot) else { return }
            guard state.racers[slot].finishedAt == nil else { return }
            state.racers[slot].finishedAt = state.clock.elapsed(at: now)

        default:
            break
        }
    }

    static func stopAll(_ state: inout RaceTimerState, at now: Date) {
        state.clock.stop(at: now)
    }

    // MARK: - Derived

    static func derived(
        _ state: RaceTimerState,
        rules: RaceTimerRules,
        isFinished: Bool,
        at now: Date
    ) -> DerivedRaceTimerBoard {
        let elapsed = state.clock.elapsed(at: now)

        let unplaced = state.racers.enumerated().map { index, racer in
            DerivedRaceTimerBoard.Racer(
                slotIndex: index,
                position: nil,
                lapsCompleted: racer.splits.count,
                elapsed: racer.finishedAt ?? elapsed,
                lastLap: lapDurations(racer.splits).last,
                bestLap: lapDurations(racer.splits).min(),
                hasFinished: racer.finishedAt != nil
            )
        }

        return DerivedRaceTimerBoard(
            rows: placed(unplaced, state: state, rules: rules),
            raceClock: ClockDisplay(
                value: elapsed,
                isRunning: state.clock.isRunning,
                showsTenths: true,
                hasExpired: false
            ),
            hasStarted: state.clock.isRunning || elapsed > 0,
            lapCount: rules.lapCount,
            isFinished: isFinished
        )
    }

    /// Lap durations from cumulative crossing times.
    static func lapDurations(_ splits: [TimeInterval]) -> [TimeInterval] {
        splits.enumerated().map { index, split in
            split - (index > 0 ? splits[index - 1] : 0)
        }
    }

    /// Sorts into running order and numbers the placings.
    ///
    /// A racer with nothing on the board yet gets **no position** rather than an arbitrary one.
    /// Handing out 1st through 8th at the start line, before anyone has crossed anything, would be
    /// inventing a result — and the field is in slot order at that point purely by accident.
    private static func placed(
        _ racers: [DerivedRaceTimerBoard.Racer],
        state: RaceTimerState,
        rules: RaceTimerRules
    ) -> [DerivedRaceTimerBoard.Racer] {
        let sorted = racers.sorted { lhs, rhs in
            // Anyone who has finished is ahead of anyone still out on the course.
            if lhs.hasFinished != rhs.hasFinished { return lhs.hasFinished }

            if lhs.hasFinished, rhs.hasFinished {
                if lhs.elapsed != rhs.elapsed {
                    return rules.lowerTimeWins ? lhs.elapsed < rhs.elapsed : lhs.elapsed > rhs.elapsed
                }
                return lhs.slotIndex < rhs.slotIndex
            }

            // Still racing: more laps leads, and on equal laps whoever got there first.
            if lhs.lapsCompleted != rhs.lapsCompleted { return lhs.lapsCompleted > rhs.lapsCompleted }
            let left = state.racers[lhs.slotIndex].splits.last
            let right = state.racers[rhs.slotIndex].splits.last
            if let left, let right, left != right { return left < right }
            return lhs.slotIndex < rhs.slotIndex
        }

        var position = 0
        return sorted.map { racer in
            var updated = racer
            guard racer.hasFinished || racer.lapsCompleted > 0 else { return updated }
            position += 1
            updated.position = position
            return updated
        }
    }

    // MARK: - Outcome

    static func outcome(
        _ state: RaceTimerState,
        rules: RaceTimerRules,
        at now: Date
    ) -> MatchOutcome? {
        let board = derived(state, rules: rules, isFinished: true, at: now)
        let placedRows = board.rows.filter { $0.position != nil }
        guard !placedRows.isEmpty else { return nil }

        var ranks: [Int: Int] = [:]
        for row in board.rows { ranks[row.slotIndex] = row.position ?? placedRows.count + 1 }

        let winners = placedRows.filter { $0.position == 1 }.map(\.slotIndex)
        return MatchOutcome(winningSlots: winners, isDraw: false, rankBySlot: ranks)
    }
}
