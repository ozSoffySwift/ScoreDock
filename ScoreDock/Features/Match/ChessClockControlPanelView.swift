import SwiftUI

/// The operator's screen for a chess clock (§4.2, §6.3).
///
/// Unusually for this app, the preview is not a preview — on a chess clock the two faces *are* the
/// controls, so the top zone is the live board at full size and the rows beneath hold only the
/// things a face cannot express: pause, undo, adding time, and ending the game.
struct ChessClockControlPanelView: View {
    @Bindable var store: SpecialisedStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(MatchFeedback.self) private var feedback
    @Environment(VenueMonitor.self) private var venue
    @Environment(AppSettings.self) private var settings

    @State private var showingEndConfirmation = false
    @State private var showingCastingSheet = false
    @State private var showingAddTime = false
    @State private var externalDisplay = ExternalDisplay.shared

    /// 10 Hz while a clock is running, because a blitz finish is decided in tenths — and 1 Hz when
    /// paused or thermally throttled (§12).
    private var tickInterval: TimeInterval {
        guard case let .chessClock(board) = store.board(), board.isRunning else { return 1 }
        return venue.isThermallyThrottled ? 1 : 0.1
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let derived = store.board(at: context.date)

            VStack(spacing: 0) {
                if case let .chessClock(board) = derived {
                    ChessClockBoardView(
                        board: board,
                        sides: store.sides.map(\.boardInfo),
                        theme: store.theme,
                        font: settings.boardFont,
                        isInteractive: !board.isFinished,
                        onPress: { store.perform(.specialised(.pressClock(slot: $0))) }
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
            // A flag ends the game on its own, with no tap to carry it — so something has to be
            // watching. This is that something (§6.3).
            .onChange(of: flaggedSlot(in: derived)) { _, flagged in
                if flagged != nil { store.checkForTimeExpiry(at: context.date) }
            }
        }
    }

    private func flaggedSlot(in board: DerivedSpecialisedBoard) -> Int? {
        guard case let .chessClock(clock) = board else { return nil }
        return clock.flaggedSlot
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ board: DerivedChessClockBoard) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    store.perform(.toggleClock)
                } label: {
                    Label(
                        board.isRunning
                            ? String(localized: "Pause", comment: "Chess clock control")
                            : board.hasStarted
                                ? String(localized: "Resume", comment: "Chess clock control")
                                : String(localized: "Start", comment: "Chess clock control"),
                        systemImage: board.isRunning ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(board.isFinished)

                Button {
                    showingAddTime = true
                } label: {
                    Label(String(localized: "Set time", comment: "Chess clock control"), systemImage: "clock.badge.exclamationmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(board.activeSlot == nil || board.isFinished)
            }

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

            if let flagged = board.flaggedSlot {
                resultBanner(flagged: flagged)
            }

            Button(role: .destructive) {
                showingEndConfirmation = true
            } label: {
                Label(String(localized: "End game", comment: "Control"), systemImage: "flag.checkered")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .sheet(isPresented: $showingCastingSheet) { CastingSheet() }
        .sheet(isPresented: $showingAddTime) {
            // Seeded from what is actually on the clock, so pressing Set without touching anything
            // is a no-op rather than a jump to some arbitrary default.
            ChessClockTimeSheet(store: store, currentRemaining: runningRemaining(board))
        }
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
        } message: {
            Text(
                "ScoreDock records the clock, not the result — a game that ends without a flag is saved with no winner.",
                comment: "Chess clock end explanation"
            )
        }
    }

    private func runningRemaining(_ board: DerivedChessClockBoard) -> TimeInterval {
        guard let active = board.activeSlot,
              let side = board.sides.first(where: { $0.slotIndex == active })
        else { return 0 }
        return side.remaining
    }

    private func resultBanner(flagged: Int) -> some View {
        let loser = store.sides.indices.contains(flagged) ? store.sides[flagged].displayName : ""
        let winnerSlot = store.sides.indices.first { $0 != flagged }
        let winner = winnerSlot.map { store.sides[$0].displayName } ?? ""

        return Label {
            Text("\(loser) ran out of time — \(winner) wins on time.", comment: "Chess clock result")
                .font(.footnote)
        } icon: {
            Image(systemName: "flag.fill")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.tertiary.opacity(0.25), in: .rect(cornerRadius: 10))
    }
}

/// Putting time back on the running clock — the arbiter's correction (§6.3).
private struct ChessClockTimeSheet: View {
    let store: SpecialisedStore

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int
    @State private var seconds: Int

    init(store: SpecialisedStore, currentRemaining: TimeInterval) {
        self.store = store
        let whole = Int(currentRemaining.rounded())
        _minutes = State(initialValue: whole / 60)
        _seconds = State(initialValue: whole % 60)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $minutes, in: 0 ... 180) {
                        LabeledContent(String(localized: "Minutes", comment: "Time field"), value: "\(minutes)")
                    }
                    Stepper(value: $seconds, in: 0 ... 59) {
                        LabeledContent(String(localized: "Seconds", comment: "Time field"), value: "\(seconds)")
                    }
                } footer: {
                    Text(
                        "Sets the time left on the clock that is currently running. Recorded in the game log like any other change.",
                        comment: "Set time footer"
                    )
                }
            }
            .navigationTitle(Text("Set time left", comment: "Sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Action")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Set", comment: "Action")) {
                        store.perform(.setClockElapsed(TimeInterval(minutes * 60 + seconds)))
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
