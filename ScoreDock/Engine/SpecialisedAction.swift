import Foundation

/// The bespoke half of the operator's vocabulary — what the five specialised boards can do (§6.3).
///
/// **Why these are nested under one `EngineAction.specialised` case rather than flattened into it.**
/// `EngineAction` is the *cross-engine* vocabulary: `score`, `toggleClock` and `timeout` mean
/// something on almost every board, which is why `TeamEngine` switches over it exhaustively — adding
/// one there should force every engine to decide what it means. Pressing a chess clock has no
/// meaning on a basketball board and never will, so putting these in the same flat enum would add
/// eleven cases that every other engine must dismiss, and would dilute exactly the signal that
/// exhaustiveness check exists to give.
///
/// Each case still earns its own `EventKind`, because §13.3 wants a legible play-by-play, not a row
/// of `correction`s.
enum SpecialisedAction: Codable, Sendable, Hashable {
    // MARK: Chess clock

    /// The player at `slot` has completed a move: their clock stops and takes its increment, and
    /// their opponent's starts. This is one button on a physical clock, and it is one action here.
    case pressClock(slot: Int)

    // MARK: Race timer

    case recordLap(slot: Int)
    case finishRacer(slot: Int)

    // MARK: American football

    case setDownAndDistance(down: Int, yardsToGo: Int)
    /// Yard line the ball is spotted on, as the scoreboard shows it (0...`fieldLength`).
    case setBallOn(yardLine: Int)

    // MARK: Cricket

    /// One delivery.
    ///
    /// `runs` is what was scored *in addition to* the extra's own penalty — runs off the bat, runs
    /// the batters ran, or byes. A wide with nothing run is `runs: 0, extra: .wide` and adds one;
    /// a no-ball hit for four is `runs: 4, extra: .noBall` and adds five.
    case delivery(runs: Int, extra: CricketExtra?)
    case wicket(kind: WicketKind)
    case endInnings

    // MARK: Baseball

    case pitch(PitchOutcome)
    /// Which bases are occupied, as a first/second/third triple. Set directly because a scorer
    /// watches the runners rather than deriving them.
    case setBases(first: Bool, second: Bool, third: Bool)
    case advanceHalfInning
}

// MARK: - Cricket vocabulary

/// A delivery that is not a plain legal ball (§6.3).
///
/// The distinction that matters to the board is whether the ball counts towards the over: a wide or
/// a no-ball does not, a bye or leg-bye does. Both still add runs.
enum CricketExtra: String, Codable, CaseIterable, Sendable {
    case wide, noBall, bye, legBye

    /// Whether the delivery counts as one of the over's balls (MCC Law 22.1 / 21.1 for the first two).
    var countsAsBall: Bool {
        switch self {
        case .wide, .noBall: false
        case .bye, .legBye: true
        }
    }

    /// Runs the extra itself concedes, before anything the batters run.
    var penaltyRuns: Int {
        switch self {
        case .wide, .noBall: 1
        case .bye, .legBye: 0
        }
    }

    var shortLabel: String {
        switch self {
        case .wide: "WD"
        case .noBall: "NB"
        case .bye: "B"
        case .legBye: "LB"
        }
    }
}

enum WicketKind: String, Codable, CaseIterable, Sendable {
    case bowled, caught, lbw, runOut, stumped, other

    var shortLabel: String {
        switch self {
        case .bowled: String(localized: "Bowled", comment: "Cricket dismissal")
        case .caught: String(localized: "Caught", comment: "Cricket dismissal")
        case .lbw: String(localized: "LBW", comment: "Cricket dismissal")
        case .runOut: String(localized: "Run out", comment: "Cricket dismissal")
        case .stumped: String(localized: "Stumped", comment: "Cricket dismissal")
        case .other: String(localized: "Out", comment: "Cricket dismissal")
        }
    }
}

// MARK: - Baseball vocabulary

/// What one pitch produced, at the level a scoreboard tracks (§6.3).
enum PitchOutcome: String, Codable, CaseIterable, Sendable {
    case ball, strike
    /// A foul, which is a strike except that it cannot be the third one.
    case foul
    case out
    case hit
    case error
    /// A run crossed the plate. Kept as a pitch outcome so the board's one control strip covers
    /// everything an operator taps between pitches.
    case run

    var shortLabel: String {
        switch self {
        case .ball: String(localized: "Ball", comment: "Baseball pitch outcome")
        case .strike: String(localized: "Strike", comment: "Baseball pitch outcome")
        case .foul: String(localized: "Foul", comment: "Baseball pitch outcome")
        case .out: String(localized: "Out", comment: "Baseball pitch outcome")
        case .hit: String(localized: "Hit", comment: "Baseball pitch outcome")
        case .error: String(localized: "Error", comment: "Baseball pitch outcome")
        case .run: String(localized: "Run", comment: "Baseball pitch outcome")
        }
    }
}
