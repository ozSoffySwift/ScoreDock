import Foundation

/// The board a match finished on, captured for export (§13.4, §13.5).
///
/// **Why this exists.** The share card used to lay the result out itself — sides stacked as rows
/// with the score on the right — which meant a shared card looked nothing like the board the game
/// was actually played on. §13.4 asks for the card to be rendered in the match's own theme so it
/// *matches* the board; re-describing the result in a different arrangement misses the point, and on
/// the bespoke boards it lost information outright (a cricket card cannot say `184-3 in 12.4` with
/// two names and two numbers).
///
/// So the card now renders the **real board view**, and this is what makes that possible from a
/// `Sendable` snapshot: every engine's derived board is already a `Sendable` value, so the export
/// model can carry one and the renderer never reaches back into SwiftData.
enum ExportedBoard: Sendable, Hashable {
    case team(DerivedBoard, TeamRules)
    case setMatch(DerivedSetMatchBoard)
    case list(DerivedListBoard)
    case specialised(DerivedSpecialisedBoard)

    /// Width ÷ height the board wants on a card.
    ///
    /// Each board letterboxes itself to roughly this, so giving it a frame of the wrong shape leaves
    /// dead space or crops the content. Kept here rather than in the card so the number lives with
    /// the board that has the opinion.
    var preferredAspect: CGFloat {
        switch self {
        case .team, .setMatch:
            return 1.9
        case .list:
            return 1.5
        case let .specialised(board):
            switch board {
            case .americanFootball, .cricket: return 1.9
            case .chessClock: return 1.8
            case .baseball: return 2.1
            case .raceTimer: return 1.4
            case .unavailable: return 1.9
            }
        }
    }
}

extension MatchExportBuilder {
    /// Replays the log into the board the match ended on.
    ///
    /// Taken at `endedAt` for a closed match and at `now` for a live one, so a card shared mid-match
    /// shows the clock where it actually is.
    @MainActor
    static func board(for match: Match, at now: Date = .now) -> ExportedBoard? {
        guard let rules = match.rulesSnapshot else { return nil }
        let events = match.orderedEvents
        let sideCount = match.orderedSides.count
        let instant = match.endedAt ?? now

        switch rules {
        case let .team(rules):
            let state = MatchReplay.state(TeamEngine.self, rules: rules, sideCount: sideCount, events: events)
            return .team(TeamEngine.derived(state, rules: rules, at: instant), rules)

        case let .setMatch(rules):
            let state = MatchReplay.state(SetMatchEngine.self, rules: rules, sideCount: sideCount, events: events)
            return .setMatch(SetMatchEngine.derived(state, rules: rules, at: instant))

        case let .list(rules):
            let state = MatchReplay.state(ListEngine.self, rules: rules, sideCount: sideCount, events: events)
            return .list(ListEngine.derived(state, rules: rules, at: instant))

        case let .specialised(rules):
            let state = MatchReplay.state(SpecialisedEngine.self, rules: rules, sideCount: sideCount, events: events)
            return .specialised(SpecialisedEngine.derived(state, rules: rules, at: instant))
        }
    }
}
