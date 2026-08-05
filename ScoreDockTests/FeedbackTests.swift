import Foundation
import Testing

@testable import ScoreDock

/// §11 and §6.4. Sounds are *scheduled* against wall-clock time rather than fired from a UI tick,
/// so the schedule itself is what has to be correct.
@Suite("Match feedback (§11, §6.4)")
struct FeedbackTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.t0.addingTimeInterval(seconds) }

    private var basketball: TeamRules {
        BuiltInCatalog.bySlug["basketball"]?.rules.teamRules ?? TeamRules()
    }

    private func cues(
        _ state: TeamState,
        _ rules: TeamRules,
        preferences: SoundPreferences = SoundPreferences(),
        at now: Date
    ) -> [ScheduledCue] {
        MatchFeedback.cues(state: state, rules: rules, preferences: preferences, at: now)
    }

    // MARK: Period buzzer

    @Test("A stopped clock arms nothing")
    func stoppedClockArmsNothing() {
        let rules = basketball
        let state = TeamEngine.initialState(rules: rules, sideCount: 2)
        #expect(cues(state, rules, at: at(0)).isEmpty)
    }

    /// The §6.4 guarantee in test form: the buzzer is armed for the absolute instant the clock
    /// reaches zero, so a throttled UI cannot make it late.
    @Test("Starting the clock arms the buzzer for the exact expiry instant")
    func buzzerArmedForExpiry() throws {
        var rules = basketball
        rules.periodLength = 600
        rules.shotClockEnabled = false
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        let buzzer = try #require(cues(state, rules, at: at(0)).first { $0.sound == .buzzer })
        #expect(buzzer.fireAt == at(600))

        // Asked again 90 seconds in, it still points at the same absolute instant.
        let later = try #require(cues(state, rules, at: at(90)).first { $0.sound == .buzzer })
        #expect(later.fireAt == at(600))
    }

    @Test("A buzzer already past is not armed")
    func expiredBuzzerNotArmed() {
        var rules = basketball
        rules.periodLength = 600
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        #expect(!cues(state, rules, at: at(700)).contains { $0.sound == .buzzer })
    }

    /// Soccer runs into added time; a buzzer at 45:00 would be wrong (§6.1).
    @Test("A count-up clock arms no buzzer")
    func countUpHasNoBuzzer() {
        var rules = TeamRules()
        rules.countsUp = true
        rules.periodLength = 2700
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        #expect(!cues(state, rules, at: at(0)).contains { $0.sound == .buzzer })
    }

    @Test("A finished match arms nothing")
    func finishedMatchIsSilent() {
        let rules = basketball
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.finishMatch, to: &state, rules: rules, at: at(10))

        #expect(cues(state, rules, at: at(10)).isEmpty)
    }

    // MARK: Shot clock

    @Test("The shot clock arms a horn at zero and a tick five seconds out")
    func shotClockCues() throws {
        let rules = basketball  // 24 / 14
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleShotClock, to: &state, rules: rules, at: at(0))

        let armed = cues(state, rules, at: at(0))
        #expect(try #require(armed.first { $0.sound == .horn }).fireAt == at(24))
        #expect(try #require(armed.first { $0.sound == .tick }).fireAt == at(19))
    }

    @Test("Resetting the shot clock to the short value re-arms both cues")
    func shotClockShortReset() throws {
        let rules = basketball
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleShotClock, to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.resetShotClock(full: false), to: &state, rules: rules, at: at(10))

        let armed = cues(state, rules, at: at(10))
        #expect(try #require(armed.first { $0.sound == .horn }).fireAt == at(24))
        #expect(try #require(armed.first { $0.sound == .tick }).fireAt == at(19))
    }

    // MARK: Break

    /// A break replaces the main clock, so it must replace the main clock's sounds too — a period
    /// buzzer going off during half-time would be a real embarrassment in a hall.
    @Test("A break arms only its chime, never the period buzzer")
    func breakSuppressesRegulationCues() throws {
        let rules = basketball
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.startBreak(900), to: &state, rules: rules, at: at(120))

        let armed = cues(state, rules, at: at(120))
        #expect(armed.map(\.sound) == [.chime])
        #expect(try #require(armed.first).fireAt == at(1020))
    }

    // MARK: Preferences

    @Test("Each sound can be switched off individually")
    func individualToggles() {
        var rules = basketball
        rules.periodLength = 600
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        TeamEngine.apply(.toggleShotClock, to: &state, rules: rules, at: at(0))

        var prefs = SoundPreferences()
        #expect(Set(cues(state, rules, preferences: prefs, at: at(0)).map(\.sound)) == [.buzzer, .horn, .tick])

        prefs.buzzer = false
        #expect(!cues(state, rules, preferences: prefs, at: at(0)).contains { $0.sound == .buzzer })

        prefs.shotClockHorn = false
        prefs.shotClockTick = false
        #expect(cues(state, rules, preferences: prefs, at: at(0)).isEmpty)
    }

    /// §11.1: the 60 s and 10 s warnings are off by default.
    @Test("Timer warnings are off by default and arm correctly when enabled")
    func timerWarnings() {
        var rules = basketball
        rules.periodLength = 600
        rules.shotClockEnabled = false
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        TeamEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        #expect(SoundPreferences().timerWarning == false)
        #expect(!cues(state, rules, at: at(0)).contains { $0.sound == .warning })

        var prefs = SoundPreferences()
        prefs.timerWarning = true
        let warnings = cues(state, rules, preferences: prefs, at: at(0))
            .filter { $0.sound == .warning }
            .map(\.fireAt)
            .sorted()
        #expect(warnings == [at(540), at(590)], "60 s and 10 s remaining")
    }

    @Test("Every sound has a bundled asset name")
    func soundAssetNames() {
        #expect(MatchSound.allCases.count == 5)
        for sound in MatchSound.allCases {
            #expect(sound.fileName == "\(sound.rawValue).wav")
            #expect(!sound.displayName.isEmpty)
        }
    }

    // MARK: The bespoke boards (§6.3)

    /// Football and the chess clock got no scheduled sound at all until M8 — a quarter ran out in
    /// silence and a flag fell in silence, on the one path §11.1 exists for.
    @Test("A football quarter is armed to buzz at the instant it expires")
    func footballQuarterBuzzes() throws {
        var rules = SpecialisedRules(board: .americanFootball)
        let footballRules = try #require(
            BuiltInCatalog.bySlug["american-football"]?.rules.specialisedRules?.americanFootball
        )
        rules.americanFootball = footballRules

        var state = SpecialisedEngine.initialState(rules: rules, sideCount: 2)
        SpecialisedEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

        let cues = MatchFeedback.cues(state: state, rules: rules, preferences: SoundPreferences(), at: at(0))
        let buzzer = try #require(cues.first { $0.sound == .buzzer })
        #expect(buzzer.fireAt == at(footballRules.quarterLength), "armed for the wall-clock instant, not a tick")
    }

    @Test("The play clock gets the same horn a shot clock does")
    func playClockHorn() throws {
        var rules = SpecialisedRules(board: .americanFootball)
        rules.americanFootball = try #require(
            BuiltInCatalog.bySlug["american-football"]?.rules.specialisedRules?.americanFootball
        )

        var state = SpecialisedEngine.initialState(rules: rules, sideCount: 2)
        SpecialisedEngine.apply(.toggleShotClock, to: &state, rules: rules, at: at(0))

        let cues = MatchFeedback.cues(state: state, rules: rules, preferences: SoundPreferences(), at: at(0))
        let horn = try #require(cues.first { $0.sound == .horn })
        #expect(horn.fireAt == at(40))
    }

    /// Only the side actually on the clock can flag, and its limit includes the increment banked.
    @Test("Only the running chess clock is armed, and it accounts for the increment")
    func chessFlagIsArmed() throws {
        var rules = SpecialisedRules(board: .chessClock)
        var clockRules = ChessClockRules()
        clockRules.baseTime = 60
        clockRules.incrementMode = .fischer
        clockRules.incrementSeconds = 5
        rules.chessClock = clockRules

        var state = SpecialisedEngine.initialState(rules: rules, sideCount: 2)
        // White moves instantly and banks five seconds; Black is now on the clock with a plain 60.
        SpecialisedEngine.apply(.specialised(.pressClock(slot: 0)), to: &state, rules: rules, at: at(0))

        let cues = MatchFeedback.cues(state: state, rules: rules, preferences: SoundPreferences(), at: at(0))
        #expect(cues.count == 1, "the stopped clock cannot flag")
        #expect(cues.first?.fireAt == at(60))
    }

    @Test("A board with no expiring clock schedules nothing")
    func clocklessBoardsAreSilent() throws {
        for board in [SpecialisedBoard.cricket, .baseball, .raceTimer] {
            var rules = SpecialisedRules(board: board)
            rules.cricket = CricketRules()
            rules.baseball = BaseballRules()
            rules.raceTimer = RaceTimerRules()

            var state = SpecialisedEngine.initialState(rules: rules, sideCount: 2)
            SpecialisedEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))

            let cues = MatchFeedback.cues(state: state, rules: rules, preferences: SoundPreferences(), at: at(0))
            #expect(cues.isEmpty, "\(board.rawValue) has nothing to expire")
        }
    }

    @Test("A finished match arms nothing")
    func finishedSpecialisedMatchIsSilent() throws {
        var rules = SpecialisedRules(board: .americanFootball)
        rules.americanFootball = AmericanFootballRules()

        var state = SpecialisedEngine.initialState(rules: rules, sideCount: 2)
        SpecialisedEngine.apply(.toggleClock, to: &state, rules: rules, at: at(0))
        SpecialisedEngine.apply(.finishMatch, to: &state, rules: rules, at: at(1))

        #expect(MatchFeedback.cues(state: state, rules: rules, preferences: SoundPreferences(), at: at(1)).isEmpty)
    }
}

/// §5.3 — the rule that rotating must never take the operator's controls away.
@Suite("Surface selection (§5.3)")
struct MatchSurfaceTests {
    @Test("Landscape shows the board only when nothing is casting")
    func behaviourMatrix() {
        // Portrait, no TV → control panel.
        #expect(!MatchSurface.deviceShowsBoard(isLandscape: false, isCasting: false))
        // Landscape, no TV → board.
        #expect(MatchSurface.deviceShowsBoard(isLandscape: true, isCasting: false))
        // Portrait, casting → control panel.
        #expect(!MatchSurface.deviceShowsBoard(isLandscape: false, isCasting: true))
        // Landscape, casting → control panel, NOT a second copy of the board.
        #expect(!MatchSurface.deviceShowsBoard(isLandscape: true, isCasting: true))
    }

    @Test("Board modes cover the documented set")
    func boardModes() {
        #expect(BoardMode.allCases.map(\.rawValue) == ["full", "shotClockOnly", "timerOnly"])
        for mode in BoardMode.allCases {
            #expect(!mode.displayName.isEmpty)
            #expect(!mode.symbolName.isEmpty)
        }
    }
}
