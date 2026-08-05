import Foundation

/// How a set-match score is written on the board (§6.2).
enum ScoreNotation: String, DefaultingRawEnum {
    /// Plain running points — volleyball, badminton, table tennis, squash, pickleball.
    case numeric
    /// 0 / 15 / 30 / 40 / Ad, with deuce and games rolling up into sets.
    case tennis
    /// Counting *down* from a start score to exactly zero, with bust handling.
    case dartsCountdown

    static var fallback: Self { .numeric }
}

/// Rules for the set-match engine — 8 presets, rally scoring (§6.2).
struct SetMatchRules: Codable, Hashable, Sendable {
    /// Sets needed to take the match. 3 for a best-of-5, 2 for a best-of-3.
    var setsToWin: Int = 2
    var pointsPerSet: Int = 21
    /// Deciding sets are often shorter — volleyball's fifth set is to 15, not 25.
    var decidingSetPoints: Int = 15
    var winByTwo: Bool = true
    /// Hard ceiling where a win-by-two rally cannot run forever (badminton caps at 30). Nil = uncapped.
    var hardCap: Int?

    var serveTracking: Bool = false
    /// Consecutive points before serve changes hands. 1 is rally-point serve alternation;
    /// table tennis uses 2.
    var servesPerRotation: Int = 1

    var notation: ScoreNotation = .numeric

    // MARK: Tiebreak
    var tiebreakEnabled: Bool = false
    var tiebreakPoints: Int = 7
    /// Replace a full deciding set with a first-to-N tiebreak (tennis match tiebreak).
    var matchTiebreak: Bool = false
    /// Target for that match tiebreak. Ten is the common form; still user-editable (§8.5).
    var matchTiebreakPoints: Int = 10

    // MARK: Darts
    /// Starting score for `dartsCountdown`, e.g. 501.
    var startScore: Int = 501
    var legsPerSet: Int = 3
    /// Whether a leg must finish exactly on a double.
    var doubleOut: Bool = true

    init() {}
}

extension SetMatchRules {
    private enum CodingKeys: String, CodingKey {
        case setsToWin, pointsPerSet, decidingSetPoints, winByTwo, hardCap
        case serveTracking, servesPerRotation, notation
        case tiebreakEnabled, tiebreakPoints, matchTiebreak, matchTiebreakPoints
        case startScore, legsPerSet, doubleOut
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SetMatchRules()
        self.init()
        setsToWin = try c.value(.setsToWin, or: d.setsToWin)
        pointsPerSet = try c.value(.pointsPerSet, or: d.pointsPerSet)
        decidingSetPoints = try c.value(.decidingSetPoints, or: d.decidingSetPoints)
        winByTwo = try c.value(.winByTwo, or: d.winByTwo)
        hardCap = try c.decodeIfPresent(Int.self, forKey: .hardCap)
        serveTracking = try c.value(.serveTracking, or: d.serveTracking)
        servesPerRotation = try c.value(.servesPerRotation, or: d.servesPerRotation)
        notation = ScoreNotation(storedRaw: try c.decodeIfPresent(String.self, forKey: .notation))
        tiebreakEnabled = try c.value(.tiebreakEnabled, or: d.tiebreakEnabled)
        tiebreakPoints = try c.value(.tiebreakPoints, or: d.tiebreakPoints)
        matchTiebreak = try c.value(.matchTiebreak, or: d.matchTiebreak)
        matchTiebreakPoints = try c.value(.matchTiebreakPoints, or: d.matchTiebreakPoints)
        startScore = try c.value(.startScore, or: d.startScore)
        legsPerSet = try c.value(.legsPerSet, or: d.legsPerSet)
        doubleOut = try c.value(.doubleOut, or: d.doubleOut)
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(setsToWin, forKey: .setsToWin)
        try c.encode(pointsPerSet, forKey: .pointsPerSet)
        try c.encode(decidingSetPoints, forKey: .decidingSetPoints)
        try c.encode(winByTwo, forKey: .winByTwo)
        try c.encodeIfPresent(hardCap, forKey: .hardCap)
        try c.encode(serveTracking, forKey: .serveTracking)
        try c.encode(servesPerRotation, forKey: .servesPerRotation)
        try c.encode(notation.rawValue, forKey: .notation)
        try c.encode(tiebreakEnabled, forKey: .tiebreakEnabled)
        try c.encode(tiebreakPoints, forKey: .tiebreakPoints)
        try c.encode(matchTiebreak, forKey: .matchTiebreak)
        try c.encode(startScore, forKey: .startScore)
        try c.encode(legsPerSet, forKey: .legsPerSet)
        try c.encode(doubleOut, forKey: .doubleOut)
    }
}
