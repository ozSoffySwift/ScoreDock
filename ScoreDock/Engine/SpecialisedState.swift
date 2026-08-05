import Foundation

/// The specialised engine's complete state (§6.3).
///
/// **Why one state type with five optional sub-states, and not five engines.** §17 risk 2 calls
/// these "five small apps", and the *rules* genuinely share nothing — which is why
/// `SpecialisedRules` is already a discriminator plus optional sub-structs, and this mirrors it
/// exactly. What they do share is all the plumbing: the event log, undo resolution, snapshotting,
/// crash recovery, the setup screen, the container. Five stores would duplicate that five more
/// times to buy nothing.
///
/// So the split is: one `SpecialisedEngine` and one `SpecialisedStore` own the plumbing, and five
/// pure sub-engines own the rules, each with its own state struct that knows nothing about the
/// others. Only the discriminator is shared.
/// Sub-states are added board by board as M6 lands them, rather than all five up front as empty
/// shells. A shell would let the router send someone to a board that renders nothing.
struct SpecialisedState: Codable, Sendable, Hashable {
    var board: SpecialisedBoard = .chessClock

    var chessClock: ChessClockState?
    var raceTimer: RaceTimerState?
    var americanFootball: AmericanFootballState?
    var cricket: CricketState?
    var baseball: BaseballState?

    var isFinished: Bool = false

    init(board: SpecialisedBoard = .chessClock) {
        self.board = board
    }
}

extension SpecialisedState {
    private enum CodingKeys: String, CodingKey {
        case board, chessClock, raceTimer, americanFootball, cricket, baseball, isFinished
    }

    /// Decode-with-defaults, same discipline as the rule types: a snapshot written by a build that
    /// knows a board this one does not must still open.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(board: SpecialisedBoard(storedRaw: try c.decodeIfPresent(String.self, forKey: .board)))
        chessClock = try c.decodeIfPresent(ChessClockState.self, forKey: .chessClock)
        raceTimer = try c.decodeIfPresent(RaceTimerState.self, forKey: .raceTimer)
        americanFootball = try c.decodeIfPresent(AmericanFootballState.self, forKey: .americanFootball)
        cricket = try c.decodeIfPresent(CricketState.self, forKey: .cricket)
        baseball = try c.decodeIfPresent(BaseballState.self, forKey: .baseball)
        isFinished = try c.decodeIfPresent(Bool.self, forKey: .isFinished) ?? false
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(board.rawValue, forKey: .board)
        try c.encodeIfPresent(chessClock, forKey: .chessClock)
        try c.encodeIfPresent(raceTimer, forKey: .raceTimer)
        try c.encodeIfPresent(americanFootball, forKey: .americanFootball)
        try c.encodeIfPresent(cricket, forKey: .cricket)
        try c.encodeIfPresent(baseball, forKey: .baseball)
        try c.encode(isFinished, forKey: .isFinished)
    }
}

// MARK: - Chess clock

/// One player's clock (§6.3).
struct ChessClockSideState: Codable, Sendable, Hashable {
    /// Time this player has actually spent thinking. Date-anchored, like every clock in the app —
    /// remaining time is *derived* from it, never decremented on a tick (§6.4).
    var spent: MatchClock = MatchClock()

    /// Increment banked so far. Fischer adds the full increment per move; Bronstein adds back only
    /// what the move actually used, up to the increment — which is the same thing as a delay, and
    /// is why both modes are one accumulator rather than two code paths.
    var bonus: TimeInterval = 0

    var moves: Int = 0

    /// Set the moment this clock reaches zero, so a flag stays fallen even if the clock is later
    /// paused or the opponent keeps playing.
    var hasFlagged: Bool = false
}

struct ChessClockState: Codable, Sendable, Hashable {
    var sides: [ChessClockSideState]

    /// Whose clock is running, or nil before the first press and while paused.
    var activeSlot: Int?

    /// Where the running side's clock stood when its turn began, so Bronstein can tell how long the
    /// move took. Nil when no turn is in progress.
    var turnStartSpent: TimeInterval?

    /// True once someone has pressed; distinguishes "not started" from "paused mid-game".
    var hasStarted: Bool = false

    init(sideCount: Int = 2) {
        sides = Array(repeating: ChessClockSideState(), count: max(2, sideCount))
    }
}

// MARK: - Derived boards

/// What a specialised board renders (§6.3).
///
/// An enum rather than a struct of optionals: each board's view takes exactly the payload it needs,
/// and adding a board cannot quietly leave another one's field nil.
///
/// `unavailable` remains as the safety net for a match synced from a build that knows a board this
/// one does not — the router shows "not available in this version" rather than an empty scoreboard.
/// With all five implemented it is no longer reachable from this build's own presets.
enum DerivedSpecialisedBoard: Sendable, Hashable {
    case chessClock(DerivedChessClockBoard)
    case raceTimer(DerivedRaceTimerBoard)
    case americanFootball(DerivedFootballBoard)
    case cricket(DerivedCricketBoard)
    case baseball(DerivedBaseballBoard)
    case unavailable(SpecialisedBoard)
}

// MARK: - Race timer

/// One racer's record (§6.3).
struct RaceTimerRacerState: Codable, Sendable, Hashable {
    /// Race time at each completed lap, cumulative. Lap durations are the differences between
    /// these, which is why the *crossing times* are what get stored: a stored duration would have to
    /// be recomputed every time a mis-tap was undone.
    var splits: [TimeInterval] = []

    /// Race time at which this racer finished, if they have.
    var finishedAt: TimeInterval?
}

struct RaceTimerState: Codable, Sendable, Hashable {
    /// One clock for the whole field — a race has a single start gun, and per-racer times are
    /// positions on that one timeline.
    var clock: MatchClock = MatchClock()
    var racers: [RaceTimerRacerState]

    init(racerCount: Int = 4) {
        racers = Array(repeating: RaceTimerRacerState(), count: max(1, racerCount))
    }
}

// MARK: - Cricket

/// One innings (§6.3).
struct CricketInningsState: Codable, Sendable, Hashable {
    /// Which side is batting.
    var battingSlot: Int = 0

    var runs: Int = 0
    var wickets: Int = 0

    /// Balls that counted towards the over. Wides and no-balls are excluded, which is exactly why
    /// this is stored rather than a count of deliveries.
    var legalBalls: Int = 0

    var extras: Int = 0
    /// Runs since the last wicket.
    var partnership: Int = 0

    var isClosed: Bool = false
}

struct CricketState: Codable, Sendable, Hashable {
    var innings: [CricketInningsState]
    var currentInnings: Int = 0

    init(firstBattingSlot: Int = 0) {
        innings = [CricketInningsState(battingSlot: firstBattingSlot)]
    }
}

// MARK: - Baseball

/// Who is on base (§6.3).
///
/// Three flags rather than a count, because a force play depends on *which* bases are occupied, not
/// how many.
struct BaseOccupancy: Codable, Sendable, Hashable {
    var first = false
    var second = false
    var third = false

    var isEmpty: Bool { !first && !second && !third }

    /// Batter to first, moving only the runners who have no choice — and scoring the one forced home
    /// from third.
    ///
    /// Returns the runs forced in. A *forced* run is not a judgement call, which is why this is the
    /// only path that changes the score on its own; anything else is the operator's explicit Run.
    mutating func forceAdvance() -> Int {
        if !first { first = true; return 0 }
        if !second { second = true; return 0 }
        if !third { third = true; return 0 }
        return 1
    }
}

struct BaseballSideState: Codable, Sendable, Hashable {
    /// Runs per inning, oldest first. The line score is this, and the total is its sum.
    var runsByInning: [Int] = []
    var hits: Int = 0
    var errors: Int = 0

    var runs: Int { runsByInning.reduce(0, +) }
}

struct BaseballState: Codable, Sendable, Hashable {
    var sides: [BaseballSideState]

    var inning: Int = 1
    /// The visiting side bats the top of the inning; the home side bats the bottom.
    var isTop: Bool = true

    var balls: Int = 0
    var strikes: Int = 0
    var outs: Int = 0
    var bases = BaseOccupancy()

    init(sideCount: Int = 2) {
        sides = Array(repeating: BaseballSideState(), count: max(2, sideCount))
    }

    /// Slot 0 is home and bats the bottom (§7.1).
    var battingSlot: Int { isTop ? 1 : 0 }
    var fieldingSlot: Int { isTop ? 0 : 1 }
}

// MARK: - American football

struct FootballSideState: Codable, Sendable, Hashable {
    var score: Int = 0
    /// Reset entering the second half, which is what "per half" means (§8.3).
    var timeoutsUsed: Int = 0
}

struct AmericanFootballState: Codable, Sendable, Hashable {
    var sides: [FootballSideState]

    var clock: MatchClock = MatchClock()
    var playClock: MatchClock = MatchClock()
    /// What the play clock is currently counting down from — 40 or 25 (§8.3).
    var playClockDuration: TimeInterval = 40

    var quarter: Int = 1
    var possessionSlot: Int?

    var down: Int = 1
    var yardsToGo: Int = 10

    /// Yards from the **possessing team's own goal line**, 0...`fieldLength`.
    ///
    /// Stored from the offence's point of view rather than as a painted field number, because that
    /// is the frame in which "and goal" and a first down are decided. The painted number a board
    /// shows counts up to midfield and back down again, and is derived from this.
    var ballOn: Int = 25

    var isFinished: Bool = false

    init(sideCount: Int = 2, playClockFull: TimeInterval = 40) {
        sides = Array(repeating: FootballSideState(), count: max(2, sideCount))
        playClockDuration = playClockFull
    }
}

// MARK: - Derived boards

struct DerivedBaseballBoard: Sendable, Hashable {
    struct Side: Sendable, Hashable {
        var slotIndex: Int
        var runs: Int
        var hits: Int
        var errors: Int
        /// Runs per inning. `nil` is an inning this side has not batted — which is not the same as
        /// a scoreless one, and a line score that printed 0 for it would be lying.
        var lineScore: [Int?]
        var isBatting: Bool
    }

    var sides: [Side]
    var inning: Int
    var isTop: Bool
    /// The innings the line score has columns for.
    var inningsPlayed: Int

    var balls: Int
    var strikes: Int
    var outs: Int
    var bases: BaseOccupancy

    var showsHitsAndErrors: Bool
    var isFinished: Bool

    /// "T5" or "B5" — top or bottom of the fifth.
    var inningLabel: String {
        isTop
            ? String(localized: "T\(inning)", comment: "Baseball inning")
            : String(localized: "B\(inning)", comment: "Baseball inning")
    }

    /// The count, balls before strikes, as everyone says it.
    var countText: String { "\(balls)-\(strikes)" }
}

struct DerivedCricketBoard: Sendable, Hashable {
    /// A completed innings, for the strip along the top.
    struct InningsLine: Sendable, Hashable {
        var battingSlot: Int
        var runs: Int
        var wickets: Int
        var oversText: String
        /// All ten down, so the score reads "180" rather than "180-10" the way a scorebook does.
        var isAllOut: Bool
    }

    var battingSlot: Int
    var bowlingSlot: Int

    var runs: Int
    var wickets: Int
    var isAllOut: Bool
    /// `overs.balls` — "12.3" is twelve complete overs and three balls.
    var oversText: String
    var extras: Int
    var partnership: Int

    var runRate: Double
    var requiredRate: Double?
    var target: Int?
    var runsNeeded: Int?
    var ballsRemaining: Int?

    var inningsNumber: Int
    var completedInnings: [InningsLine]
    var isFinished: Bool

    /// "180-4", or "180" once all ten are down — how a scorebook writes it.
    var scoreText: String {
        isAllOut ? "\(runs)" : "\(runs)-\(wickets)"
    }
}

struct DerivedFootballBoard: Sendable, Hashable {
    struct Side: Sendable, Hashable {
        var slotIndex: Int
        var score: Int
        var timeoutsRemaining: Int
        var hasPossession: Bool
    }

    var sides: [Side]
    var gameClock: ClockDisplay
    var playClock: ClockDisplay
    var quarterLabel: String
    var quarter: Int
    /// "3RD & 7", or "1ST & GOAL" inside the ten.
    var downAndDistance: String
    /// The yard-line number as painted on the field: up to midfield, then back down.
    var ballOnNumber: Int
    var possessionSlot: Int?
    var isFinished: Bool
}

struct DerivedRaceTimerBoard: Sendable, Hashable {
    struct Racer: Sendable, Hashable {
        var slotIndex: Int
        /// Nil until this racer has something to be placed on — see `DerivedRaceTimerBoard.rows`.
        var position: Int?
        var lapsCompleted: Int
        /// Time on the clock for this racer: their finish time, or the running race time.
        var elapsed: TimeInterval
        var lastLap: TimeInterval?
        var bestLap: TimeInterval?
        var hasFinished: Bool

        var clock: ClockDisplay {
            ClockDisplay(value: elapsed, isRunning: !hasFinished, showsTenths: true, hasExpired: false)
        }
    }

    /// In running order, best first.
    var rows: [Racer]
    var raceClock: ClockDisplay
    var hasStarted: Bool
    var lapCount: Int?
    var isFinished: Bool
}

struct DerivedChessClockBoard: Sendable, Hashable {
    struct Side: Sendable, Hashable {
        var slotIndex: Int
        /// Time left, already clamped at zero.
        var remaining: TimeInterval
        var isActive: Bool
        var hasFlagged: Bool
        var moves: Int

        /// Tenths appear under ten seconds, which is when a blitz game is decided by them.
        var clock: ClockDisplay {
            ClockDisplay(
                value: remaining,
                isRunning: isActive,
                showsTenths: remaining < 10,
                hasExpired: remaining <= 0
            )
        }
    }

    var sides: [Side]
    var activeSlot: Int?
    var hasStarted: Bool
    var isRunning: Bool
    /// The slot that ran out of time, if any.
    var flaggedSlot: Int?
    var incrementLabel: String
    var isFinished: Bool
}
