import Foundation

/// A human-readable summary of a rule set.
///
/// Used by the preset detail sheet now and by Setup in M1, so the two never drift into describing
/// the same rules differently.
struct RuleSummary {
    struct Row: Identifiable, Hashable {
        var id: String { key }
        /// Matches the key used in the catalog's `sources` map, so a citation can be attached.
        var key: String
        var label: String
        var value: String

        /// The value wrapped in a Unicode first-strong isolate.
        ///
        /// §10.2 warns that bidi auto-detection produces wrong results on short mixed strings, and
        /// it does: `"מחזורים: 4 × 10 min"` renders with the numeric run reversed, because the
        /// runtime resolves direction across the whole line rather than per run. FSI…PDI scopes
        /// direction resolution to this value alone, so `4 × 10 min` stays in that order beside a
        /// Hebrew label.
        ///
        /// Only needed where a value is *composed into* a larger mixed string. `LabeledContent`
        /// renders label and value as separate runs and needs no isolate.
        var isolatedValue: String { "\u{2068}\(value)\u{2069}" }
    }

    static func rows(for rules: AnyRuleSet) -> [Row] {
        switch rules {
        case let .team(r): teamRows(r)
        case let .setMatch(r): setMatchRows(r)
        case let .list(r): listRows(r)
        case let .specialised(r): specialisedRows(r)
        }
    }

    // MARK: Team

    private static func teamRows(_ r: TeamRules) -> [Row] {
        var rows: [Row] = []

        if r.periodLength > 0 {
            rows.append(Row(
                key: "periodCount",
                label: String(localized: "Periods", comment: "Rule summary label"),
                value: "\(r.periodCount) × \(duration(r.periodLength))"
            ))
        } else if r.periodCount > 1 {
            rows.append(Row(
                key: "periodCount",
                label: String(localized: "Periods", comment: "Rule summary label"),
                value: "\(r.periodCount)"
            ))
        }

        rows.append(Row(
            key: "countsUp",
            label: String(localized: "Clock", comment: "Rule summary label"),
            value: r.countsUp
                ? String(localized: "Counts up", comment: "Clock direction")
                : String(localized: "Counts down", comment: "Clock direction")
        ))

        if r.foulTrackingEnabled {
            rows.append(Row(
                key: "foulLimit",
                label: String(localized: "Foul limit", comment: "Rule summary label"),
                value: "\(r.foulLimit)"
            ))
            if let bonus = r.bonusThreshold {
                rows.append(Row(
                    key: "bonusThreshold",
                    label: String(localized: "Bonus at", comment: "Rule summary label"),
                    value: String(localized: "\(bonus) team fouls", comment: "Bonus threshold value")
                ))
            }
        }

        if r.timeoutCount > 0 {
            rows.append(Row(
                key: "timeoutCount",
                label: String(localized: "Timeouts", comment: "Rule summary label"),
                value: r.timeoutsResetAtHalf
                    ? String(localized: "\(r.timeoutCount), reset at half", comment: "Timeout allowance")
                    : "\(r.timeoutCount)"
            ))
        }

        if r.shotClockEnabled {
            rows.append(Row(
                key: "shotClockFull",
                label: String(localized: "Shot clock", comment: "Rule summary label"),
                value: r.shotClockFull == r.shotClockShort
                    ? "\(Int(r.shotClockFull))s"
                    : "\(Int(r.shotClockFull))s / \(Int(r.shotClockShort))s"
            ))
        }

        if r.possessionArrowEnabled {
            rows.append(Row(
                key: "possessionArrowEnabled",
                label: String(localized: "Possession", comment: "Rule summary label"),
                value: String(localized: "Alternating arrow", comment: "Possession rule")
            ))
        }

        if r.scoreIncrements.count > 1 {
            rows.append(Row(
                key: "scoreIncrements",
                label: String(localized: "Score buttons", comment: "Rule summary label"),
                value: r.scoreIncrements.map { "+\($0)" }.joined(separator: " · ")
            ))
        }

        if r.breakDuration > 0 {
            rows.append(Row(
                key: "breakDuration",
                label: String(localized: "Break", comment: "Rule summary label"),
                value: duration(r.breakDuration)
            ))
        }

        return rows
    }

    // MARK: Set-match

    private static func setMatchRows(_ r: SetMatchRules) -> [Row] {
        var rows: [Row] = []

        if r.notation == .dartsCountdown {
            rows.append(Row(
                key: "startScore",
                label: String(localized: "Start score", comment: "Rule summary label"),
                value: "\(r.startScore)"
            ))
            rows.append(Row(
                key: "legsPerSet",
                label: String(localized: "Legs per set", comment: "Rule summary label"),
                value: "\(r.legsPerSet)"
            ))
            rows.append(Row(
                key: "doubleOut",
                label: String(localized: "Finish", comment: "Rule summary label"),
                value: r.doubleOut
                    ? String(localized: "Double out", comment: "Darts finish rule")
                    : String(localized: "Straight out", comment: "Darts finish rule")
            ))
            return rows
        }

        rows.append(Row(
            key: "setsToWin",
            label: String(localized: "Sets to win", comment: "Rule summary label"),
            value: "\(r.setsToWin)"
        ))

        if r.notation == .tennis {
            rows.append(Row(
                key: "notation",
                label: String(localized: "Scoring", comment: "Rule summary label"),
                value: String(localized: "15 · 30 · 40 · Ad", comment: "Tennis notation")
            ))
        } else {
            rows.append(Row(
                key: "pointsPerSet",
                label: String(localized: "Points per set", comment: "Rule summary label"),
                value: "\(r.pointsPerSet)"
            ))
            if r.decidingSetPoints != r.pointsPerSet {
                rows.append(Row(
                    key: "decidingSetPoints",
                    label: String(localized: "Deciding set", comment: "Rule summary label"),
                    value: "\(r.decidingSetPoints)"
                ))
            }
        }

        if r.winByTwo {
            rows.append(Row(
                key: "winByTwo",
                label: String(localized: "Margin", comment: "Rule summary label"),
                value: String(localized: "Win by two", comment: "Win margin rule")
            ))
        }
        if let cap = r.hardCap {
            rows.append(Row(
                key: "hardCap",
                label: String(localized: "Hard cap", comment: "Rule summary label"),
                value: "\(cap)"
            ))
        }
        if r.tiebreakEnabled {
            rows.append(Row(
                key: "tiebreakPoints",
                label: String(localized: "Tiebreak", comment: "Rule summary label"),
                value: String(localized: "to \(r.tiebreakPoints)", comment: "Tiebreak target")
            ))
        }
        if r.serveTracking, r.servesPerRotation > 1 {
            rows.append(Row(
                key: "servesPerRotation",
                label: String(localized: "Serve changes", comment: "Rule summary label"),
                value: String(localized: "every \(r.servesPerRotation) points", comment: "Serve rotation")
            ))
        }
        return rows
    }

    // MARK: List

    private static func listRows(_ r: ListRules) -> [Row] {
        var rows: [Row] = [
            Row(
                key: "style",
                label: String(localized: "Format", comment: "Rule summary label"),
                value: r.style.summaryLabel
            )
        ]
        switch r.style {
        case .standings:
            rows.append(Row(
                key: "pointsForWin",
                label: String(localized: "Points", comment: "Rule summary label"),
                value: String(
                    localized: "\(r.pointsForWin) win · \(r.pointsForDraw) draw · \(r.pointsForLoss) loss",
                    comment: "Standings points allocation"
                )
            ))
            rows.append(Row(
                key: "columns",
                label: String(localized: "Columns", comment: "Rule summary label"),
                value: r.columns.map(\.shortLabel).joined(separator: " ")
            ))
        case .bracket:
            rows.append(Row(
                key: "bracketSize",
                label: String(localized: "Seeds", comment: "Rule summary label"),
                value: "\(r.bracketSize)"
            ))
        case .scoreSheet:
            rows.append(Row(
                key: "roundCount",
                label: String(localized: "Rounds", comment: "Rule summary label"),
                value: "\(r.roundCount)"
            ))
            rows.append(Row(
                key: "participantCount",
                label: String(localized: "Players", comment: "Rule summary label"),
                value: "\(r.participantCount)"
            ))
        case .leaderboard:
            rows.append(Row(
                key: "higherIsBetter",
                label: String(localized: "Ranking", comment: "Rule summary label"),
                value: r.higherIsBetter
                    ? String(localized: "Highest first", comment: "Ranking direction")
                    : String(localized: "Lowest first", comment: "Ranking direction")
            ))
        }
        return rows
    }

    // MARK: Specialised

    private static func specialisedRows(_ r: SpecialisedRules) -> [Row] {
        switch r.board {
        case .americanFootball:
            let f = r.americanFootball ?? AmericanFootballRules()
            return [
                Row(key: "quarterLength", label: String(localized: "Quarters", comment: "Rule summary label"),
                    value: "\(f.quarterCount) × \(duration(f.quarterLength))"),
                Row(key: "playClockNormal", label: String(localized: "Play clock", comment: "Rule summary label"),
                    value: "\(Int(f.playClockNormal))s / \(Int(f.playClockShort))s"),
                Row(key: "timeoutsPerHalf", label: String(localized: "Timeouts per half", comment: "Rule summary label"),
                    value: "\(f.timeoutsPerHalf)"),
            ]
        case .cricket:
            let c = r.cricket ?? CricketRules()
            return [
                Row(key: "format", label: String(localized: "Format", comment: "Rule summary label"),
                    value: c.format.summaryLabel),
                Row(key: "oversPerInnings", label: String(localized: "Overs", comment: "Rule summary label"),
                    value: "\(c.oversPerInnings)"),
                Row(key: "wicketsPerInnings", label: String(localized: "Wickets", comment: "Rule summary label"),
                    value: "\(c.wicketsPerInnings)"),
            ]
        case .baseball:
            let b = r.baseball ?? BaseballRules()
            return [
                Row(key: "inningCount", label: String(localized: "Innings", comment: "Rule summary label"),
                    value: "\(b.inningCount)"),
                Row(key: "outsPerHalfInning", label: String(localized: "Outs", comment: "Rule summary label"),
                    value: "\(b.outsPerHalfInning)"),
            ]
        case .chessClock:
            let c = r.chessClock ?? ChessClockRules()
            return [
                Row(key: "baseTime", label: String(localized: "Base time", comment: "Rule summary label"),
                    value: duration(c.baseTime)),
                Row(key: "incrementMode", label: String(localized: "Increment", comment: "Rule summary label"),
                    value: c.incrementMode == .none
                        ? String(localized: "None", comment: "No clock increment")
                        : "\(c.incrementMode.summaryLabel) +\(Int(c.incrementSeconds))s"),
            ]
        case .raceTimer:
            let t = r.raceTimer ?? RaceTimerRules()
            return [
                Row(key: "racerCount", label: String(localized: "Racers", comment: "Rule summary label"),
                    value: "\(t.racerCount)"),
                Row(key: "recordSplits", label: String(localized: "Splits", comment: "Rule summary label"),
                    value: t.recordSplits
                        ? String(localized: "Recorded", comment: "Splits recorded")
                        : String(localized: "Off", comment: "Splits off")),
            ]
        }
    }

    /// Formats seconds as `M:SS` under a minute-boundary, or whole minutes where it divides evenly.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total % 60 == 0 {
            return String(localized: "\(total / 60) min", comment: "Whole-minute duration")
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Presentation labels

extension ListStyle {
    var summaryLabel: String {
        switch self {
        case .leaderboard: String(localized: "Leaderboard", comment: "List format")
        case .standings: String(localized: "Standings", comment: "List format")
        case .bracket: String(localized: "Bracket", comment: "List format")
        case .scoreSheet: String(localized: "Score sheet", comment: "List format")
        }
    }
}

extension CricketRules.Format {
    var summaryLabel: String {
        switch self {
        case .t20: "T20"
        case .odi: "ODI"
        case .test: String(localized: "Test", comment: "Cricket format")
        }
    }
}

extension ChessClockRules.Increment {
    var summaryLabel: String {
        switch self {
        case .fischer: "Fischer"
        case .bronstein: "Bronstein"
        case .none: String(localized: "None", comment: "No clock increment")
        }
    }
}

extension PresetCategory {
    var sectionTitle: String {
        switch self {
        case .team: String(localized: "Team scoreboards", comment: "Picker section")
        case .setMatch: String(localized: "Sets & matches", comment: "Picker section")
        case .specialised: String(localized: "Specialised", comment: "Picker section")
        case .list: String(localized: "Lists & tables", comment: "Picker section")
        }
    }

    var symbolName: String {
        switch self {
        case .team: "sportscourt"
        case .setMatch: "figure.tennis"
        case .specialised: "star.circle"
        case .list: "list.number"
        }
    }
}
