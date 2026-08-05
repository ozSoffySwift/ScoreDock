import Foundation

/// One participant's state on a list or table board (§6.5).
///
/// A single struct covers all four styles because they overlap more than they look: a leaderboard is
/// a score sheet with one round, and a standings row is a leaderboard row with the score computed
/// from a record rather than entered directly.
struct ListEntryState: Codable, Sendable, Hashable {
    /// Leaderboard total, and the score sheet's running total.
    var total: Int = 0

    /// Per-round scores, oldest first. Score sheet only.
    var rounds: [Int] = []

    // Standings.
    var won: Int = 0
    var drawn: Int = 0
    var lost: Int = 0
    var goalsFor: Int = 0
    var goalsAgainst: Int = 0

    var played: Int { won + drawn + lost }
    var goalDifference: Int { goalsFor - goalsAgainst }

    func points(_ rules: ListRules) -> Int {
        won * rules.pointsForWin + drawn * rules.pointsForDraw + lost * rules.pointsForLoss
    }
}

/// A single-elimination bracket (§6.5).
///
/// Matches are stored as one flat array, breadth-first: the first round occupies the first
/// `size / 2` slots, the next round the following `size / 4`, and so on, ending with the final.
/// A bracket of `size` entrants always has exactly `size - 1` matches, which is what makes the flat
/// layout safe to index arithmetically rather than walking a tree.
struct BracketState: Codable, Sendable, Hashable {
    /// Winning slot for each match, or nil while undecided.
    var winners: [Int?]
    var size: Int

    init(size: Int) {
        // Round up to a power of two; the empty places become byes.
        var rounded = 2
        while rounded < max(2, size) { rounded *= 2 }
        self.size = rounded
        winners = Array(repeating: nil, count: rounded - 1)
    }

    var roundCount: Int { Int(log2(Double(size))) }

    /// Number of matches in `round`, counting from zero.
    func matchCount(inRound round: Int) -> Int {
        max(0, size / (1 << (round + 1)))
    }

    /// Index of the first match of `round` within `winners`.
    func firstMatchIndex(inRound round: Int) -> Int {
        (0 ..< round).reduce(0) { $0 + matchCount(inRound: $1) }
    }

    func round(containing match: Int) -> Int {
        var round = 0
        var offset = 0
        while round < roundCount {
            let count = matchCount(inRound: round)
            if match < offset + count { return round }
            offset += count
            round += 1
        }
        return max(0, roundCount - 1)
    }

    /// The two entrants in a match, as participant slots — nil where the place is a bye or the
    /// feeding match has not been decided yet.
    func participants(inMatch match: Int) -> (Int?, Int?) {
        let round = round(containing: match)
        let positionInRound = match - firstMatchIndex(inRound: round)

        guard round > 0 else {
            // First round pairs entrants in listed order, which is what a bracket drawn down a page
            // looks like.
            return (positionInRound * 2, positionInRound * 2 + 1)
        }

        let previousFirst = firstMatchIndex(inRound: round - 1)
        let upper = previousFirst + positionInRound * 2
        let lower = upper + 1
        return (winners[safe: upper] ?? nil, winners[safe: lower] ?? nil)
    }
}

/// The list engine's complete state (§6.5).
struct ListState: Codable, Sendable, Hashable {
    var entries: [ListEntryState]

    /// Score sheet: the round currently being entered, zero-based.
    var currentRound: Int = 0

    var bracket: BracketState?
    var isFinished: Bool = false

    init(participantCount: Int = 4, style: ListStyle = .leaderboard, bracketSize: Int = 8) {
        entries = Array(repeating: ListEntryState(), count: max(1, participantCount))
        if style == .bracket {
            bracket = BracketState(size: bracketSize)
        }
    }

    func entry(_ slot: Int) -> ListEntryState? {
        entries.indices.contains(slot) ? entries[slot] : nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Derived board

/// What a list or table board renders (§6.5).
struct DerivedListBoard: Sendable, Hashable {
    struct Row: Sendable, Hashable, Identifiable {
        var slotIndex: Int
        /// Position in the table, sharing a number with anyone tied (§6.5).
        var rank: Int
        var isTiedRank: Bool
        var total: Int
        var rounds: [Int]
        var played: Int
        var won: Int
        var drawn: Int
        var lost: Int
        var goalsFor: Int
        var goalsAgainst: Int
        var goalDifference: Int
        var points: Int

        var id: Int { slotIndex }

        func value(for column: StandingsColumn) -> Int {
            switch column {
            case .played: played
            case .won: won
            case .drawn: drawn
            case .lost: lost
            case .goalsFor: goalsFor
            case .goalsAgainst: goalsAgainst
            case .goalDifference: goalDifference
            case .points: points
            }
        }
    }

    struct BracketMatch: Sendable, Hashable, Identifiable {
        var index: Int
        var round: Int
        var upperSlot: Int?
        var lowerSlot: Int?
        var winnerSlot: Int?
        /// One side is empty, so the other advances without playing (§6.5).
        var isBye: Bool
        var id: Int { index }
    }

    var style: ListStyle
    /// Already sorted into display order for leaderboard and standings; in entry order otherwise.
    var rows: [Row]
    var columns: [StandingsColumn]
    var roundCount: Int
    var currentRound: Int
    var bracketMatches: [BracketMatch]
    var bracketRoundCount: Int
    var champion: Int?
    var isFinished: Bool
}
