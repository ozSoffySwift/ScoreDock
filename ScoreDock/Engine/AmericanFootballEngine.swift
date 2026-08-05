import Foundation

/// The American football board (§6.3): game clock *and* play clock, quarter, down and distance,
/// ball-on, possession, timeouts per half.
///
/// Most of what this board needs already exists in the shared vocabulary — score, timeout, period,
/// clock, possession — and the play clock maps exactly onto the shot-clock actions, tap for the
/// full 40 and long-press for the 25 (§4.2). Only down-and-distance and the ball spot are new.
enum AmericanFootballEngine {
    static func initialState(rules: AmericanFootballRules, sideCount: Int) -> AmericanFootballState {
        var state = AmericanFootballState(sideCount: sideCount, playClockFull: rules.playClockNormal)
        state.yardsToGo = rules.yardsToConvert
        state.ballOn = max(0, min(rules.fieldLength, 25))
        return state
    }

    // MARK: - Apply

    static func apply(
        _ action: EngineAction,
        to state: inout AmericanFootballState,
        rules: AmericanFootballRules,
        at now: Date
    ) {
        guard !state.isFinished else { return }

        switch action {
        case let .score(slot, points, _):
            guard state.sides.indices.contains(slot) else { return }
            state.sides[slot].score = max(0, state.sides[slot].score + points)

        case let .timeout(slot, delta):
            guard state.sides.indices.contains(slot) else { return }
            let used = state.sides[slot].timeoutsUsed + delta
            state.sides[slot].timeoutsUsed = min(max(0, used), rules.timeoutsPerHalf)

        case .advancePeriod:
            advance(&state, rules: rules, at: now)

        case .previousPeriod:
            guard state.quarter > 1 else { return }
            state.quarter -= 1
            state.clock.reset(to: 0, at: now)
            state.playClock.reset(to: 0, at: now)

        case .toggleClock:
            state.clock.toggle(at: now)

        case let .setClockElapsed(value):
            state.clock.setElapsed(value, at: now)

        case .toggleShotClock:
            state.playClock.toggle(at: now)

        case let .resetShotClock(full):
            state.playClockDuration = full ? rules.playClockNormal : rules.playClockShort
            // Keeps running if it was running — the play clock restarts as the ball is spotted.
            state.playClock.reset(to: 0, running: state.playClock.isRunning, at: now)

        case let .setPossession(slot):
            let previous = state.possessionSlot
            if let slot, state.sides.indices.contains(slot) {
                state.possessionSlot = slot
            } else {
                state.possessionSlot = nil
            }

            // The ball does not move when possession changes, but the *frame* does: `ballOn` is
            // measured from the possessing team's own goal line, so a turnover mirrors it. Without
            // this, a change of possession on the 30 would read as the other team's 30.
            if let previous, let new = state.possessionSlot, previous != new {
                state.ballOn = max(0, rules.fieldLength - state.ballOn)
            }
            // A turnover is always a fresh set of downs.
            if previous != state.possessionSlot, state.possessionSlot != nil {
                state.down = 1
                state.yardsToGo = firstDownDistance(from: state.ballOn, rules: rules)
            }

        case let .specialised(.setDownAndDistance(down, yardsToGo)):
            state.down = min(max(1, down), max(1, rules.downsToConvert))
            state.yardsToGo = max(0, yardsToGo)

        case let .specialised(.setBallOn(yardLine)):
            state.ballOn = max(0, min(rules.fieldLength, yardLine))

        case .finishMatch:
            state.clock.stop(at: now)
            state.playClock.stop(at: now)
            state.isFinished = true

        default:
            break
        }
    }

    private static func advance(
        _ state: inout AmericanFootballState,
        rules: AmericanFootballRules,
        at now: Date
    ) {
        state.quarter += 1
        state.clock.reset(to: 0, at: now)
        state.playClock.reset(to: 0, at: now)
        state.playClockDuration = rules.playClockNormal

        // Timeouts are *per half*, so they come back entering the second half and at no other
        // quarter boundary.
        if state.quarter == (rules.quarterCount / 2) + 1 {
            for index in state.sides.indices { state.sides[index].timeoutsUsed = 0 }
        }
    }

    /// Ten yards, or the goal line if it is closer — which is what makes it "and goal".
    static func firstDownDistance(from ballOn: Int, rules: AmericanFootballRules) -> Int {
        min(rules.yardsToConvert, max(0, rules.fieldLength - ballOn))
    }

    static func stopAll(_ state: inout AmericanFootballState, at now: Date) {
        state.clock.stop(at: now)
        state.playClock.stop(at: now)
    }

    // MARK: - Derived

    static func derived(
        _ state: AmericanFootballState,
        rules: AmericanFootballRules,
        isFinished: Bool,
        at now: Date
    ) -> DerivedFootballBoard {
        let elapsed = state.clock.elapsed(at: now)
        let remaining = rules.quarterLength - elapsed
        let playRemaining = state.playClockDuration - state.playClock.elapsed(at: now)

        let sides = state.sides.enumerated().map { index, side in
            DerivedFootballBoard.Side(
                slotIndex: index,
                score: side.score,
                timeoutsRemaining: max(0, rules.timeoutsPerHalf - side.timeoutsUsed),
                hasPossession: state.possessionSlot == index
            )
        }

        return DerivedFootballBoard(
            sides: sides,
            gameClock: ClockDisplay(
                value: max(0, remaining),
                isRunning: state.clock.isRunning,
                // Tenths inside the last minute, which is when a football clock is read that way.
                showsTenths: remaining < 60,
                hasExpired: rules.quarterLength > 0 && elapsed >= rules.quarterLength
            ),
            playClock: ClockDisplay(
                value: max(0, playRemaining),
                isRunning: state.playClock.isRunning,
                showsTenths: false,
                hasExpired: playRemaining <= 0,
                style: .secondsOnly
            ),
            quarterLabel: quarterLabel(state.quarter, rules: rules),
            quarter: state.quarter,
            downAndDistance: downAndDistance(state, rules: rules),
            ballOnNumber: paintedYardLine(state.ballOn, rules: rules),
            possessionSlot: state.possessionSlot,
            isFinished: isFinished
        )
    }

    /// The number painted on the field: it counts up to midfield and back down again, so the 70 in
    /// the offence's frame is the 30 on the turf.
    static func paintedYardLine(_ ballOn: Int, rules: AmericanFootballRules) -> Int {
        let clamped = max(0, min(rules.fieldLength, ballOn))
        return min(clamped, rules.fieldLength - clamped)
    }

    static func downAndDistance(_ state: AmericanFootballState, rules: AmericanFootballRules) -> String {
        let down = ordinal(state.down)

        // "And goal" whenever the line to gain *is* the goal line — the distance and the yards
        // remaining coincide.
        if state.yardsToGo >= max(0, rules.fieldLength - state.ballOn) {
            return String(localized: "\(down) & GOAL", comment: "Football down and distance")
        }
        return String(localized: "\(down) & \(state.yardsToGo)", comment: "Football down and distance")
    }

    private static func ordinal(_ down: Int) -> String {
        switch down {
        case 1: String(localized: "1ST", comment: "Football down")
        case 2: String(localized: "2ND", comment: "Football down")
        case 3: String(localized: "3RD", comment: "Football down")
        case 4: String(localized: "4TH", comment: "Football down")
        default: "\(down)"
        }
    }

    static func quarterLabel(_ quarter: Int, rules: AmericanFootballRules) -> String {
        guard quarter <= rules.quarterCount else {
            let extra = quarter - rules.quarterCount
            return extra > 1
                ? String(localized: "OT\(extra)", comment: "Football period")
                : String(localized: "OT", comment: "Football period")
        }
        return String(localized: "Q\(quarter)", comment: "Football period")
    }

    // MARK: - Outcome

    static func outcome(
        _ state: AmericanFootballState,
        rules: AmericanFootballRules,
        at now: Date
    ) -> MatchOutcome? {
        let scores = state.sides.map(\.score)
        guard let best = scores.max() else { return nil }
        let winners = scores.indices.filter { scores[$0] == best }

        var ranks: [Int: Int] = [:]
        for (slot, score) in scores.enumerated() {
            ranks[slot] = scores.count { $0 > score } + 1
        }

        return MatchOutcome(
            winningSlots: winners.count == scores.count ? [] : winners,
            isDraw: winners.count == scores.count,
            rankBySlot: ranks
        )
    }
}
