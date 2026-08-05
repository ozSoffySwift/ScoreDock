import Foundation

/// One side's state in a set-match game (§6.2).
struct SetMatchSideState: Codable, Sendable, Hashable {
    var setsWon: Int = 0

    /// Games won in the current set. Tennis only — numeric scoring goes straight from points to
    /// sets, with no intermediate unit.
    var gamesWon: Int = 0

    /// Points in the current game (tennis) or the current set (numeric).
    var points: Int = 0

    /// Legs won in the current set. Darts only.
    var legsWon: Int = 0

    /// Score left to check out from. Darts only.
    var remaining: Int = 501

    init(remaining: Int = 501) {
        self.remaining = remaining
    }
}

/// The set-match engine's complete state (§6.2).
struct SetMatchState: Codable, Sendable, Hashable {
    var sides: [SetMatchSideState]

    /// Finished sets, as `[side0, side1]` rows — the set history a board shows along the top.
    /// For tennis these are games won; for numeric scoring, points; for darts, legs.
    var completedSets: [[Int]] = []

    var servingSlot: Int?
    /// Points served consecutively, for rotation rules that alternate every N points.
    var servesInRotation: Int = 0

    /// True while a tiebreak is being played instead of a normal game.
    var isTiebreak: Bool = false

    /// Darts: the last visit went below zero, or left an unfinishable 1. Shown briefly on the board
    /// so the operator can see the entry was rejected rather than lost.
    var lastVisitBusted: Bool = false

    var isFinished: Bool = false

    init(sideCount: Int = 2, startScore: Int = 501) {
        sides = Array(repeating: SetMatchSideState(remaining: startScore), count: max(1, sideCount))
        servingSlot = 0
    }

    var currentSetNumber: Int { completedSets.count + 1 }

    func side(_ slot: Int) -> SetMatchSideState? {
        sides.indices.contains(slot) ? sides[slot] : nil
    }
}

// MARK: - Derived board

/// What a set-match board renders (§6.2).
///
/// **Sets won are the primary display; current-game points sit alongside.** That ordering is the
/// spec's, and it is what makes a tennis board readable — nobody watching cares that it is 30–15
/// as much as they care that it is 2 sets to 1.
struct DerivedSetMatchBoard: Sendable, Hashable {
    struct Side: Sendable, Hashable {
        var slotIndex: Int
        /// The headline number: sets won.
        var setsWon: Int
        /// The current game's score, already formatted for the notation — `40`, `AD`, `23`, `170`.
        var pointsText: String
        /// Games won in the current set, where the notation has games.
        var gamesWon: Int?
        /// Legs won in the current set, for darts.
        var legsWon: Int?
        var isServing: Bool
        /// Darts: a suggested checkout for the current remaining score, if there is one.
        var checkout: String?
    }

    var sides: [Side]
    /// Finished sets, oldest first.
    var completedSets: [[Int]]
    var currentSetNumber: Int
    var notation: ScoreNotation
    var isTiebreak: Bool
    var isMatchTiebreak: Bool
    var isDecidingSet: Bool
    var lastVisitBusted: Bool
    var isFinished: Bool

    /// A short label for the state of play — "Set 3", "Tiebreak", "Match tiebreak".
    var stageLabel: String {
        if isMatchTiebreak { return String(localized: "MATCH TIEBREAK", comment: "Set-match stage") }
        if isTiebreak { return String(localized: "TIEBREAK", comment: "Set-match stage") }
        return String(localized: "SET \(currentSetNumber)", comment: "Set-match stage")
    }
}
