import Foundation
import Testing

@testable import ScoreDock

/// The team engine covers 20 of the 37 presets, so these rules are the ones most users meet (§6.1).
@Suite("Team engine (§6.1)")
struct TeamEngineTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.t0.addingTimeInterval(seconds) }

    /// FIBA basketball — the preset the M1 exit criterion is written against.
    private var basketball: TeamRules {
        BuiltInCatalog.bySlug["basketball"]?.rules.teamRules ?? TeamRules()
    }

    private func newState(_ rules: TeamRules) -> TeamState {
        TeamEngine.initialState(rules: rules, sideCount: 2)
    }

    private func apply(_ actions: [EngineAction], to state: inout TeamState, rules: TeamRules, at date: Date) {
        for action in actions {
            TeamEngine.apply(action, to: &state, rules: rules, at: date)
        }
    }

    // MARK: Scoring

    @Test("Scoring adds and subtracts, and never goes negative")
    func scoring() {
        let rules = basketball
        var state = newState(rules)

        apply([.score(slot: 0, points: 3), .score(slot: 0, points: 2)], to: &state, rules: rules, at: at(0))
        #expect(state.sides[0].score == 5)
        #expect(state.sides[1].score == 0)

        TeamEngine.apply(.score(slot: 0, points: -1), to: &state, rules: rules, at: at(0))
        #expect(state.sides[0].score == 4)

        // A long-press on a zero score is a mis-tap, not a debt.
        TeamEngine.apply(.score(slot: 1, points: -5), to: &state, rules: rules, at: at(0))
        #expect(state.sides[1].score == 0)
    }

    @Test("An out-of-range slot is ignored rather than trapping")
    func outOfRangeSlot() {
        let rules = basketball
        var state = newState(rules)
        TeamEngine.apply(.score(slot: 7, points: 3), to: &state, rules: rules, at: at(0))
        #expect(state.sides.map(\.score) == [0, 0])
    }

    // MARK: Fouls

    @Test("Fouls track, floor at zero, and light the bonus at the threshold")
    func fouls() {
        let rules = basketball  // limit 5, bonus at 5
        var state = newState(rules)

        for _ in 0 ..< 4 {
            TeamEngine.apply(.foul(slot: 0, delta: 1), to: &state, rules: rules, at: at(0))
        }
        var board = TeamEngine.derived(state, rules: rules, at: at(0))
        #expect(board.sides[0].fouls == 4)
        #expect(board.sides[0].isInBonus == false)

        TeamEngine.apply(.foul(slot: 0, delta: 1), to: &state, rules: rules, at: at(0))
        board = TeamEngine.derived(state, rules: rules, at: at(0))
        #expect(board.sides[0].isInBonus == true)
        #expect(board.sides[0].hasFouledOut == true)

        TeamEngine.apply(.foul(slot: 0, delta: -10), to: &state, rules: rules, at: at(0))
        #expect(state.sides[0].fouls == 0)
    }

    @Test("Fouls are ignored entirely when tracking is off")
    func foulsDisabled() {
        var rules = basketball
        rules.foulTrackingEnabled = false
        var state = newState(rules)

        TeamEngine.apply(.foul(slot: 0, delta: 1), to: &state, rules: rules, at: at(0))
        #expect(state.sides[0].fouls == 0)
        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).sides[0].fouls == nil)
    }

    // MARK: Timeouts

    @Test("Timeouts clamp between zero and the allowance")
    func timeouts() {
        var rules = basketball
        rules.timeoutCount = 3
        var state = newState(rules)

        for _ in 0 ..< 5 {
            TeamEngine.apply(.timeout(slot: 0, delta: 1), to: &state, rules: rules, at: at(0))
        }
        #expect(state.sides[0].timeoutsUsed == 3)
        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).sides[0].timeoutsRemaining == 0)

        TeamEngine.apply(.timeout(slot: 0, delta: -1), to: &state, rules: rules, at: at(0))
        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).sides[0].timeoutsRemaining == 1)
    }

    // MARK: Periods

    @Test("Advancing a period resets the clock and per-period fouls")
    func periodAdvance() {
        var rules = basketball
        rules.foulsResetPerPeriod = true
        var state = newState(rules)

        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.foul(slot: 0, delta: 3), to: &state, rules: rules, at: at(100))
        TeamEngine.apply(.advancePeriod, to: &state, rules: rules, at: at(100))

        #expect(state.period == 2)
        #expect(state.sides[0].fouls == 0)
        #expect(state.clock.elapsed(at: at(200)) == 0, "clock restarts stopped at zero")
        #expect(!state.clock.isRunning)
    }

    @Test("Fouls carry across periods when the rules say so")
    func foulsCarryAcrossPeriods() {
        var rules = basketball
        rules.foulsResetPerPeriod = false
        var state = newState(rules)

        TeamEngine.apply(.foul(slot: 0, delta: 3), to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.advancePeriod, to: &state, rules: rules, at: at(0))
        #expect(state.sides[0].fouls == 3)
    }

    @Test("Timeouts reset at the half boundary, not at every period")
    func timeoutsResetAtHalf() {
        var rules = basketball
        rules.periodCount = 4
        rules.timeoutCount = 5
        rules.timeoutsResetAtHalf = true
        var state = newState(rules)

        TeamEngine.apply(.timeout(slot: 0, delta: 2), to: &state, rules: rules, at: at(0))

        TeamEngine.apply(.advancePeriod, to: &state, rules: rules, at: at(0))  // → Q2
        #expect(state.sides[0].timeoutsUsed == 2, "no reset entering Q2")

        TeamEngine.apply(.advancePeriod, to: &state, rules: rules, at: at(0))  // → Q3, half
        #expect(state.sides[0].timeoutsUsed == 0)
    }

    @Test("Two-half games reset timeouts entering the second half")
    func timeoutsResetTwoHalves() {
        var rules = TeamRules()
        rules.periodCount = 2
        rules.timeoutCount = 3
        rules.timeoutsResetAtHalf = true
        var state = newState(rules)

        TeamEngine.apply(.timeout(slot: 0, delta: 1), to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.advancePeriod, to: &state, rules: rules, at: at(0))
        #expect(state.sides[0].timeoutsUsed == 0)
    }

    @Test("Period labels fall back, override, and roll into overtime")
    func periodLabels() {
        let rules = basketball
        var state = newState(rules)

        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).periodLabel == "Q1")

        TeamEngine.apply(.setPeriodLabel("OT"), to: &state, rules: rules, at: at(0))
        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).periodLabel == "OT")

        // Advancing clears the override — the next period is a fresh one.
        TeamEngine.apply(.advancePeriod, to: &state, rules: rules, at: at(0))
        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).periodLabel == "Q2")

        for _ in 0 ..< 3 { TeamEngine.apply(.advancePeriod, to: &state, rules: rules, at: at(0)) }
        #expect(state.period == 5)
        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).periodLabel == "OT")
    }

    @Test("Going back a period is possible but never below the first")
    func previousPeriod() {
        let rules = basketball
        var state = newState(rules)
        TeamEngine.apply(.previousPeriod, to: &state, rules: rules, at: at(0))
        #expect(state.period == 1)

        TeamEngine.apply(.advancePeriod, to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.previousPeriod, to: &state, rules: rules, at: at(0))
        #expect(state.period == 1)
    }

    // MARK: Clock direction

    @Test("A countdown clamps at zero and reports expiry")
    func countdownExpiry() {
        var rules = basketball          // 10 minute periods, counts down
        rules.periodLength = 600
        var state = newState(rules)

        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        var board = TeamEngine.derived(state, rules: rules, at: at(60))
        #expect(board.primaryClock.value == 540)
        #expect(!board.primaryClock.hasExpired)

        board = TeamEngine.derived(state, rules: rules, at: at(600))
        #expect(board.primaryClock.value == 0)
        #expect(board.primaryClock.hasExpired)

        // Past the buzzer it stays at zero rather than going negative.
        board = TeamEngine.derived(state, rules: rules, at: at(700))
        #expect(board.primaryClock.value == 0)
    }

    /// Soccer runs past 45:00 into added time — clamping here would be a bug, not a safeguard.
    @Test("A count-up clock runs past the period length into added time")
    func countUpAddedTime() {
        var rules = TeamRules()
        rules.countsUp = true
        rules.periodLength = 2700
        var state = newState(rules)

        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        let board = TeamEngine.derived(state, rules: rules, at: at(2880))
        #expect(board.primaryClock.value == 2880)
        #expect(board.primaryClock.hasExpired, "past regulation, but still running")
    }

    @Test("Tenths appear only below the configured threshold")
    func tenths() {
        var rules = basketball
        rules.showTenths = true
        rules.tenthsThreshold = 60
        rules.periodLength = 600
        var state = newState(rules)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        #expect(!TeamEngine.derived(state, rules: rules, at: at(500)).primaryClock.showsTenths)
        #expect(TeamEngine.derived(state, rules: rules, at: at(560)).primaryClock.showsTenths)
    }

    // MARK: Shot clock

    @Test("The shot clock resets to full on tap and short on long-press")
    func shotClock() {
        let rules = basketball  // 24 / 14
        var state = newState(rules)

        TeamEngine.apply(.toggleShotClock, to: &state, rules: rules, at: at(0))
        #expect(TeamEngine.derived(state, rules: rules, at: at(10)).shotClock?.value == 14)

        TeamEngine.apply(.resetShotClock(full: false), to: &state, rules: rules, at: at(10))
        #expect(state.shotClockDuration == 14)
        #expect(TeamEngine.derived(state, rules: rules, at: at(10)).shotClock?.value == 14)
        #expect(TeamEngine.derived(state, rules: rules, at: at(20)).shotClock?.value == 4)

        TeamEngine.apply(.resetShotClock(full: true), to: &state, rules: rules, at: at(20))
        #expect(TeamEngine.derived(state, rules: rules, at: at(20)).shotClock?.value == 24)
        #expect(state.shotClock.isRunning, "a reset keeps it running on a live ball")
    }

    @Test("The shot clock is absent when the rules disable it")
    func shotClockDisabled() {
        var rules = basketball
        rules.shotClockEnabled = false
        var state = newState(rules)
        TeamEngine.apply(.toggleShotClock, to: &state, rules: rules, at: at(0))
        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).shotClock == nil)
    }

    // MARK: Break

    /// §6.1: the break replaces the main timer, then hands control back **at exactly the paused
    /// value**. Losing that value would silently rob a team of match time.
    @Test("A break replaces the clock and hands it back at exactly the paused value")
    func breakHandsBackExactly() {
        var rules = basketball
        rules.periodLength = 600
        var state = newState(rules)

        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        // 3:20 played, so 6:40 remains.
        TeamEngine.apply(.startBreak(900), to: &state, rules: rules, at: at(200))

        #expect(state.isOnBreak)
        #expect(!state.clock.isRunning)

        var board = TeamEngine.derived(state, rules: rules, at: at(200))
        #expect(board.isBreak)
        #expect(board.primaryClock.value == 900, "the break owns the display")

        board = TeamEngine.derived(state, rules: rules, at: at(400))
        #expect(board.primaryClock.value == 700)

        // Fifteen real minutes later, regulation time is untouched.
        TeamEngine.apply(.endBreak, to: &state, rules: rules, at: at(1100))
        board = TeamEngine.derived(state, rules: rules, at: at(1100))
        #expect(!board.isBreak)
        #expect(board.primaryClock.value == 400, "6:40 remaining, exactly as paused")
    }

    @Test("Toggling the clock during a break drives the break")
    func toggleDuringBreak() {
        let rules = basketball
        var state = newState(rules)
        TeamEngine.apply(.startBreak(600), to: &state, rules: rules, at: at(0))

        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(100))
        #expect(state.breakClock?.isRunning == false)
        #expect(!state.clock.isRunning, "regulation time stays paused")
    }

    // MARK: Possession

    @Test("Possession sets and clears, and only when the arrow is enabled")
    func possession() {
        var rules = basketball
        var state = newState(rules)

        TeamEngine.apply(.setPossession(1), to: &state, rules: rules, at: at(0))
        #expect(TeamEngine.derived(state, rules: rules, at: at(0)).possessionSlot == 1)

        TeamEngine.apply(.setPossession(nil), to: &state, rules: rules, at: at(0))
        #expect(state.possessionSlot == nil)

        rules.possessionArrowEnabled = false
        var plain = newState(rules)
        TeamEngine.apply(.setPossession(0), to: &plain, rules: rules, at: at(0))
        #expect(TeamEngine.derived(plain, rules: rules, at: at(0)).possessionSlot == nil)
    }

    // MARK: Finishing

    @Test("Finishing stops the clocks and freezes the state")
    func finish() {
        let rules = basketball
        var state = newState(rules)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.score(slot: 0, points: 10), to: &state, rules: rules, at: at(100))
        TeamEngine.apply(.finishMatch, to: &state, rules: rules, at: at(100))

        #expect(state.isFinished)
        #expect(!state.clock.isRunning)

        // A finished match ignores further actions.
        TeamEngine.apply(.score(slot: 1, points: 99), to: &state, rules: rules, at: at(200))
        #expect(state.sides[1].score == 0)
    }

    @Test("Outcome is nil until the match finishes")
    func outcomeRequiresFinish() {
        let rules = basketball
        var state = newState(rules)
        TeamEngine.apply(.score(slot: 0, points: 10), to: &state, rules: rules, at: at(0))
        #expect(TeamEngine.outcome(state, rules: rules, at: at(0)) == nil)
    }

    @Test("Outcome reports the winner, and a draw when scores are level")
    func outcome() throws {
        let rules = basketball

        var win = newState(rules)
        TeamEngine.apply(.score(slot: 0, points: 62), to: &win, rules: rules, at: at(0))
        TeamEngine.apply(.score(slot: 1, points: 58), to: &win, rules: rules, at: at(0))
        TeamEngine.apply(.finishMatch, to: &win, rules: rules, at: at(0))

        let result = try #require(TeamEngine.outcome(win, rules: rules, at: at(0)))
        #expect(result.winningSlots == [0])
        #expect(!result.isDraw)
        #expect(result.outcome(forSlot: 0) == .win)
        #expect(result.outcome(forSlot: 1) == .loss)
        #expect(result.rankBySlot == [0: 1, 1: 2])

        var draw = newState(rules)
        TeamEngine.apply(.score(slot: 0, points: 40), to: &draw, rules: rules, at: at(0))
        TeamEngine.apply(.score(slot: 1, points: 40), to: &draw, rules: rules, at: at(0))
        TeamEngine.apply(.finishMatch, to: &draw, rules: rules, at: at(0))

        let drawn = try #require(TeamEngine.outcome(draw, rules: rules, at: at(0)))
        #expect(drawn.isDraw)
        #expect(drawn.outcome(forSlot: 0) == .draw)
        // Tied sides share a rank (§6.5).
        #expect(drawn.rankBySlot == [0: 1, 1: 1])
    }

    // MARK: State round-trip

    /// Crash recovery encodes this state to `Match.stateBlob` and decodes it on next launch (§12).
    @Test("State survives a Codable round trip with its clocks intact")
    func stateRoundTrip() throws {
        let rules = basketball
        var state = newState(rules)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.score(slot: 0, points: 7), to: &state, rules: rules, at: at(60))
        TeamEngine.apply(.startBreak(300), to: &state, rules: rules, at: at(120))

        let data = try JSONEncoder().encode(state)
        let restored = try JSONDecoder().decode(TeamState.self, from: data)

        #expect(restored == state)
        // And the restored clock still tells the right time.
        #expect(
            TeamEngine.derived(restored, rules: rules, at: at(300)).primaryClock.value
                == TeamEngine.derived(state, rules: rules, at: at(300)).primaryClock.value
        )
    }
}
