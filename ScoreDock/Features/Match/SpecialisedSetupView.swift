import SwiftUI

/// Picks the right setup screen for a bespoke board (§6.3).
///
/// Each board gets its own setup rather than one screen with five conditional sections: a chess
/// clock is configured by time control and a cricket match by overs and format, and those have
/// nothing to say to each other. Routing keeps each screen readable and lets one board's oddities
/// stay entirely inside it.
struct SpecialisedSetupView: View {
    let preset: GamePreset

    private var board: SpecialisedBoard? { preset.rules.specialisedRules?.board }

    var body: some View {
        switch board {
        case .chessClock:
            ChessClockSetupView(preset: preset)
        case .raceTimer:
            RaceTimerSetupView(preset: preset)
        case .americanFootball:
            FootballSetupView(preset: preset)
        case .cricket:
            CricketSetupView(preset: preset)
        case .baseball:
            BaseballSetupView(preset: preset)
        case nil:
            // Unreachable from the preset screen, which checks `implementedBoards` before offering
            // the link — but a deep link or a synced preset could land here.
            ContentUnavailableView {
                Label(
                    String(localized: "Not available yet", comment: "Unavailable board"),
                    systemImage: "clock.badge"
                )
            } description: {
                Text("This board is coming in a later update.", comment: "Unavailable board")
            }
        }
    }
}
