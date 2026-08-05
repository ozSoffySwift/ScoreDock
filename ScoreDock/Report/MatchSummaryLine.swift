import Foundation

/// The one-line summary of a match, for the Play resume row and the History list.
///
/// Both call sites used to build this themselves as `zip(sides, displayScores).joined(" – ")`, which
/// is right for two sides and wrong for everything else. An eight-team league read
/// `Team 1 0 – Team 2 0 – Team 3 0 – …`: the wrong shape (a score line for a table) carrying the
/// wrong number (`displayScores` sums `.score` events, but a standings figure is *points* derived
/// from win/draw records, so every row was structurally 0).
///
/// So the summary is engine-aware, and lives in one place.
enum MatchSummaryLine {
    /// How many places a table lists before collapsing into "+N more".
    private static let tablePlaceLimit = 3

    static func text(for match: Match) -> String {
        let sides = match.orderedSides
        guard !sides.isEmpty else { return "" }

        if case let .list(rules) = match.rulesSnapshot {
            return listText(for: match, sides: sides, rules: rules)
        }

        // Team and set-match boards have two sides, and a score line is exactly right for them.
        return zip(sides, match.displayScores)
            .map { "\($0.displayName) \($1)" }
            .joined(separator: " – ")
    }

    // MARK: - Tables

    private static func listText(for match: Match, sides: [MatchSide], rules: ListRules) -> String {
        let board = ListEngine.derived(
            state(for: match, sides: sides, rules: rules),
            rules: rules,
            at: .now
        )

        if rules.style == .bracket {
            return bracketText(board: board, sides: sides)
        }

        // `derived` returns the rows already in rank order.
        let places = board.rows.prefix(tablePlaceLimit).map { row -> String in
            let name = sides.first { $0.slotIndex == row.slotIndex }?.displayName ?? ""
            let figure = rules.style == .standings ? row.points : row.total
            return "\(row.rank). \(name) \(figure)"
        }

        let remainder = board.rows.count - places.count
        guard remainder > 0 else { return places.joined(separator: " · ") }
        return (places + [morePlaces(remainder)]).joined(separator: " · ")
    }

    private static func bracketText(board: DerivedListBoard, sides: [MatchSide]) -> String {
        // A bracket has no running total to report, so it reports its progress instead.
        if let champion = board.champion,
           let winner = sides.first(where: { $0.slotIndex == champion }) {
            return String(localized: "Champion: \(winner.displayName)", comment: "Bracket summary")
        }

        // Deliberately no "x of y": in an oversized bracket some places have no entrants and can
        // never be decided, so any denominator drawn from the bracket size would be a target the
        // tournament cannot reach.
        let decided = board.bracketMatches.count { $0.winnerSlot != nil }
        return String(
            localized: "\(sides.count) seeds · \(decided) decided",
            comment: "Bracket summary — seeds, then matches with a result"
        )
    }

    private static func morePlaces(_ count: Int) -> String {
        String(localized: "+\(count) more", comment: "Table summary — places not listed")
    }

    /// Rebuilds table state from the log, honouring the stored snapshot when it is still valid.
    private static func state(for match: Match, sides: [MatchSide], rules: ListRules) -> ListState {
        let events = match.orderedEvents

        // A closed match keeps its final state in the snapshot, so the common History case replays
        // nothing at all.
        var snapshot: (state: ListState, upToIndex: Int)?
        if let blob = match.stateBlob,
           MatchReplay.isSnapshotValid(upToIndex: match.snapshotEventIndex, events: events),
           let stored = try? JSONDecoder().decode(ListState.self, from: blob) {
            snapshot = (stored, match.snapshotEventIndex)
        }

        return MatchReplay.state(
            ListEngine.self,
            rules: rules,
            sideCount: sides.count,
            events: events,
            snapshot: snapshot
        )
    }
}
