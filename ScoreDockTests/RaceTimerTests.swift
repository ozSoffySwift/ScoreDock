import Foundation
import Testing

@testable import ScoreDock

/// §6.3 — the race timer, sequenced second at M6.
@Suite("Race timer (§6.3)")
struct RaceTimerTests {
    static let tip = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.tip.addingTimeInterval(seconds) }

    private func rules(racers: Int = 4, laps: Int? = nil, lowerWins: Bool = true) -> RaceTimerRules {
        var rules = RaceTimerRules()
        rules.racerCount = racers
        rules.lapCount = laps
        rules.lowerTimeWins = lowerWins
        return rules
    }

    private func started(_ rules: RaceTimerRules, at now: Date) -> RaceTimerState {
        var state = RaceTimerEngine.initialState(rules: rules, sideCount: rules.racerCount)
        RaceTimerEngine.apply(.toggleClock, to: &state, rules: rules, at: now)
        return state
    }

    private func lap(_ slot: Int, _ state: inout RaceTimerState, _ rules: RaceTimerRules, at now: Date) {
        RaceTimerEngine.apply(.specialised(.recordLap(slot: slot)), to: &state, rules: rules, at: now)
    }

    private func board(_ state: RaceTimerState, _ rules: RaceTimerRules, at now: Date) -> DerivedRaceTimerBoard {
        RaceTimerEngine.derived(state, rules: rules, isFinished: false, at: now)
    }

    // MARK: Laps and splits

    @Test("Lap durations come out of the crossing times")
    func lapDurations() {
        let rules = rules()
        var state = started(rules, at: at(0))

        lap(0, &state, rules, at: at(62))       // 62.0
        lap(0, &state, rules, at: at(121))      // 59.0
        lap(0, &state, rules, at: at(185))      // 64.0

        let row = board(state, rules, at: at(200)).rows.first { $0.slotIndex == 0 }
        #expect(row?.lapsCompleted == 3)
        #expect(row?.lastLap == 64)
        #expect(row?.bestLap == 59)
    }

    /// Undo removes the crossing time, and the neighbouring durations have to fall out correctly
    /// with nothing recomputed — the reason splits are stored rather than durations.
    @Test("Removing a mis-tapped lap leaves the remaining durations correct")
    func undoingALapRepairsTheNeighbours() {
        let rules = rules()
        var state = started(rules, at: at(0))

        lap(0, &state, rules, at: at(60))
        lap(0, &state, rules, at: at(65))       // the mis-tap
        lap(0, &state, rules, at: at(120))

        #expect(RaceTimerEngine.lapDurations(state.racers[0].splits) == [60, 5, 55])

        state.racers[0].splits.remove(at: 1)
        #expect(RaceTimerEngine.lapDurations(state.racers[0].splits) == [60, 60])
    }

    @Test("A lap before the gun is refused")
    func lapBeforeStart() {
        let rules = rules()
        var state = RaceTimerEngine.initialState(rules: rules, sideCount: 4)

        lap(0, &state, rules, at: at(5))
        #expect(state.racers[0].splits.isEmpty, "a split at 0.000 is a mis-tap, not a lap")
    }

    @Test("The whole field runs on one clock")
    func oneClockForTheField() {
        let rules = rules()
        var state = started(rules, at: at(0))
        lap(1, &state, rules, at: at(30))

        let derived = board(state, rules, at: at(45))
        #expect(derived.raceClock.value == 45)
        // A racer still running shows the race clock; the one who has laps still shows it too,
        // because they have not finished.
        #expect(derived.rows.allSatisfy { $0.elapsed == 45 })
    }

    // MARK: Finishing

    @Test("A fixed-distance race finishes a racer on their final lap")
    func lapCountFinishesTheRacer() {
        let rules = rules(laps: 3)
        var state = started(rules, at: at(0))

        lap(0, &state, rules, at: at(60))
        lap(0, &state, rules, at: at(120))
        #expect(state.racers[0].finishedAt == nil)

        lap(0, &state, rules, at: at(178))
        #expect(state.racers[0].finishedAt == 178, "no second tap needed")

        // And their clock stops there while the race goes on around them.
        let row = board(state, rules, at: at(400)).rows.first { $0.slotIndex == 0 }
        #expect(row?.elapsed == 178)
        #expect(row?.hasFinished == true)
    }

    @Test("A finished racer cannot record another lap")
    func finishedRacerIsDone() {
        let rules = rules(laps: 1)
        var state = started(rules, at: at(0))

        lap(0, &state, rules, at: at(50))
        lap(0, &state, rules, at: at(90))

        #expect(state.racers[0].splits == [50])
        #expect(state.racers[0].finishedAt == 50)
    }

    @Test("An open race finishes a racer by hand")
    func manualFinish() {
        let rules = rules()
        var state = started(rules, at: at(0))

        RaceTimerEngine.apply(.specialised(.finishRacer(slot: 2)), to: &state, rules: rules, at: at(310))
        #expect(state.racers[2].finishedAt == 310)
    }

    // MARK: Running order

    @Test("Nobody is placed before anyone has crossed anything")
    func noPositionsAtTheStartLine() {
        let rules = rules()
        let state = started(rules, at: at(0))

        let derived = board(state, rules, at: at(10))
        #expect(derived.rows.allSatisfy { $0.position == nil }, "handing out 1st–4th at the gun invents a result")
    }

    @Test("Running order is laps first, then who got there first")
    func runningOrder() {
        let rules = rules()
        var state = started(rules, at: at(0))

        lap(2, &state, rules, at: at(58))       // racer 2, one lap, earliest
        lap(0, &state, rules, at: at(61))       // racer 0, one lap
        lap(0, &state, rules, at: at(119))      // racer 0, two laps — takes the lead
        lap(1, &state, rules, at: at(70))       // racer 1, one lap, latest

        let rows = board(state, rules, at: at(130)).rows
        #expect(rows.map(\.slotIndex) == [0, 2, 1, 3])
        #expect(rows.map(\.position) == [1, 2, 3, nil], "racer 3 has not crossed anything")
    }

    @Test("A finished racer outranks anyone still on the course")
    func finishersLead() {
        let rules = rules()
        var state = started(rules, at: at(0))

        lap(1, &state, rules, at: at(40))
        lap(1, &state, rules, at: at(80))
        lap(1, &state, rules, at: at(120))      // racer 1 has three laps
        RaceTimerEngine.apply(.specialised(.finishRacer(slot: 3)), to: &state, rules: rules, at: at(200))

        let rows = board(state, rules, at: at(210)).rows
        #expect(rows.first?.slotIndex == 3, "finished, even on no laps")
        #expect(rows[1].slotIndex == 1)
    }

    @Test("Finishers are ordered by their finish times")
    func finishOrder() {
        let rules = rules()
        var state = started(rules, at: at(0))

        RaceTimerEngine.apply(.specialised(.finishRacer(slot: 2)), to: &state, rules: rules, at: at(300))
        RaceTimerEngine.apply(.specialised(.finishRacer(slot: 0)), to: &state, rules: rules, at: at(280))
        RaceTimerEngine.apply(.specialised(.finishRacer(slot: 1)), to: &state, rules: rules, at: at(295))

        #expect(board(state, rules, at: at(310)).rows.prefix(3).map(\.slotIndex) == [0, 1, 2])
    }

    /// The rule exists for formats where staying out longest wins, so it has to actually invert.
    @Test("lowerTimeWins false reverses the finish order")
    func higherTimeWins() {
        let rules = rules(lowerWins: false)
        var state = started(rules, at: at(0))

        RaceTimerEngine.apply(.specialised(.finishRacer(slot: 0)), to: &state, rules: rules, at: at(280))
        RaceTimerEngine.apply(.specialised(.finishRacer(slot: 1)), to: &state, rules: rules, at: at(295))

        #expect(board(state, rules, at: at(300)).rows.prefix(2).map(\.slotIndex) == [1, 0])
    }

    // MARK: Pausing and outcome

    @Test("A paused race clock does not move")
    func pauseHoldsTheClock() {
        let rules = rules()
        var state = started(rules, at: at(0))

        RaceTimerEngine.apply(.toggleClock, to: &state, rules: rules, at: at(50))
        #expect(board(state, rules, at: at(500)).raceClock.value == 50)

        RaceTimerEngine.apply(.toggleClock, to: &state, rules: rules, at: at(500))
        #expect(board(state, rules, at: at(510)).raceClock.value == 60)
    }

    @Test("The winner is the racer in first place")
    func outcomeRanksTheField() throws {
        let rules = rules(laps: 2)
        var state = started(rules, at: at(0))

        lap(0, &state, rules, at: at(60))
        lap(1, &state, rules, at: at(62))
        lap(1, &state, rules, at: at(121))      // racer 1 finishes first
        lap(0, &state, rules, at: at(125))      // racer 0 second

        let result = try #require(RaceTimerEngine.outcome(state, rules: rules, at: at(130)))
        #expect(result.winningSlots == [1])
        #expect(result.rankBySlot[1] == 1)
        #expect(result.rankBySlot[0] == 2)
        // Racers 2 and 3 never crossed anything, so they sit behind everyone who did.
        #expect(result.rankBySlot[2] == 3)
        #expect(result.rankBySlot[3] == 3)
    }

    @Test("A race nobody started has no result")
    func noResultWithoutRacing() {
        let rules = rules()
        let state = started(rules, at: at(0))
        #expect(RaceTimerEngine.outcome(state, rules: rules, at: at(60)) == nil)
    }

    // MARK: Through the shared engine

    @Test("The dispatcher routes to the race timer")
    func throughSpecialisedEngine() {
        var rules = SpecialisedRules(board: .raceTimer)
        rules.raceTimer = self.rules(racers: 3)

        var state = SpecialisedEngine.initialState(rules: rules, sideCount: 3)
        SpecialisedEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        SpecialisedEngine.apply(.specialised(.recordLap(slot: 1)), to: &state, rules: rules, at: at(45))

        guard case let .raceTimer(board) = SpecialisedEngine.derived(state, rules: rules, at: at(50)) else {
            Issue.record("expected a race timer board")
            return
        }
        #expect(board.rows.count == 3)
        #expect(board.rows.first?.slotIndex == 1)
        #expect(board.raceClock.value == 50)

        SpecialisedEngine.apply(.finishMatch, to: &state, rules: rules, at: at(50))
        #expect(state.isFinished)
        // The clock stops with the race, so the times do not drift on afterwards.
        #expect(SpecialisedEngine.derived(state, rules: rules, at: at(900)) == SpecialisedEngine.derived(state, rules: rules, at: at(50)))
    }
}
