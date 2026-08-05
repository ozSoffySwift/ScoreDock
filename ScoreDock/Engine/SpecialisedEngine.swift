import Foundation

/// The five bespoke boards, behind one `ScoreEngine` (§6.3).
///
/// This type owns **no rules**. Every decision about how a game works lives in a per-board engine —
/// `ChessClockEngine` and its siblings — which are pure and independently testable. All this does
/// is route by the discriminator and keep the plumbing (event log, undo, snapshots, crash recovery)
/// in one place instead of five.
///
/// §17 risk 2 warns these are "five small apps" and are the most likely part of the backlog to slip.
/// Routing rather than abstracting is the hedge: each board can be as odd as its sport demands
/// without any of the others having to accommodate it.
enum SpecialisedEngine: ScoreEngine {
    static var kind: EngineKind { .specialised }

    /// Which boards this build implements. The router reads it so an unimplemented board says so,
    /// rather than opening an empty scoreboard. All five are in as of M6; it stays because a match
    /// synced from a newer build can still name one this build has never heard of.
    static let implementedBoards: Set<SpecialisedBoard> = [.chessClock, .raceTimer, .americanFootball, .cricket, .baseball]

    static func initialState(rules: SpecialisedRules, sideCount: Int) -> SpecialisedState {
        var state = SpecialisedState(board: rules.board)
        switch rules.board {
        case .chessClock:
            state.chessClock = ChessClockEngine.initialState(
                rules: rules.chessClock ?? ChessClockRules(),
                sideCount: sideCount
            )
        case .raceTimer:
            state.raceTimer = RaceTimerEngine.initialState(
                rules: rules.raceTimer ?? RaceTimerRules(),
                sideCount: sideCount
            )
        case .americanFootball:
            state.americanFootball = AmericanFootballEngine.initialState(
                rules: rules.americanFootball ?? AmericanFootballRules(),
                sideCount: sideCount
            )
        case .cricket:
            state.cricket = CricketEngine.initialState(
                rules: rules.cricket ?? CricketRules(),
                sideCount: sideCount
            )
        case .baseball:
            state.baseball = BaseballEngine.initialState(
                rules: rules.baseball ?? BaseballRules(),
                sideCount: sideCount
            )
        }
        return state
    }

    // MARK: - Apply

    static func apply(
        _ action: EngineAction,
        to state: inout SpecialisedState,
        rules: SpecialisedRules,
        at now: Date
    ) {
        guard !state.isFinished else { return }

        if case .finishMatch = action {
            finish(&state, at: now)
            return
        }

        switch state.board {
        case .chessClock:
            guard var board = state.chessClock else { return }
            ChessClockEngine.apply(action, to: &board, rules: rules.chessClock ?? ChessClockRules(), at: now)
            state.chessClock = board
        case .raceTimer:
            guard var board = state.raceTimer else { return }
            RaceTimerEngine.apply(action, to: &board, rules: rules.raceTimer ?? RaceTimerRules(), at: now)
            state.raceTimer = board
        case .americanFootball:
            guard var board = state.americanFootball else { return }
            AmericanFootballEngine.apply(
                action, to: &board, rules: rules.americanFootball ?? AmericanFootballRules(), at: now
            )
            state.americanFootball = board
        case .cricket:
            guard var board = state.cricket else { return }
            CricketEngine.apply(action, to: &board, rules: rules.cricket ?? CricketRules(), at: now)
            state.cricket = board
        case .baseball:
            guard var board = state.baseball else { return }
            BaseballEngine.apply(action, to: &board, rules: rules.baseball ?? BaseballRules(), at: now)
            state.baseball = board
        }
    }

    private static func finish(_ state: inout SpecialisedState, at now: Date) {
        switch state.board {
        case .chessClock:
            if var board = state.chessClock {
                ChessClockEngine.stopAll(&board, at: now)
                state.chessClock = board
            }
        case .raceTimer:
            if var board = state.raceTimer {
                RaceTimerEngine.stopAll(&board, at: now)
                state.raceTimer = board
            }
        case .americanFootball:
            if var board = state.americanFootball {
                AmericanFootballEngine.stopAll(&board, at: now)
                state.americanFootball = board
            }
        case .cricket:
            if var board = state.cricket {
                CricketEngine.closeAll(&board)
                state.cricket = board
            }
        case .baseball:
            // Nothing to stop: a baseball board has no clock.
            break
        }
        state.isFinished = true
    }

    // MARK: - Derived

    static func derived(
        _ state: SpecialisedState,
        rules: SpecialisedRules,
        at now: Date
    ) -> DerivedSpecialisedBoard {
        switch state.board {
        case .chessClock:
            guard let board = state.chessClock else { return .unavailable(.chessClock) }
            return .chessClock(
                ChessClockEngine.derived(
                    board,
                    rules: rules.chessClock ?? ChessClockRules(),
                    isFinished: state.isFinished,
                    at: now
                )
            )
        case .raceTimer:
            guard let board = state.raceTimer else { return .unavailable(.raceTimer) }
            return .raceTimer(
                RaceTimerEngine.derived(
                    board,
                    rules: rules.raceTimer ?? RaceTimerRules(),
                    isFinished: state.isFinished,
                    at: now
                )
            )
        case .americanFootball:
            guard let board = state.americanFootball else { return .unavailable(.americanFootball) }
            return .americanFootball(
                AmericanFootballEngine.derived(
                    board,
                    rules: rules.americanFootball ?? AmericanFootballRules(),
                    isFinished: state.isFinished,
                    at: now
                )
            )
        case .cricket:
            guard let board = state.cricket else { return .unavailable(.cricket) }
            return .cricket(
                CricketEngine.derived(
                    board,
                    rules: rules.cricket ?? CricketRules(),
                    sideCount: 2,
                    isFinished: state.isFinished,
                    at: now
                )
            )
        case .baseball:
            guard let board = state.baseball else { return .unavailable(.baseball) }
            return .baseball(
                BaseballEngine.derived(
                    board,
                    rules: rules.baseball ?? BaseballRules(),
                    isFinished: state.isFinished,
                    at: now
                )
            )
        }
    }

    // MARK: - Outcome

    static func outcome(
        _ state: SpecialisedState,
        rules: SpecialisedRules,
        at now: Date
    ) -> MatchOutcome? {
        guard state.isFinished else { return nil }

        switch state.board {
        case .chessClock:
            guard let board = state.chessClock else { return nil }
            return ChessClockEngine.outcome(board, rules: rules.chessClock ?? ChessClockRules(), at: now)
        case .raceTimer:
            guard let board = state.raceTimer else { return nil }
            return RaceTimerEngine.outcome(board, rules: rules.raceTimer ?? RaceTimerRules(), at: now)
        case .americanFootball:
            guard let board = state.americanFootball else { return nil }
            return AmericanFootballEngine.outcome(
                board, rules: rules.americanFootball ?? AmericanFootballRules(), at: now
            )
        case .cricket:
            guard let board = state.cricket else { return nil }
            return CricketEngine.outcome(board, rules: rules.cricket ?? CricketRules(), at: now)
        case .baseball:
            guard let board = state.baseball else { return nil }
            return BaseballEngine.outcome(board, rules: rules.baseball ?? BaseballRules(), at: now)
        }
    }
}
