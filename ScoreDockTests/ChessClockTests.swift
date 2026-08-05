import Foundation
import SwiftData
import Testing

@testable import ScoreDock

/// §6.3 — the chess clock, sequenced first at M6.
@Suite("Chess clock (§6.3)")
struct ChessClockTests {
    static let tip = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.tip.addingTimeInterval(seconds) }

    private func rules(
        base: TimeInterval = 300,
        mode: ChessClockRules.Increment = .fischer,
        increment: TimeInterval = 3
    ) -> ChessClockRules {
        var rules = ChessClockRules()
        rules.baseTime = base
        rules.incrementMode = mode
        rules.incrementSeconds = increment
        return rules
    }

    private func press(_ slot: Int, _ state: inout ChessClockState, _ rules: ChessClockRules, at now: Date) {
        ChessClockEngine.apply(.specialised(.pressClock(slot: slot)), to: &state, rules: rules, at: now)
    }

    private func remaining(_ state: ChessClockState, _ slot: Int, _ rules: ChessClockRules, at now: Date) -> TimeInterval {
        ChessClockEngine.remaining(state.sides[slot], rules: rules, at: now)
    }

    // MARK: Turn passing

    @Test("Only the running side's clock counts down")
    func onlyActiveClockRuns() {
        let rules = rules()
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(0))          // White moves; Black is now on the clock
        #expect(state.activeSlot == 1)

        // Ten seconds pass. Black is thinking, so only Black's clock moves.
        #expect(remaining(state, 1, rules, at: at(10)) == 290)
        #expect(remaining(state, 0, rules, at: at(10)) == 303, "White banked the increment and stopped")
    }

    @Test("Pressing out of turn does nothing")
    func pressOutOfTurn() {
        let rules = rules()
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(0))
        press(0, &state, rules, at: at(5))          // White fumbles their own button again

        #expect(state.activeSlot == 1, "still Black's move")
        #expect(state.sides[0].moves == 1, "the second press was not a move")
        // A physical clock's button is already down; the fumble must not bank a second increment.
        #expect(remaining(state, 0, rules, at: at(5)) == 303)
    }

    // MARK: Increments

    @Test("Fischer adds the full increment after every move")
    func fischerIncrement() {
        let rules = rules(mode: .fischer, increment: 3)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(0))          // instant move
        press(1, &state, rules, at: at(10))         // Black thinks for 10 s
        press(0, &state, rules, at: at(12))         // White thinks for 2 s

        #expect(remaining(state, 0, rules, at: at(12)) == 304, "300 − 2 spent + 2 × 3 increment")
        #expect(remaining(state, 1, rules, at: at(12)) == 293, "300 − 10 spent + 3 increment")
    }

    /// The property that makes Bronstein and Fischer one code path: a delay returns only the time
    /// the move actually used, so a fast move can never bank time.
    @Test("Bronstein returns only the time the move used")
    func bronsteinIncrement() {
        let rules = rules(mode: .bronstein, increment: 5)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(0))          // instant move: nothing used, nothing returned
        #expect(remaining(state, 0, rules, at: at(0)) == 300, "an instant move cannot gain time")

        press(1, &state, rules, at: at(2))          // Black used 2 s of a 5 s delay
        #expect(remaining(state, 1, rules, at: at(2)) == 300, "fully refunded, but not beyond the base")

        press(0, &state, rules, at: at(20))         // White used 18 s, more than the delay
        #expect(remaining(state, 0, rules, at: at(20)) == 287, "300 − 18 + 5 capped increment")
    }

    @Test("No increment means the clock only ever goes down")
    func noIncrement() {
        let rules = rules(mode: .none)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        // The game has to be started before anyone is being charged for thinking — see
        // `firstMoveIsFreeUntilTheGameStarts`.
        ChessClockEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        press(0, &state, rules, at: at(4))
        #expect(remaining(state, 0, rules, at: at(4)) == 296)
    }

    /// No clock runs until the game is started, so a press before that charges nobody. The app
    /// cannot bill someone for time it was never asked to measure — which is why the board leads
    /// with Start rather than with the two clock faces.
    @Test("Nobody is charged for time before the game is started")
    func firstMoveIsFreeUntilTheGameStarts() {
        let rules = rules(mode: .none)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(120))
        #expect(remaining(state, 0, rules, at: at(120)) == 300)
        #expect(state.activeSlot == 1, "and play is under way from that press")
        #expect(state.hasStarted)
    }

    // MARK: Pausing

    @Test("A pause costs neither player time, and does not count as thinking")
    func pauseIsFree() {
        let rules = rules(mode: .bronstein, increment: 5)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(0))                                        // Black on the clock
        ChessClockEngine.apply(.toggleClock, to: &state, rules: rules, at: at(3))  // pause after 3 s
        #expect(remaining(state, 1, rules, at: at(90)) == 297, "a paused clock does not run")

        ChessClockEngine.apply(.toggleClock, to: &state, rules: rules, at: at(90)) // resume
        press(1, &state, rules, at: at(92))

        // Black thought for 3 s then 2 s = 5 s; the 87 s pause is not thinking time, so Bronstein
        // refunds 5 (the whole delay) rather than being fooled into capping on wall-clock time.
        #expect(remaining(state, 1, rules, at: at(92)) == 300)
    }

    @Test("Toggling before the first press starts the game")
    func toggleStartsTheGame() {
        let rules = rules()
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        #expect(!state.hasStarted)
        ChessClockEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        #expect(state.hasStarted)
        #expect(state.activeSlot == 0)
        #expect(remaining(state, 0, rules, at: at(6)) == 294)
    }

    // MARK: Flags

    @Test("A flag falls exactly at zero and never goes negative")
    func flagFalls() {
        let rules = rules(base: 10, mode: .none)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(0))
        let board = ChessClockEngine.derived(state, rules: rules, isFinished: false, at: at(15))

        #expect(board.flaggedSlot == 1)
        #expect(board.sides[1].remaining == 0, "never negative — the board reads 00:00")
        #expect(board.sides[1].hasFlagged)
        #expect(!board.sides[0].hasFlagged)
    }

    @Test("Losing on time hands the game to the other player")
    func flagDecidesTheGame() {
        let rules = rules(base: 10, mode: .none)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)
        press(0, &state, rules, at: at(0))

        let result = ChessClockEngine.outcome(state, rules: rules, at: at(15))
        let outcome = try! #require(result)
        #expect(outcome.winningSlots == [0])
        #expect(!outcome.isDraw)
        #expect(outcome.rankBySlot == [0: 1, 1: 2])
    }

    /// ScoreDock is a clock, not an arbiter.
    @Test("A game that ends without a flag has no result the app can claim")
    func noFlagNoResult() {
        let rules = rules()
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)
        press(0, &state, rules, at: at(0))
        press(1, &state, rules, at: at(30))

        #expect(ChessClockEngine.outcome(state, rules: rules, at: at(30)) == nil)
    }

    @Test("A move played on a fallen flag earns no increment")
    func flaggedMoveEarnsNothing() {
        let rules = rules(base: 10, mode: .fischer, increment: 3)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(0))
        press(1, &state, rules, at: at(30))         // Black presses long after flagging

        #expect(state.sides[1].hasFlagged)
        #expect(remaining(state, 1, rules, at: at(30)) == -20, "no increment rescued it")
        #expect(ChessClockEngine.derived(state, rules: rules, isFinished: false, at: at(30)).flaggedSlot == 1)
    }

    // MARK: Corrections

    @Test("An arbiter can put time back on the running clock")
    func setRemainingTime() {
        let rules = rules(base: 300, mode: .none)
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)
        press(0, &state, rules, at: at(0))          // Black on the clock

        ChessClockEngine.apply(.setClockElapsed(120), to: &state, rules: rules, at: at(60))
        #expect(remaining(state, 1, rules, at: at(60)) == 120, "set in time *left*, which is the only number here")
        #expect(remaining(state, 1, rules, at: at(70)) == 110, "and it keeps running from there")
    }

    // MARK: Moves and labels

    @Test("Each side counts its own moves")
    func moveCounter() {
        let rules = rules()
        var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)

        press(0, &state, rules, at: at(1))
        press(1, &state, rules, at: at(2))
        press(0, &state, rules, at: at(3))

        #expect(state.sides[0].moves == 2)
        #expect(state.sides[1].moves == 1)
    }

    @Test("The time control reads the way players write it")
    func timeControlLabel() {
        #expect(ChessClockEngine.timeControlLabel(rules(base: 300, mode: .fischer, increment: 3)) == "5|3")
        // Written even when zero — a bare "3" next to a move count reads as a number, not a control.
        #expect(ChessClockEngine.timeControlLabel(rules(base: 180, mode: .none)) == "3|0")
        #expect(ChessClockEngine.timeControlLabel(rules(base: 90, mode: .fischer, increment: 1)) == "1:30|1")
    }

    // MARK: Through the shared engine

    @Test("The dispatcher routes to the chess clock and finishes cleanly")
    func throughSpecialisedEngine() {
        var rules = SpecialisedRules(board: .chessClock)
        rules.chessClock = self.rules(base: 60, mode: .fischer, increment: 2)

        var state = SpecialisedEngine.initialState(rules: rules, sideCount: 2)
        SpecialisedEngine.apply(.specialised(.pressClock(slot: 0)), to: &state, rules: rules, at: at(0))

        guard case let .chessClock(board) = SpecialisedEngine.derived(state, rules: rules, at: at(5)) else {
            Issue.record("expected a chess clock board")
            return
        }
        #expect(board.activeSlot == 1)
        #expect(board.sides[1].remaining == 55)
        #expect(board.incrementLabel == "1|2")

        SpecialisedEngine.apply(.finishMatch, to: &state, rules: rules, at: at(5))
        #expect(state.isFinished)
        // Both clocks are stopped, so time no longer moves after the game ends.
        #expect(SpecialisedEngine.derived(state, rules: rules, at: at(900)) == SpecialisedEngine.derived(state, rules: rules, at: at(5)))
    }

    /// The share card prints `finalScore` (§13.5), so it has to be a number that reads as a result.
    @Test("A finished game is recorded 1–0 to whoever is left standing")
    @MainActor
    func finalScoreIsTheChessResult() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let preset = try #require(BuiltInCatalog.bySlug["chess-clock"])

        var configured = SpecialisedRules(board: .chessClock)
        configured.chessClock = rules(base: 10, mode: .none)

        let match = MatchBuilder.make(
            preset: GamePreset(
                origin: .builtIn(slug: preset.slug),
                name: preset.name,
                emoji: preset.emoji,
                engine: preset.engine,
                category: preset.category,
                rules: .specialised(configured),
                defaultThemeID: preset.defaultThemeID,
                sortIndex: 0
            ),
            rules: .specialised(configured),
            title: nil,
            venue: nil,
            themeID: preset.defaultThemeID,
            attributionEnabled: false,
            sides: [
                SideDraft(displayName: "White", colorHex: "#ECEFF1"),
                SideDraft(displayName: "Black", colorHex: "#78909C"),
            ],
            in: context
        )

        let store = try #require(SpecialisedStore(match: match, context: context))
        store.perform(.specialised(.pressClock(slot: 0)), at: at(0))

        // Black's ten seconds run out with nobody touching anything, which is the whole point.
        store.checkForTimeExpiry(at: at(15))

        #expect(match.status == .finished)
        #expect(match.orderedSides.map(\.finalScore) == [1, 0])
        #expect(match.orderedSides.map(\.outcome) == [.win, .loss])
        #expect(match.orderedEvents.last?.kind == .matchFinish, "the flag is recorded as a real event")
    }

    @Test("A game ended by hand with no flag records no winner")
    @MainActor
    func endedWithoutFlagHasNoResult() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let preset = try #require(BuiltInCatalog.bySlug["chess-clock"])

        var configured = SpecialisedRules(board: .chessClock)
        configured.chessClock = rules(base: 600, mode: .fischer, increment: 5)

        let match = MatchBuilder.make(
            preset: GamePreset(
                origin: .builtIn(slug: preset.slug),
                name: preset.name,
                emoji: preset.emoji,
                engine: preset.engine,
                category: preset.category,
                rules: .specialised(configured),
                defaultThemeID: preset.defaultThemeID,
                sortIndex: 0
            ),
            rules: .specialised(configured),
            title: nil,
            venue: nil,
            themeID: preset.defaultThemeID,
            attributionEnabled: false,
            sides: [
                SideDraft(displayName: "White", colorHex: "#ECEFF1"),
                SideDraft(displayName: "Black", colorHex: "#78909C"),
            ],
            in: context
        )

        let store = try #require(SpecialisedStore(match: match, context: context))
        store.perform(.specialised(.pressClock(slot: 0)), at: at(0))
        store.perform(.specialised(.pressClock(slot: 1)), at: at(30))
        store.finish(at: at(60))

        // Neither player flagged, so the app has no idea who won — and says so rather than
        // inventing a draw.
        #expect(match.orderedSides.allSatisfy { $0.outcome == .unfinished })
        #expect(match.orderedSides.map(\.finalScore) == [0, 0])
    }

    @Test("Every specialised action survives the event round trip")
    func specialisedActionsRoundTrip() throws {
        let actions: [SpecialisedAction] = [
            .pressClock(slot: 1),
            .recordLap(slot: 2),
            .finishRacer(slot: 0),
            .setDownAndDistance(down: 3, yardsToGo: 7),
            .setBallOn(yardLine: 42),
            .delivery(runs: 4, extra: nil),
            .delivery(runs: 1, extra: .noBall),
            .wicket(kind: .lbw),
            .endInnings,
            .pitch(.strike),
            .setBases(first: true, second: false, third: true),
            .advanceHalfInning,
        ]

        for action in actions {
            let wrapped = EngineAction.specialised(action)
            let rebuilt = EngineAction.from(
                kind: wrapped.eventKind,
                slotIndex: wrapped.eventSlotIndex,
                value: wrapped.eventValue,
                playerID: nil,
                note: wrapped.eventNote
            )
            #expect(rebuilt == wrapped, "\(action) did not survive the round trip")
        }
    }

    /// A delivery whose extra this build does not recognise must not silently become a legal ball —
    /// that would change the over count and put the innings out of step.
    @Test("An unknown delivery extra is refused rather than downgraded")
    func unknownExtraIsRefused() {
        #expect(SpecialisedAction.from(kind: .delivery, slotIndex: nil, value: 2, note: "penaltyRuns") == nil)
        #expect(SpecialisedAction.from(kind: .delivery, slotIndex: nil, value: 2, note: nil) == .delivery(runs: 2, extra: nil))
    }
}
