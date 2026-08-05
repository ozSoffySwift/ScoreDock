import SwiftUI

/// What the TV shows (§5.2, §6.1).
///
/// Reads `ActiveMatch.shared` rather than taking a store as a parameter, because the scene delegate
/// that creates it has no SwiftUI environment to inject through. It renders the board in whichever
/// mode the operator picked on the device.
struct ExternalBoardView: View {
    @State private var active = ActiveMatch.shared
    @State private var settings = AppSettings.shared

    var body: some View {
        Group {
            if let store = active.store {
                board(for: store)
            } else {
                // Connected with no match running. A blank TV looks broken; this looks deliberate.
                IdleExternalBoardView(theme: settings.theme)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
    }

    /// Every engine reaches the television, not just the team one.
    @ViewBuilder
    private func board(for store: AnyMatchStore) -> some View {
        switch store {
        case let .team(store): teamBoard(store)
        case let .setMatch(store): setMatchBoard(store)
        case let .list(store): listBoard(store)
        case let .specialised(store): specialisedBoard(store)
        }
    }

    private func teamBoard(_ store: LiveMatchStore) -> some View {
        // The external display never shows tenths at 10 Hz unless the mode is a clock — a full board
        // on a TV is read from across a hall, where a tenths digit is illegible anyway.
        TimelineView(.periodic(from: .now, by: teamTick(store))) { context in
            let derived = store.board(at: context.date)

            backdrop(store.theme) {
                switch active.boardMode {
                case .full:
                    ScoreboardView(
                        board: derived,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isInteractive: false
                    )
                case .shotClockOnly:
                    SingleValueBoardView(
                        value: derived.shotClock?.formatted ?? "—",
                        caption: String(localized: "SHOT CLOCK", comment: "External board caption"),
                        isAlert: derived.shotClock?.hasExpired == true,
                        theme: store.theme,
                        font: settings.boardFont
                    )
                case .timerOnly:
                    SingleValueBoardView(
                        value: derived.primaryClock.formatted,
                        caption: derived.isBreak
                            ? String(localized: "BREAK", comment: "External board caption")
                            : derived.periodLabel,
                        isAlert: derived.primaryClock.hasExpired,
                        theme: store.theme,
                        font: settings.boardFont
                    )
                }
            }
        }
    }

    private func setMatchBoard(_ store: SetMatchStore) -> some View {
        // No clock, so a one-second tick is enough to keep a resumed match honest.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            backdrop(store.theme) {
                SetMatchBoardView(
                    board: store.board(),
                    sides: store.sides.map(\.boardInfo),
                    theme: store.theme,
                    font: settings.boardFont,
                    isInteractive: false
                )
            }
        }
    }

    private func listBoard(_ store: ListStore) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            backdrop(store.theme) {
                ListBoardView(
                    board: store.board(),
                    sides: store.sides.map(\.boardInfo),
                    theme: store.theme,
                    font: settings.boardFont,
                    isInteractive: false
                )
            }
        }
    }

    private func specialisedBoard(_ store: SpecialisedStore) -> some View {
        TimelineView(.periodic(from: .now, by: specialisedTick(store))) { context in
            let derived = store.board(at: context.date)

            backdrop(store.theme) {
                switch (derived, active.boardMode) {
                case let (.chessClock(board), _):
                    ChessClockBoardView(
                        board: board,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isInteractive: false
                    )

                case let (.raceTimer(board), .timerOnly):
                    SingleValueBoardView(
                        value: board.raceClock.formatted,
                        caption: String(localized: "RACE", comment: "Race timer label"),
                        isAlert: false,
                        theme: store.theme,
                        font: settings.boardFont
                    )
                case let (.raceTimer(board), _):
                    RaceTimerBoardView(
                        board: board,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isInteractive: false
                    )

                case let (.americanFootball(board), .shotClockOnly):
                    SingleValueBoardView(
                        value: board.playClock.formatted,
                        caption: String(localized: "PLAY CLOCK", comment: "Football board label"),
                        isAlert: board.playClock.hasExpired,
                        theme: store.theme,
                        font: settings.boardFont
                    )
                case let (.americanFootball(board), .timerOnly):
                    SingleValueBoardView(
                        value: board.gameClock.formatted,
                        caption: board.quarterLabel,
                        isAlert: board.gameClock.hasExpired,
                        theme: store.theme,
                        font: settings.boardFont
                    )
                case let (.americanFootball(board), _):
                    FootballBoardView(
                        board: board,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isInteractive: false
                    )

                case let (.cricket(board), _):
                    CricketBoardView(
                        board: board,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isInteractive: false
                    )
                case let (.baseball(board), _):
                    BaseballBoardView(
                        board: board,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isInteractive: false
                    )
                case let (.unavailable(board), _):
                    UnavailableBoardView(board: board, theme: store.theme)
                }
            }
        }
    }

    private func backdrop(_ theme: ThemeSpec, @ViewBuilder content: () -> some View) -> some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            content()
        }
    }

    private func teamTick(_ store: LiveMatchStore) -> TimeInterval {
        let running = store.state.clock.isRunning
            || store.state.shotClock.isRunning
            || store.state.breakClock?.isRunning == true
        guard running else { return 1 }
        return store.rules.showTenths ? 0.1 : 1
    }

    private func specialisedTick(_ store: SpecialisedStore) -> TimeInterval {
        switch store.board() {
        case let .chessClock(board): board.isRunning ? 0.1 : 1
        case let .raceTimer(board): board.raceClock.isRunning ? 0.1 : 1
        case let .americanFootball(board):
            board.gameClock.isRunning || board.playClock.isRunning ? 0.1 : 1
        case .cricket, .baseball, .unavailable: 1
        }
    }
}

/// One number, as large as the screen allows — the iPad-above-the-basket case (§6.1).
struct SingleValueBoardView: View {
    var value: String
    var caption: String?
    var isAlert: Bool
    var theme: ThemeSpec
    var font: BoardFont

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.height * 0.62, geometry.size.width / CGFloat(max(2, value.count)) * 1.5)

            VStack(spacing: geometry.size.height * 0.04) {
                if let caption {
                    Text(caption)
                        // The app's text face — DSEG7 cannot render letters legibly (§9.2).
                        .font(.system(size: max(14, geometry.size.height * 0.07), weight: .heavy))
                        .tracking(geometry.size.height * 0.012)
                        .foregroundStyle(theme.labelColor)
                }
                LEDNumber(text: value, theme: theme, font: font, size: size)
                    .foregroundStyle(isAlert ? theme.accentColor : theme.digitColor)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(theme.backgroundColor)
        .environment(\.layoutDirection, .leftToRight)
    }
}

/// Shown when a display is attached but no match is running.
struct IdleExternalBoardView: View {
    var theme: ThemeSpec

    var body: some View {
        ZStack {
            theme.backgroundColor.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "sportscourt")
                    .font(.system(size: 64, weight: .light))
                Text("Ready", comment: "Idle external display")
                    .font(.system(size: 40, weight: .heavy))
                Text("Start a match on your device", comment: "Idle external display detail")
                    .font(.title3)
            }
            .foregroundStyle(theme.labelColor)
        }
    }
}

#Preview("Shot clock only") {
    SingleValueBoardView(
        value: "24",
        caption: "SHOT CLOCK",
        isAlert: false,
        theme: BuiltInThemes.theme(id: "black"),
        font: .sevenSegment
    )
}
