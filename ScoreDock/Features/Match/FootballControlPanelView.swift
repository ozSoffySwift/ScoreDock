import SwiftUI

/// The operator's screen for an American football board (§4.2, §6.3).
///
/// This board has the most to operate of the five, so the controls are grouped the way a play
/// unfolds: score the drive, set the next down, move the ball, run the clocks.
struct FootballControlPanelView: View {
    @Bindable var store: SpecialisedStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(VenueMonitor.self) private var venue
    @Environment(AppSettings.self) private var settings

    @State private var showingEndConfirmation = false
    @State private var showingCastingSheet = false
    @State private var externalDisplay = ExternalDisplay.shared

    /// The scoring plays, in the order an operator reaches for them.
    private static let scoringPlays: [(label: String, points: Int)] = [
        ("TD +6", 6), ("FG +3", 3), ("XP +1", 1), ("2PT +2", 2), ("SAF +2", 2),
    ]

    private var tickInterval: TimeInterval {
        guard case let .americanFootball(board) = store.board() else { return 1 }
        guard board.gameClock.isRunning || board.playClock.isRunning else { return 1 }
        return venue.isThermallyThrottled ? 1 : 0.1
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            VStack(spacing: 0) {
                if case let .americanFootball(board) = store.board(at: context.date) {
                    FootballBoardView(
                        board: board,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isCompact: true,
                        isInteractive: !board.isFinished,
                        onTap: { store.perform(.setPossession($0)) }
                    )
                    .frame(height: 190)
                    .clipShape(.rect(cornerRadius: 14))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    Divider().padding(.top, 8)

                    ScrollView {
                        controls(board)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                    }
                }
            }
            // A quarter that runs out stops itself, and the stop is logged like any other (§13.3).
            .onChange(of: gameClockExpired(context.date)) { _, expired in
                if expired { store.stopClockIfRunning() }
            }
        }
    }

    private func gameClockExpired(_ now: Date) -> Bool {
        guard case let .americanFootball(board) = store.board(at: now) else { return false }
        return board.gameClock.hasExpired && board.gameClock.isRunning
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ board: DerivedFootballBoard) -> some View {
        VStack(spacing: 14) {
            scoringSection(board)
            downSection(board)
            ballSection(board)
            clockSection(board)
            matchSection(board)
        }
        .sheet(isPresented: $showingCastingSheet) { CastingSheet() }
        .confirmationDialog(
            Text("End this game?", comment: "Confirmation title"),
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "End game", comment: "Confirmation"), role: .destructive) {
                store.finish()
                onFinish()
            }
            Button(String(localized: "Cancel", comment: "Confirmation"), role: .cancel) {}
        }
    }

    private func scoringSection(_ board: DerivedFootballBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Score", comment: "Control section"))

            ForEach(board.sides, id: \.slotIndex) { side in
                HStack(spacing: 6) {
                    Text(sideName(side.slotIndex))
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(width: 54, alignment: .leading)

                    ControlButtonGrid(items: Self.scoringPlays.map(\.label), columns: 5) { label in
                        Text(label)
                            .font(.caption2.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } action: { label in
                        guard let play = Self.scoringPlays.first(where: { $0.label == label }) else { return }
                        store.perform(.score(slot: side.slotIndex, points: play.points))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func downSection(_ board: DerivedFootballBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Down & distance", comment: "Control section"))

            HStack(spacing: 8) {
                Button {
                    // A first down is a fresh set, and the distance is ten yards or the goal line —
                    // whichever comes first, which is what makes it "and goal".
                    store.perform(.specialised(.setDownAndDistance(
                        down: 1,
                        yardsToGo: AmericanFootballEngine.firstDownDistance(from: ballOn, rules: footballRules)
                    )))
                } label: {
                    Text("1st down", comment: "Football control")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.perform(.specialised(.setDownAndDistance(down: down + 1, yardsToGo: yardsToGo)))
                } label: {
                    Text("Next down", comment: "Football control")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(down >= footballRules.downsToConvert)
            }

            Stepper(value: yardsToGoBinding, in: 0 ... 99) {
                LabeledContent(
                    String(localized: "To go", comment: "Football control"),
                    value: board.downAndDistance
                )
            }
        }
    }

    private func ballSection(_ board: DerivedFootballBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Ball", comment: "Control section"))

            Stepper(value: ballOnBinding, in: 0 ... footballRules.fieldLength) {
                LabeledContent(
                    String(localized: "Ball on", comment: "Football control"),
                    value: "\(board.ballOnNumber)"
                )
            }

            HStack(spacing: 8) {
                ForEach(board.sides, id: \.slotIndex) { side in
                    Button {
                        store.perform(.setPossession(side.slotIndex))
                    } label: {
                        Label(sideName(side.slotIndex), systemImage: "football.fill")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(side.hasPossession ? .accentColor : .secondary)
                }
            }
        }
    }

    private func clockSection(_ board: DerivedFootballBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Clocks", comment: "Control section"))

            HStack(spacing: 8) {
                Button { store.perform(.toggleClock) } label: {
                    Label(
                        board.gameClock.isRunning
                            ? String(localized: "Stop", comment: "Control")
                            : String(localized: "Start", comment: "Control"),
                        systemImage: board.gameClock.isRunning ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button { store.perform(.toggleShotClock) } label: {
                    Label(
                        String(localized: "Play clock", comment: "Control"),
                        systemImage: board.playClock.isRunning ? "pause" : "play"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                // Tap for 40, long-press for 25 — the same gesture pair as the shot clock (§4.2).
                Button { store.perform(.resetShotClock(full: true)) } label: {
                    Text("Reset 40", comment: "Football control").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { store.perform(.resetShotClock(full: false)) } label: {
                    Text("Reset 25", comment: "Football control").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button { store.perform(.previousPeriod) } label: {
                    Label(String(localized: "Back", comment: "Control"), systemImage: "chevron.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(board.quarter <= 1)

                Button { store.perform(.advancePeriod) } label: {
                    Label(String(localized: "Next quarter", comment: "Control"), systemImage: "chevron.right")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                ForEach(board.sides, id: \.slotIndex) { side in
                    Button {
                        store.perform(.timeout(slot: side.slotIndex, delta: 1))
                    } label: {
                        Text(
                            "\(sideName(side.slotIndex)) TO · \(side.timeoutsRemaining)",
                            comment: "Football timeout control"
                        )
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(side.timeoutsRemaining == 0)
                }
            }
        }
    }

    private func matchSection(_ board: DerivedFootballBoard) -> some View {
        VStack(spacing: 10) {
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
                Label(String(localized: "End game", comment: "Control"), systemImage: "flag.checkered")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: State access

    private var footballRules: AmericanFootballRules {
        store.rules.americanFootball ?? AmericanFootballRules()
    }

    private var down: Int { store.state.americanFootball?.down ?? 1 }
    private var yardsToGo: Int { store.state.americanFootball?.yardsToGo ?? 10 }
    private var ballOn: Int { store.state.americanFootball?.ballOn ?? 25 }

    private func sideName(_ slot: Int) -> String {
        store.sides.indices.contains(slot) ? store.sides[slot].shortName : ""
    }

    private var yardsToGoBinding: Binding<Int> {
        Binding(
            get: { yardsToGo },
            set: { store.perform(.specialised(.setDownAndDistance(down: down, yardsToGo: $0))) }
        )
    }

    private var ballOnBinding: Binding<Int> {
        Binding(
            get: { ballOn },
            set: { store.perform(.specialised(.setBallOn(yardLine: $0))) }
        )
    }
}
