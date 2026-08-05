import Foundation

/// The list and table engine — 4 presets (§6.5).
///
/// Four boards over **N participants** rather than two sides, which is the real difference from the
/// other engines: `MatchSide.slotIndex` was always specified as "0 = home, 1 = visitor, n for
/// leaderboards" (§7.1), and this is where the *n* is used.
///
/// The model is kept deliberately general. §6.5 notes the score sheet is the natural bridge to the
/// board-game side of the portfolio, and §19.2 leaves standalone-vs-shared-module open — so nothing
/// here assumes a sport, and a future integration stays a data question rather than a rewrite.
enum ListEngine: ScoreEngine {
    static var kind: EngineKind { .list }

    static func initialState(rules: ListRules, sideCount: Int) -> ListState {
        var state = ListState(
            participantCount: sideCount > 0 ? sideCount : rules.participantCount,
            style: rules.style,
            bracketSize: rules.bracketSize
        )
        if rules.style == .scoreSheet {
            for index in state.entries.indices {
                state.entries[index].rounds = Array(repeating: 0, count: max(1, rules.roundCount))
            }
        }
        return state
    }

    // MARK: - Apply

    static func apply(_ action: EngineAction, to state: inout ListState, rules: ListRules, at now: Date) {
        guard !state.isFinished else { return }

        switch action {
        case let .score(slot, points, _):
            guard state.entries.indices.contains(slot) else { return }
            switch rules.style {
            case .scoreSheet:
                // Points land in the round being entered, and the total is always the sum of the
                // rounds — never a separate number that could drift away from them.
                let round = min(state.currentRound, max(0, state.entries[slot].rounds.count - 1))
                guard state.entries[slot].rounds.indices.contains(round) else { return }
                state.entries[slot].rounds[round] += points
                state.entries[slot].total = state.entries[slot].rounds.reduce(0, +)
            case .leaderboard, .standings, .bracket:
                state.entries[slot].total += points
            }

        case let .adjustRecord(slot, field, delta):
            guard state.entries.indices.contains(slot) else { return }
            switch field {
            case .won: state.entries[slot].won = max(0, state.entries[slot].won + delta)
            case .drawn: state.entries[slot].drawn = max(0, state.entries[slot].drawn + delta)
            case .lost: state.entries[slot].lost = max(0, state.entries[slot].lost + delta)
            case .goalsFor: state.entries[slot].goalsFor = max(0, state.entries[slot].goalsFor + delta)
            case .goalsAgainst: state.entries[slot].goalsAgainst = max(0, state.entries[slot].goalsAgainst + delta)
            }

        case let .setBracketWinner(match, slot):
            guard var bracket = state.bracket, bracket.winners.indices.contains(match) else { return }
            bracket.winners[match] = slot
            // Changing an earlier result invalidates everything downstream of it — leaving a stale
            // finalist in a later round would be worse than clearing the bracket back to that point.
            clearDownstream(of: match, in: &bracket)
            state.bracket = bracket

        case .advancePeriod:
            guard rules.style == .scoreSheet else { return }
            state.currentRound = min(state.currentRound + 1, max(0, rules.roundCount - 1))

        case .previousPeriod:
            guard rules.style == .scoreSheet else { return }
            state.currentRound = max(0, state.currentRound - 1)

        case .finishMatch:
            state.isFinished = true

        default:
            // Clocks, fouls, serve and the rest have no meaning on a table.
            break
        }
    }

    /// Clears results that depended on `match`, walking forward through the bracket.
    private static func clearDownstream(of match: Int, in bracket: inout BracketState) {
        var current = match
        let rounds = bracket.roundCount
        var round = bracket.round(containing: match)

        while round < rounds - 1 {
            let positionInRound = current - bracket.firstMatchIndex(inRound: round)
            let nextRound = round + 1
            let next = bracket.firstMatchIndex(inRound: nextRound) + positionInRound / 2
            guard bracket.winners.indices.contains(next) else { return }
            bracket.winners[next] = nil
            current = next
            round = nextRound
        }
    }

    // MARK: - Derived

    static func derived(_ state: ListState, rules: ListRules, at now: Date) -> DerivedListBoard {
        var rows = state.entries.enumerated().map { index, entry in
            DerivedListBoard.Row(
                slotIndex: index,
                rank: 0,
                isTiedRank: false,
                total: entry.total,
                rounds: entry.rounds,
                played: entry.played,
                won: entry.won,
                drawn: entry.drawn,
                lost: entry.lost,
                goalsFor: entry.goalsFor,
                goalsAgainst: entry.goalsAgainst,
                goalDifference: entry.goalDifference,
                points: entry.points(rules)
            )
        }

        switch rules.style {
        case .leaderboard, .scoreSheet:
            rows = ranked(rows, by: { $0.total }, higherIsBetter: rules.higherIsBetter, rules: rules)
        case .standings:
            // Points, then goal difference, then goals scored — the conventional league order.
            rows = ranked(
                rows,
                by: { $0.points * 1_000_000 + $0.goalDifference * 1_000 + $0.goalsFor },
                higherIsBetter: true,
                rules: rules
            )
        case .bracket:
            break
        }

        let matches = state.bracket.map { bracket in
            (0 ..< bracket.winners.count).map { index -> DerivedListBoard.BracketMatch in
                let (upper, lower) = bracket.participants(inMatch: index)
                let round = bracket.round(containing: index)
                let hasUpper = state.entries.indices.contains(upper ?? -1)
                let hasLower = state.entries.indices.contains(lower ?? -1)

                // A bye is *exactly one* entrant with no opponent — they advance unplayed. A place
                // with neither entrant is simply an unused half of an oversized bracket, and calling
                // that a bye would be nonsense.
                let isBye = round == 0 && (hasUpper != hasLower)

                return DerivedListBoard.BracketMatch(
                    index: index,
                    round: round,
                    upperSlot: hasUpper ? upper : nil,
                    lowerSlot: hasLower ? lower : nil,
                    winnerSlot: bracket.winners[index] ?? autoAdvance(isBye: isBye, upper: upper, lower: lower, state: state),
                    isBye: isBye
                )
            }
        } ?? []

        return DerivedListBoard(
            style: rules.style,
            rows: rows,
            columns: rules.columns,
            roundCount: rules.style == .scoreSheet ? max(1, rules.roundCount) : 0,
            currentRound: state.currentRound,
            bracketMatches: matches,
            bracketRoundCount: state.bracket?.roundCount ?? 0,
            champion: matches.last?.winnerSlot,
            isFinished: state.isFinished
        )
    }

    /// A bye needs no result — the single entrant advances on its own (§6.5).
    private static func autoAdvance(isBye: Bool, upper: Int?, lower: Int?, state: ListState) -> Int? {
        guard isBye else { return nil }
        if let upper, state.entries.indices.contains(upper) { return upper }
        if let lower, state.entries.indices.contains(lower) { return lower }
        return nil
    }

    /// Ranks rows, sharing a position between ties (§6.5).
    ///
    /// Standard competition ranking: two entries tied for first are both 1st and the next is 3rd.
    /// §6.5 asks for ties to be "handled explicitly", so the tie is *marked* as well as shared —
    /// a board that silently orders equal scores invites an argument.
    private static func ranked(
        _ rows: [DerivedListBoard.Row],
        by score: (DerivedListBoard.Row) -> Int,
        higherIsBetter: Bool,
        rules: ListRules
    ) -> [DerivedListBoard.Row] {
        let sorted = rows.sorted { lhs, rhs in
            let left = score(lhs)
            let right = score(rhs)
            if left != right { return higherIsBetter ? left > right : left < right }
            // Stable tie-break on entry order, so the table does not shuffle between refreshes.
            return lhs.slotIndex < rhs.slotIndex
        }

        return sorted.map { row in
            var updated = row
            let mine = score(row)
            let better = sorted.count {
                higherIsBetter ? score($0) > mine : score($0) < mine
            }
            updated.rank = better + 1
            updated.isTiedRank = rules.sharedRanksOnTie && sorted.count { score($0) == mine } > 1
            return updated
        }
    }

    // MARK: - Outcome

    static func outcome(_ state: ListState, rules: ListRules, at now: Date) -> MatchOutcome? {
        guard state.isFinished else { return nil }
        let board = derived(state, rules: rules, at: now)

        if rules.style == .bracket {
            guard let champion = board.champion else { return nil }
            var ranks: [Int: Int] = [:]
            for index in state.entries.indices { ranks[index] = index == champion ? 1 : 2 }
            return MatchOutcome(winningSlots: [champion], isDraw: false, rankBySlot: ranks)
        }

        var ranks: [Int: Int] = [:]
        for row in board.rows { ranks[row.slotIndex] = row.rank }
        let winners = board.rows.filter { $0.rank == 1 }.map(\.slotIndex)

        return MatchOutcome(
            winningSlots: winners.count == board.rows.count ? [] : winners,
            isDraw: winners.count > 1,
            rankBySlot: ranks
        )
    }
}
