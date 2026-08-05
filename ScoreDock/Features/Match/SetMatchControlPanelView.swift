import SwiftUI

/// The operator's screen for rally-scored games (§4.2, §6.2).
///
/// Same two-zone shape as the team panel — live board on top, controls beneath — but the controls
/// are different because the job is: rally scoring is one point at a time, and the interesting
/// state is who serves rather than what the clock says.
struct SetMatchControlPanelView: View {
    @Bindable var store: SetMatchStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(MatchFeedback.self) private var feedback
    @Environment(VenueMonitor.self) private var venue

    @State private var externalDisplay = ExternalDisplay.shared
    @State private var showingCastingSheet = false
    @State private var showingEndConfirmation = false
    @State private var dartsEntry = ""

    private var isDarts: Bool { store.rules.notation == .dartsCountdown }

    var body: some View {
        let board = store.board()

        VStack(spacing: 0) {
            SetMatchBoardView(
                board: board,
                sides: store.sides.map(\.boardInfo),
                theme: store.theme,
                font: .sevenSegment,
                isCompact: true,
                onTap: { awardPoint(to: $0) },
                onLongPress: { store.perform(.score(slot: $0, points: -1)) }
            )
            .frame(height: 210)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    if externalDisplay.isConnected { castingBadge }

                    if isDarts {
                        dartsControls(board)
                    } else {
                        pointButtons(board)
                    }

                    if store.rules.serveTracking { serveRow(board) }

                    HStack(spacing: 10) {
                        Button(action: onRequestFullScreen) {
                            Label(
                                String(localized: "Full screen", comment: "Control panel button"),
                                systemImage: "arrow.up.left.and.arrow.down.right"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button { store.undo() } label: {
                            Label(
                                String(localized: "Undo", comment: "Control panel button"),
                                systemImage: "arrow.uturn.backward"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.canUndo)
                    }
                    .controlSize(.large)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                    if !externalDisplay.isConnected {
                        Button { showingCastingSheet = true } label: {
                            Label(
                                String(localized: "Cast to TV", comment: "Control panel button"),
                                systemImage: "tv"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .sheet(isPresented: $showingCastingSheet) { CastingSheet() }
                    }

                    Button(role: .destructive) { showingEndConfirmation = true } label: {
                        Text("End match", comment: "Control panel button")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .confirmationDialog(
                        Text("End this match?", comment: "Confirmation title"),
                        isPresented: $showingEndConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(String(localized: "Finish match", comment: "Confirmation action")) {
                            store.finish()
                            onFinish()
                        }
                        Button(String(localized: "Abandon match", comment: "Confirmation action"), role: .destructive) {
                            store.abandon()
                            onFinish()
                        }
                        Button(String(localized: "Keep playing", comment: "Confirmation action"), role: .cancel) {}
                    } message: {
                        Text("The full play-by-play is already saved either way.", comment: "Confirmation message")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: Rally scoring

    private func pointButtons(_ board: DerivedSetMatchBoard) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(store.sides.enumerated()), id: \.offset) { slot, side in
                VStack(spacing: 6) {
                    Text(side.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: side.colorHex))
                        .lineLimit(1)

                    Button {
                        awardPoint(to: slot)
                    } label: {
                        Text("+1", comment: "Award a point")
                            .font(.title2.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: side.colorHex))

                    Button {
                        store.perform(.score(slot: slot, points: -1))
                    } label: {
                        Label(
                            String(localized: "Correct", comment: "Subtract a point"),
                            systemImage: "minus"
                        )
                        .font(.caption)
                        .frame(maxWidth: .infinity, minHeight: 32)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: Darts

    /// Darts is entered as a **visit total**, not per dart — which is how a scorer actually works,
    /// and why a bust reverts the whole visit rather than the last throw (§6.2).
    private func dartsControls(_ board: DerivedSetMatchBoard) -> some View {
        let thrower = board.sides.first { $0.isServing }?.slotIndex ?? 0
        let name = store.sides.indices.contains(thrower) ? store.sides[thrower].displayName : ""

        return VStack(spacing: 10) {
            HStack {
                Text("\(name) to throw", comment: "Darts turn indicator")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if let checkout = board.sides.first(where: { $0.slotIndex == thrower })?.checkout {
                    Text(checkout)
                        .font(.subheadline.weight(.bold).monospaced())
                        .foregroundStyle(.green)
                }
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                // The scores a scorer reaches for most often.
                ForEach([26, 41, 45, 60, 81, 85, 100, 140, 180], id: \.self) { value in
                    Button {
                        store.perform(.score(slot: thrower, points: value))
                    } label: {
                        Text("\(value)")
                            .font(.headline.monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    store.perform(.score(slot: thrower, points: 0))
                } label: {
                    Text("0")
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                TextField(
                    String(localized: "Visit score", comment: "Darts entry field"),
                    text: $dartsEntry
                )
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .font(.title3.monospacedDigit())

                Button {
                    submitDartsEntry(for: thrower)
                } label: {
                    Text("Enter", comment: "Darts submit")
                        .frame(minWidth: 80, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(Int(dartsEntry).map { $0 < 0 || $0 > 180 } ?? true)
            }
        }
    }

    private func submitDartsEntry(for slot: Int) {
        guard let value = Int(dartsEntry), (0 ... 180).contains(value) else { return }
        store.perform(.score(slot: slot, points: value))
        dartsEntry = ""
    }

    // MARK: Serve

    private func serveRow(_ board: DerivedSetMatchBoard) -> some View {
        HStack(spacing: 10) {
            ForEach(Array(store.sides.enumerated()), id: \.offset) { slot, side in
                Button {
                    store.perform(.setPossession(slot))
                } label: {
                    Label(
                        side.displayName,
                        systemImage: board.sides.first { $0.slotIndex == slot }?.isServing == true
                            ? "circle.fill"
                            : "circle"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .tint(Color(hex: side.colorHex))
            }
        }
        .accessibilityLabel(Text("Serving side", comment: "Accessibility"))
    }

    private var castingBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "tv.fill")
            Text("Casting to TV", comment: "Casting badge")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button {
                feedback.isQuickMuted.toggle()
                if feedback.isQuickMuted { MatchAudio.shared.stopAll() }
            } label: {
                Image(systemName: feedback.isQuickMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
        }
        .foregroundStyle(.green)
        .padding(12)
        .background(.green.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private func awardPoint(to slot: Int) {
        // Darts points come from the visit entry, not from tapping a side.
        guard !isDarts else { return }
        store.perform(.score(slot: slot, points: 1))
    }
}
