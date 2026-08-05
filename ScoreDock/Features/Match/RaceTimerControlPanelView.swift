import SwiftUI

/// The operator's screen for a race timer (§4.2, §6.3).
///
/// The board carries the lap buttons — every row is one — so the rows beneath it hold only what a
/// row cannot express: the gun, corrections, and ending the race.
struct RaceTimerControlPanelView: View {
    @Bindable var store: SpecialisedStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(VenueMonitor.self) private var venue
    @Environment(AppSettings.self) private var settings

    @State private var showingEndConfirmation = false
    @State private var showingCastingSheet = false
    @State private var externalDisplay = ExternalDisplay.shared

    /// Lap times are read in tenths, so a running race ticks at 10 Hz — dropped to 1 Hz when the
    /// device is thermally throttled (§12).
    private var tickInterval: TimeInterval {
        guard case let .raceTimer(board) = store.board(), board.raceClock.isRunning else { return 1 }
        return venue.isThermallyThrottled ? 1 : 0.1
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            VStack(spacing: 0) {
                if case let .raceTimer(board) = store.board(at: context.date) {
                    RaceTimerBoardView(
                        board: board,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isInteractive: !board.isFinished,
                        onLap: { store.perform(.specialised(.recordLap(slot: $0))) },
                        onFinish: { store.perform(.specialised(.finishRacer(slot: $0))) }
                    )
                    .frame(maxHeight: .infinity)
                    .clipShape(.rect(cornerRadius: 14))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Divider().padding(.top, 8)

                    controls(board)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    @ViewBuilder
    private func controls(_ board: DerivedRaceTimerBoard) -> some View {
        VStack(spacing: 12) {
            Button {
                store.perform(.toggleClock)
            } label: {
                Label(
                    board.raceClock.isRunning
                        ? String(localized: "Stop", comment: "Race control")
                        : board.hasStarted
                            ? String(localized: "Resume", comment: "Race control")
                            : String(localized: "Start race", comment: "Race control"),
                    systemImage: board.raceClock.isRunning ? "stop.fill" : "flag.checkered"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(board.isFinished)

            Label(
                String(localized: "Tap a racer to record a lap. Long-press to finish them.", comment: "Race hint"),
                systemImage: "hand.tap"
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                Button { store.undo() } label: {
                    Label(String(localized: "Undo", comment: "Control"), systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!store.canUndo)

                Button { store.redo() } label: {
                    Label(String(localized: "Redo", comment: "Control"), systemImage: "arrow.uturn.forward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!store.canRedo)
            }

            HStack(spacing: 12) {
                Button { onRequestFullScreen() } label: {
                    Label(String(localized: "Full screen", comment: "Control"), systemImage: "arrow.up.left.and.arrow.down.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { showingCastingSheet = true } label: {
                    Label(
                        String(localized: "Display", comment: "Control"),
                        systemImage: externalDisplay.isConnected ? "tv.fill" : "tv"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            Button(role: .destructive) {
                showingEndConfirmation = true
            } label: {
                Label(String(localized: "End race", comment: "Control"), systemImage: "flag.checkered.2.crossed")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .sheet(isPresented: $showingCastingSheet) { CastingSheet() }
        .confirmationDialog(
            Text("End this race?", comment: "Confirmation title"),
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "End race", comment: "Confirmation"), role: .destructive) {
                store.finish()
                onFinish()
            }
            Button(String(localized: "Cancel", comment: "Confirmation"), role: .cancel) {}
        } message: {
            Text(
                "Racers still on the course keep the laps they have recorded, and are placed behind everyone who finished.",
                comment: "End race explanation"
            )
        }
    }
}
