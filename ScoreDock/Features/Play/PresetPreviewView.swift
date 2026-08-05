import SwiftUI

/// A preview of the board a preset will actually produce.
///
/// One shared specimen used to serve every preset, which meant a league table was advertised with a
/// team scoreboard — clock, two sides and all. The preview is the main thing the detail screen is
/// *for*, so it renders through the same views the live board uses, per engine.
struct PresetPreviewView: View {
    var preset: GamePreset
    var theme: ThemeSpec
    var font: BoardFont

    private static let sampleSides = [
        BoardSideInfo(displayName: "Home", shortName: "HOME", colorHex: "#42A5F5"),
        BoardSideInfo(displayName: "Guest", shortName: "GUES", colorHex: "#EF5350"),
        BoardSideInfo(displayName: "Third", shortName: "THRD", colorHex: "#66BB6A"),
        BoardSideInfo(displayName: "Fourth", shortName: "FRTH", colorHex: "#FFA726"),
    ]

    var body: some View {
        switch preset.rules {
        case let .team(rules):
            ScoreboardView(
                board: TeamEngine.derived(teamState(rules), rules: rules, at: .now),
                sides: Array(Self.sampleSides.prefix(2)),
                theme: theme,
                font: font,
                isCompact: true,
                isInteractive: false
            )

        case let .setMatch(rules):
            SetMatchBoardView(
                board: SetMatchEngine.derived(setMatchState(rules), rules: rules, at: .now),
                sides: Array(Self.sampleSides.prefix(2)),
                theme: theme,
                font: font,
                isCompact: true,
                isInteractive: false
            )

        case let .list(rules):
            ListBoardView(
                board: ListEngine.derived(listState(rules), rules: rules, at: .now),
                sides: listSides(rules),
                theme: theme,
                font: font,
                isCompact: true,
                isInteractive: false
            )

        case let .specialised(rules):
            specialisedPreview(rules)
        }
    }

    /// M6 lands the bespoke boards one at a time (§18), so this shows the real board where one
    /// exists and a generic specimen where it does not — which at least shows the theme and font
    /// honestly, without claiming to be a cricket board.
    @ViewBuilder
    private func specialisedPreview(_ rules: SpecialisedRules) -> some View {
        switch rules.board {
        case .chessClock:
            let clockRules = rules.chessClock ?? ChessClockRules()
            ChessClockBoardView(
                board: ChessClockEngine.derived(
                    ChessClockEngine.initialState(rules: clockRules, sideCount: 2),
                    rules: clockRules,
                    isFinished: false,
                    at: .now
                ),
                sides: [
                    BoardSideInfo(displayName: String(localized: "White", comment: "Chess side"), colorHex: "#ECEFF1"),
                    BoardSideInfo(displayName: String(localized: "Black", comment: "Chess side"), colorHex: "#78909C"),
                ],
                theme: theme,
                font: font,
                isCompact: true,
                isInteractive: false
            )
        case .raceTimer:
            let raceRules = rules.raceTimer ?? RaceTimerRules()
            RaceTimerBoardView(
                board: RaceTimerEngine.derived(
                    RaceTimerEngine.initialState(rules: raceRules, sideCount: raceRules.racerCount),
                    rules: raceRules,
                    isFinished: false,
                    at: .now
                ),
                sides: (0 ..< max(2, raceRules.racerCount)).map { index in
                    BoardSideInfo(
                        displayName: String(localized: "Racer \(index + 1)", comment: "Default racer name"),
                        colorHex: Self.racePalette[index % Self.racePalette.count]
                    )
                },
                theme: theme,
                font: font,
                isCompact: true,
                isInteractive: false
            )
        case .americanFootball:
            let footballRules = rules.americanFootball ?? AmericanFootballRules()
            FootballBoardView(
                board: AmericanFootballEngine.derived(
                    footballState(footballRules), rules: footballRules, isFinished: false, at: .now
                ),
                sides: [
                    BoardSideInfo(displayName: "Home", shortName: "HOME", colorHex: "#42A5F5"),
                    BoardSideInfo(displayName: "Guest", shortName: "GUES", colorHex: "#EF5350"),
                ],
                theme: theme,
                font: font,
                isCompact: true,
                isInteractive: false
            )
        case .cricket:
            let cricketRules = rules.cricket ?? CricketRules()
            CricketBoardView(
                board: CricketEngine.derived(
                    cricketState(cricketRules), rules: cricketRules,
                    sideCount: 2, isFinished: false, at: .now
                ),
                sides: Array(Self.sampleSides.prefix(2)),
                theme: theme,
                font: font,
                isCompact: true,
                isInteractive: false
            )
        case .baseball:
            let baseballRules = rules.baseball ?? BaseballRules()
            BaseballBoardView(
                board: BaseballEngine.derived(
                    baseballState(baseballRules), rules: baseballRules, isFinished: false, at: .now
                ),
                sides: Array(Self.sampleSides.prefix(2)),
                theme: theme,
                font: font,
                isCompact: true,
                isInteractive: false
            )
        }
    }

    private static let racePalette = ["#42A5F5", "#EF5350", "#66BB6A", "#FFA726"]

    private func baseballState(_ rules: BaseballRules) -> BaseballState {
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        state.sides[1].runsByInning = [0, 2, 0, 0, 1]
        state.sides[0].runsByInning = [1, 0, 0, 3]
        state.sides[1].hits = 7
        state.sides[0].hits = 9
        state.sides[0].errors = 1
        state.inning = 5
        state.isTop = false
        state.balls = 2
        state.strikes = 1
        state.outs = 1
        state.bases = BaseOccupancy(first: true, second: false, third: true)
        return state
    }

    private func cricketState(_ rules: CricketRules) -> CricketState {
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)
        state.innings[0].runs = 84
        state.innings[0].wickets = 2
        state.innings[0].legalBalls = 58
        state.innings[0].extras = 6
        state.innings[0].partnership = 31
        return state
    }

    private func footballState(_ rules: AmericanFootballRules) -> AmericanFootballState {
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)
        state.sides[0].score = 21
        state.sides[1].score = 17
        state.possessionSlot = 0
        state.down = 3
        state.yardsToGo = 7
        state.ballOn = 62
        return state
    }

    // MARK: Representative states

    private func teamState(_ rules: TeamRules) -> TeamState {
        var state = TeamEngine.initialState(rules: rules, sideCount: 2)
        let scoresBig = rules.scoreIncrements.contains(3)
        state.sides[0].score = scoresBig ? 68 : 2
        if state.sides.count > 1 { state.sides[1].score = scoresBig ? 64 : 1 }
        state.sides[0].fouls = 3
        state.period = min(2, rules.periodCount)
        if rules.possessionArrowEnabled { state.possessionSlot = 0 }
        return state
    }

    private func setMatchState(_ rules: SetMatchRules) -> SetMatchState {
        var state = SetMatchEngine.initialState(rules: rules, sideCount: 2)
        state.sides[0].setsWon = 1
        switch rules.notation {
        case .tennis:
            state.sides[0].gamesWon = 4
            state.sides[1].gamesWon = 3
            state.sides[0].points = 3
            state.sides[1].points = 2
        case .dartsCountdown:
            state.sides[0].remaining = 170
            state.sides[1].remaining = 301
            state.sides[0].legsWon = 1
        case .numeric:
            state.sides[0].points = min(18, rules.pointsPerSet)
            state.sides[1].points = max(0, min(15, rules.pointsPerSet - 3))
        }
        state.completedSets = [[rules.pointsPerSet, max(0, rules.pointsPerSet - 4)]]
        return state
    }

    /// A bracket preview needs every place filled, or half of it reads as broken. The other styles
    /// look right with a handful of rows.
    private func listSides(_ rules: ListRules) -> [BoardSideInfo] {
        let count = listParticipantCount(rules)
        guard count > Self.sampleSides.count else { return Array(Self.sampleSides.prefix(count)) }
        return (0 ..< count).map { index in
            Self.sampleSides.indices.contains(index)
                ? Self.sampleSides[index]
                : BoardSideInfo(
                    displayName: String(localized: "Seed \(index + 1)", comment: "Bracket preview name"),
                    shortName: "S\(index + 1)",
                    colorHex: "#78909C"
                )
        }
    }

    private func listParticipantCount(_ rules: ListRules) -> Int {
        rules.style == .bracket ? max(2, rules.bracketSize) : 4
    }

    private func listState(_ rules: ListRules) -> ListState {
        var state = ListEngine.initialState(rules: rules, sideCount: listParticipantCount(rules))
        for index in state.entries.indices {
            switch rules.style {
            case .leaderboard:
                state.entries[index].total = max(0, 40 - index * 7)
            case .standings:
                state.entries[index].won = max(0, 5 - index)
                state.entries[index].drawn = index % 2
                state.entries[index].lost = index
                state.entries[index].goalsFor = max(0, 14 - index * 3)
                state.entries[index].goalsAgainst = index * 3
            case .scoreSheet:
                state.entries[index].rounds = (0 ..< max(1, rules.roundCount)).map { round in
                    round <= 1 ? max(0, 12 - index * 3 - round) : 0
                }
                state.entries[index].total = state.entries[index].rounds.reduce(0, +)
            case .bracket:
                break
            }
        }
        if rules.style == .bracket, var bracket = state.bracket, !bracket.winners.isEmpty {
            bracket.winners[0] = 0
            state.bracket = bracket
        }
        return state
    }
}
