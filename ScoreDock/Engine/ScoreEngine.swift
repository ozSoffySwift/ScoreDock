import Foundation

/// The contract every board in the app satisfies (§6).
///
/// Engines are **pure value logic with no UI, no SwiftData and no clock of their own.** That is what
/// makes them exhaustively unit-testable, which matters enormously when shipping 37 rule variants.
///
/// One deliberate departure from the spec's signature: `derived` and `outcome` take `at now: Date`.
/// The engine holds date-anchored clocks (§6.4) rather than counters, so *what the board shows*
/// genuinely depends on the instant you ask. Passing `now` in keeps the engine pure — the caller
/// supplies time — instead of having it reach for `Date.now` internally, which would make every
/// clock test unreproducible.
protocol ScoreEngine {
    associatedtype Rules: Codable & Sendable
    associatedtype State: Codable & Sendable

    /// What this engine's board renders.
    ///
    /// An associated type rather than one shared struct: a team board leads with a clock, a
    /// set-match board leads with sets won. Forcing both through one type would mean a pile of
    /// optional properties that are nil most of the time — the same shape §7.3 rejects for rules,
    /// and for the same reason.
    associatedtype Board: Sendable

    static var kind: EngineKind { get }

    static func initialState(rules: Rules, sideCount: Int) -> State

    static func apply(_ action: EngineAction, to state: inout State, rules: Rules, at now: Date)

    /// What the board renders.
    static func derived(_ state: State, rules: Rules, at now: Date) -> Board

    /// Nil while the match is still in progress.
    static func outcome(_ state: State, rules: Rules, at now: Date) -> MatchOutcome?
}

// MARK: - Actions

/// Everything an operator can do, as data.
///
/// Actions are `Codable` because they are the vocabulary of the event log (§6.6) — recording one is
/// what buys undo, the shareable play-by-play, per-player attribution, crash recovery and dispute
/// resolution all at once.
enum EngineAction: Codable, Sendable, Hashable {
    /// `playerID` is nil unless per-player attribution is on for this match, and stays optional even
    /// then: an unattributed score must always be one tap away, because a mis-tap under pressure is
    /// worse than missing data (§4.2).
    case score(slot: Int, points: Int, playerID: UUID? = nil)

    case foul(slot: Int, delta: Int)
    case timeout(slot: Int, delta: Int)

    case advancePeriod
    case previousPeriod
    /// OT / SO / HT / F, or nil to fall back to the rules' labelling (§4.2).
    case setPeriodLabel(String?)

    case toggleClock
    /// Sets elapsed time on the main clock — the long-press reset, and manual correction.
    case setClockElapsed(TimeInterval)

    case toggleShotClock
    /// Tap resets to full, long-press to the short value (§4.2).
    case resetShotClock(full: Bool)

    /// Flip to a side, or nil to clear (§4.2).
    case setPossession(Int?)

    /// The break timer *replaces* the main timer, then hands control back to regulation time at
    /// exactly the paused value (§6.1).
    case startBreak(TimeInterval)
    case endBreak

    // MARK: List and table boards (§6.5)

    /// Records who advances from a bracket match, or nil to clear it. Matches are indexed
    /// breadth-first from the first round.
    case setBracketWinner(match: Int, slot: Int?)

    /// Adjusts one column of a side's league record.
    case adjustRecord(slot: Int, field: RecordField, delta: Int)

    // MARK: Specialised boards (§6.3)

    /// The bespoke vocabulary of the five specialised boards, nested rather than flattened — see
    /// `SpecialisedAction` for why.
    case specialised(SpecialisedAction)

    case finishMatch
}

/// The columns of a standings row an operator can change directly (§6.5).
///
/// Played, goal difference and points are *computed* and therefore absent — a table where those
/// could drift out of step with the results that produced them would be worse than no table.
enum RecordField: String, Codable, CaseIterable, Sendable {
    case won, drawn, lost, goalsFor, goalsAgainst

    var shortLabel: String {
        switch self {
        case .won: "W"
        case .drawn: "D"
        case .lost: "L"
        case .goalsFor: "GF"
        case .goalsAgainst: "GA"
        }
    }
}

// MARK: - Derived board

/// What the board renders, resolved for one instant.
struct DerivedBoard: Sendable, Hashable {
    var sides: [DerivedSide]
    var primaryClock: ClockDisplay
    var periodLabel: String
    var period: Int
    var shotClock: ClockDisplay?
    var possessionSlot: Int?
    /// True while a break replaces the main clock, so the board can label it.
    var isBreak: Bool
    var isFinished: Bool
}

struct DerivedSide: Sendable, Hashable {
    var slotIndex: Int
    var score: Int
    var fouls: Int?
    var timeoutsRemaining: Int?
    /// Team fouls have reached the bonus threshold. Carries an icon on the board as well as a
    /// colour, because colour is never the only signal (§15).
    var isInBonus: Bool
    /// At or past the foul limit.
    var hasFouledOut: Bool
}

// MARK: - Outcome

struct MatchOutcome: Sendable, Hashable {
    /// Slot indices of the winning side(s). Empty means a draw.
    var winningSlots: [Int]
    var isDraw: Bool
    /// Final ranking by slot, for boards with more than two sides.
    var rankBySlot: [Int: Int]

    func outcome(forSlot slot: Int) -> SideOutcome {
        if isDraw { return .draw }
        return winningSlots.contains(slot) ? .win : .loss
    }
}
