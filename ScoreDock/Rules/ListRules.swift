import Foundation

/// Which of the four list/table boards is in play (§6.5).
enum ListStyle: String, DefaultingRawEnum {
    case leaderboard, standings, bracket, scoreSheet

    static var fallback: Self { .leaderboard }
}

/// A column in a standings table. Kept as an enum rather than free text so the engine can compute
/// each one; custom columns would need a formula language, which is out of scope.
enum StandingsColumn: String, Codable, CaseIterable, Sendable {
    case played, won, drawn, lost, goalsFor, goalsAgainst, goalDifference, points

    var shortLabel: String {
        switch self {
        case .played: "P"
        case .won: "W"
        case .drawn: "D"
        case .lost: "L"
        case .goalsFor: "GF"
        case .goalsAgainst: "GA"
        case .goalDifference: "GD"
        case .points: "Pts"
        }
    }
}

/// Rules for the list/table engine — 4 presets (§6.5).
///
/// Kept deliberately general: the score sheet is the natural bridge to the board-game side of the
/// portfolio, and §19.2 leaves standalone-vs-shared-module open. Keeping the model general means
/// that integration stays a data question rather than a rewrite.
struct ListRules: Codable, Hashable, Sendable {
    var style: ListStyle = .leaderboard

    /// Leaderboard: whether a higher score ranks first. Golf and race times want the opposite.
    var higherIsBetter: Bool = true
    /// Ties share a rank rather than being broken arbitrarily — handled explicitly, per §6.5.
    var sharedRanksOnTie: Bool = true

    // MARK: Standings
    var columns: [StandingsColumn] = [.played, .won, .drawn, .lost, .goalDifference, .points]
    var pointsForWin: Int = 3
    var pointsForDraw: Int = 1
    var pointsForLoss: Int = 0

    // MARK: Bracket
    /// Seeds in a single-elimination bracket: 4, 8, 16 or 32. Non-powers of two get byes.
    var bracketSize: Int = 8

    // MARK: Score sheet
    var roundCount: Int = 10
    var participantCount: Int = 4
    var showRunningTotals: Bool = true

    init() {}
}

extension ListRules {
    private enum CodingKeys: String, CodingKey {
        case style, higherIsBetter, sharedRanksOnTie
        case columns, pointsForWin, pointsForDraw, pointsForLoss
        case bracketSize, roundCount, participantCount, showRunningTotals
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ListRules()
        self.init()
        style = ListStyle(storedRaw: try c.decodeIfPresent(String.self, forKey: .style))
        higherIsBetter = try c.value(.higherIsBetter, or: d.higherIsBetter)
        sharedRanksOnTie = try c.value(.sharedRanksOnTie, or: d.sharedRanksOnTie)
        // Unknown column names are dropped rather than throwing, so a preset written by a newer
        // build still opens with the columns this build understands.
        let rawColumns = try c.decodeIfPresent([String].self, forKey: .columns)
        columns = rawColumns.map { $0.compactMap(StandingsColumn.init(rawValue:)) } ?? d.columns
        pointsForWin = try c.value(.pointsForWin, or: d.pointsForWin)
        pointsForDraw = try c.value(.pointsForDraw, or: d.pointsForDraw)
        pointsForLoss = try c.value(.pointsForLoss, or: d.pointsForLoss)
        bracketSize = try c.value(.bracketSize, or: d.bracketSize)
        roundCount = try c.value(.roundCount, or: d.roundCount)
        participantCount = try c.value(.participantCount, or: d.participantCount)
        showRunningTotals = try c.value(.showRunningTotals, or: d.showRunningTotals)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(style.rawValue, forKey: .style)
        try c.encode(higherIsBetter, forKey: .higherIsBetter)
        try c.encode(sharedRanksOnTie, forKey: .sharedRanksOnTie)
        try c.encode(columns.map(\.rawValue), forKey: .columns)
        try c.encode(pointsForWin, forKey: .pointsForWin)
        try c.encode(pointsForDraw, forKey: .pointsForDraw)
        try c.encode(pointsForLoss, forKey: .pointsForLoss)
        try c.encode(bracketSize, forKey: .bracketSize)
        try c.encode(roundCount, forKey: .roundCount)
        try c.encode(participantCount, forKey: .participantCount)
        try c.encode(showRunningTotals, forKey: .showRunningTotals)
    }
}
