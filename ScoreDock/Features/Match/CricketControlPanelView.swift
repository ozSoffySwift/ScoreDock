import SwiftUI

/// The operator's screen for a cricket board (§4.2, §6.3).
///
/// Scoring a cricket match is one action repeated hundreds of times, so the runs row is the whole
/// design: **0 to 6 as a single strip of large buttons**, always in the same place, reachable
/// without looking. Extras and wickets sit underneath because they are rarer, not because they are
/// less important.
struct CricketControlPanelView: View {
    @Bindable var store: SpecialisedStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(AppSettings.self) private var settings

    @State private var showingEndConfirmation = false
    @State private var showingCastingSheet = false
    @State private var showingWicketSheet = false
    @State private var showingDeclareConfirmation = false
    @State private var externalDisplay = ExternalDisplay.shared

    /// The runs off one delivery. Five and seven happen, but never often enough to earn a button.
    private static let runOptions = [0, 1, 2, 3, 4, 6]

    var body: some View {
        VStack(spacing: 0) {
            if case let .cricket(board) = store.board() {
                CricketBoardView(
                    board: board,
                    sides: store.sides.map(\.boardInfo),
                    theme: store.theme,
                    font: settings.boardFont,
                    isCompact: true,
                    isInteractive: false
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
    }

    @ViewBuilder
    private func controls(_ board: DerivedCricketBoard) -> some View {
        VStack(spacing: 14) {
            runsSection
            extrasSection
            dismissalSection(board)
            matchSection
        }
        .sheet(isPresented: $showingCastingSheet) { CastingSheet() }
        .confirmationDialog(
            Text("How was the batter out?", comment: "Cricket dismissal title"),
            isPresented: $showingWicketSheet,
            titleVisibility: .visible
        ) {
            ForEach(WicketKind.allCases, id: \.self) { kind in
                Button(kind.shortLabel) {
                    store.perform(.specialised(.wicket(kind: kind)))
                }
            }
            Button(String(localized: "Cancel", comment: "Confirmation"), role: .cancel) {}
        }
        .confirmationDialog(
            Text("Close this innings?", comment: "Confirmation title"),
            isPresented: $showingDeclareConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Close innings", comment: "Confirmation")) {
                store.perform(.specialised(.endInnings))
            }
            Button(String(localized: "Cancel", comment: "Confirmation"), role: .cancel) {}
        } message: {
            Text("The remaining overs are not bowled.", comment: "Declaration explanation")
        }
        .confirmationDialog(
            Text("End this match?", comment: "Confirmation title"),
            isPresented: $showingEndConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "End match", comment: "Confirmation"), role: .destructive) {
                store.finish()
                onFinish()
            }
            Button(String(localized: "Cancel", comment: "Confirmation"), role: .cancel) {}
        }
    }

    private var runsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Runs off the ball", comment: "Control section"))

            ControlButtonGrid(items: Self.runOptions, columns: 6) { runs in
                Text("\(runs)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .minimumScaleFactor(0.6)
            } action: { runs in
                store.perform(.specialised(.delivery(runs: runs, extra: nil)))
            }
            .buttonStyle(.bordered)
        }
    }

    private var extrasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Extras", comment: "Control section"))

            ControlButtonGrid(items: CricketExtra.allCases, columns: 4) { extra in
                Text(extra.shortLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } action: { extra in
                store.perform(.specialised(.delivery(runs: 0, extra: extra)))
            }
            .buttonStyle(.bordered)

            Text(
                "A wide or no-ball adds a run and does not count towards the over. Enter the extra first, then any runs the batters took.",
                comment: "Extras hint"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func dismissalSection(_ board: DerivedCricketBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Innings", comment: "Control section"))

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    showingWicketSheet = true
                } label: {
                    Label(String(localized: "Wicket", comment: "Cricket control"), systemImage: "figure.cricket")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingDeclareConfirmation = true
                } label: {
                    Label(String(localized: "Close innings", comment: "Cricket control"), systemImage: "flag")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.bordered)
            }

            if let needed = board.runsNeeded, let balls = board.ballsRemaining, needed > 0 {
                Label(
                    String(localized: "\(needed) needed off \(balls) balls", comment: "Cricket chase"),
                    systemImage: "target"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var matchSection: some View {
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
                Label(String(localized: "End match", comment: "Control"), systemImage: "flag.checkered")
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
}
