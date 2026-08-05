import Foundation

/// Which bespoke board is in play (§6.3).
enum SpecialisedBoard: String, DefaultingRawEnum {
    case americanFootball, cricket, baseball, chessClock, raceTimer

    static var fallback: Self { .chessClock }
}

/// Rules for the five specialised boards (§6.3).
///
/// **Scope note.** These engines are sequenced last (M6) and are individually the most expensive
/// items in the backlog — each is effectively a small app. What is modelled here is exactly the
/// parameter set §8.3 confirms, so all five presets are browsable and configurable at M0 without
/// pre-committing to rule detail that M6 will discover. Each sub-struct is expected to grow; the
/// decode-with-defaults discipline means growing it is not a migration.
///
/// Modelled as a discriminator plus optional sub-structs rather than an enum with associated
/// values, so adding a board is additive and a blob written for a board this build does not know
/// still decodes.
struct SpecialisedRules: Codable, Hashable, Sendable {
    var board: SpecialisedBoard = .chessClock

    var americanFootball: AmericanFootballRules?
    var cricket: CricketRules?
    var baseball: BaseballRules?
    var chessClock: ChessClockRules?
    var raceTimer: RaceTimerRules?

    init(board: SpecialisedBoard = .chessClock) {
        self.board = board
    }
}

extension SpecialisedRules {
    private enum CodingKeys: String, CodingKey {
        case board, americanFootball, cricket, baseball, chessClock, raceTimer
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(board: SpecialisedBoard(storedRaw: try c.decodeIfPresent(String.self, forKey: .board)))
        americanFootball = try c.decodeIfPresent(AmericanFootballRules.self, forKey: .americanFootball)
        cricket = try c.decodeIfPresent(CricketRules.self, forKey: .cricket)
        baseball = try c.decodeIfPresent(BaseballRules.self, forKey: .baseball)
        chessClock = try c.decodeIfPresent(ChessClockRules.self, forKey: .chessClock)
        raceTimer = try c.decodeIfPresent(RaceTimerRules.self, forKey: .raceTimer)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(board.rawValue, forKey: .board)
        try c.encodeIfPresent(americanFootball, forKey: .americanFootball)
        try c.encodeIfPresent(cricket, forKey: .cricket)
        try c.encodeIfPresent(baseball, forKey: .baseball)
        try c.encodeIfPresent(chessClock, forKey: .chessClock)
        try c.encodeIfPresent(raceTimer, forKey: .raceTimer)
    }
}

// MARK: - Per-board parameters

/// Game clock *and* play clock, quarter, down & distance, ball-on, possession, timeouts per half.
struct AmericanFootballRules: Codable, Hashable, Sendable {
    var quarterCount: Int = 4
    var quarterLength: TimeInterval = 900
    var playClockNormal: TimeInterval = 40
    var playClockShort: TimeInterval = 25
    var timeoutsPerHalf: Int = 3
    var fieldLength: Int = 100
    var downsToConvert: Int = 4
    var yardsToConvert: Int = 10
}

/// Runs / wickets / overs.balls, innings, format, run rates, target, partnership.
struct CricketRules: Codable, Hashable, Sendable {
    enum Format: String, Codable, Sendable { case t20, odi, test }

    var format: Format = .t20
    var oversPerInnings: Int = 20
    var ballsPerOver: Int = 6
    var wicketsPerInnings: Int = 10
    var inningsPerSide: Int = 1
    var showRunRate: Bool = true
    var showRequiredRate: Bool = true
}

/// Inning-by-inning line score, R / H / E, balls / strikes / outs, base occupancy, top/bottom.
struct BaseballRules: Codable, Hashable, Sendable {
    var inningCount: Int = 9
    var outsPerHalfInning: Int = 3
    var strikesPerOut: Int = 3
    var ballsPerWalk: Int = 4
    var showHitsAndErrors: Bool = true
    /// Extra innings continue past `inningCount` until a side leads at the end of a full inning.
    var allowsExtraInnings: Bool = true
}

/// Two independent clocks with an increment, a move counter, and flag detection.
struct ChessClockRules: Codable, Hashable, Sendable {
    enum Increment: String, Codable, Sendable {
        /// Add the increment after each move.
        case fischer
        /// Delay before the clock starts running; unused time is not banked.
        case bronstein
        case none
    }

    var baseTime: TimeInterval = 300
    var incrementMode: Increment = .fischer
    var incrementSeconds: TimeInterval = 3
    var countMoves: Bool = true
    /// Whether reaching zero ends the game immediately.
    var flagEndsGame: Bool = true
}

/// Multi-racer stopwatch with per-racer lap times, splits and running order.
struct RaceTimerRules: Codable, Hashable, Sendable {
    var racerCount: Int = 4
    var lapCount: Int?
    var recordSplits: Bool = true
    /// Lower elapsed time ranks first — the opposite of the leaderboard default.
    var lowerTimeWins: Bool = true
}
