import SwiftUI

/// The operator's screen, portrait (§4.2).
///
/// Two zones: a live interactive preview of the real board on top, and control rows beneath for
/// everything the preview cannot express.
///
/// > **Design intent (§4.2):** most of a match runs from the preview alone, so the operator's eyes
/// > stay on the game rather than on the phone. This is the single most important UX property of
/// > the app — every change here should be measured against it.
struct ControlPanelView: View {
    @Bindable var store: LiveMatchStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(MatchFeedback.self) private var feedback
    @Environment(VenueMonitor.self) private var venue

    @State private var showingPeriodLabel = false
    @State private var showingEndConfirmation = false
    @State private var showingCastingSheet = false
    @State private var externalDisplay = ExternalDisplay.shared
    @State private var active = ActiveMatch.shared
    @State private var pendingScore: PendingScore?

    /// 10 Hz while running when the rules can show tenths, 1 Hz otherwise (§6.4).
    ///
    /// Driven by the *rules* rather than by the current remaining time: a schedule is captured when
    /// `TimelineView` is created, and crossing the tenths threshold changes no state, so a
    /// remaining-time-derived interval would simply never update.
    ///
    /// Thermal state overrides it entirely — at `.serious` the board drops to 1 Hz, which also drops
    /// tenths, giving the throttled CPU budget back to keeping the display correct (§12).
    private var tickInterval: TimeInterval {
        guard store.state.clock.isRunning || store.state.breakClock?.isRunning == true else { return 1 }
        guard !venue.isThermallyThrottled else { return 1 }
        return store.rules.showTenths ? 0.1 : 1
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let board = store.board(at: context.date)

            VStack(spacing: 0) {
                preview(board)
                Divider()
                ScrollView {
                    controls(board)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }
            }
            // A countdown that reaches zero stops itself, and the stop is logged like any other
            // (§13.3). Driven from onChange so nothing mutates during a render pass.
            .onChange(of: board.primaryClock.hasExpired) { _, isExpired in
                if isExpired { store.stopIfExpired() }
            }
            .sheet(item: $pendingScore) { pending in
                AttributionSheet(
                    sideName: store.sides.indices.contains(pending.slotIndex)
                        ? store.sides[pending.slotIndex].displayName
                        : "",
                    colorHex: store.sides.indices.contains(pending.slotIndex)
                        ? store.sides[pending.slotIndex].colorHex
                        : "#1E88E5",
                    points: pending.points,
                    roster: roster(for: pending.slotIndex)
                ) { playerID in
                    store.perform(.score(slot: pending.slotIndex, points: pending.points, playerID: playerID))
                }
            }
        }
    }

    // MARK: Scoring

    /// Routes a score through attribution when it is switched on, and straight through otherwise.
    ///
    /// With attribution off — the default — this is one tap and nothing else, which is what a
    /// referee running a clock needs (§4.2). Corrections never prompt: subtracting a point is
    /// already a correction, and asking who to un-credit mid-play would be absurd.
    private func score(slot: Int, points: Int) {
        guard points > 0,
              store.match.attributionEnabled,
              !roster(for: slot).isEmpty
        else {
            store.perform(.score(slot: slot, points: points))
            return
        }
        pendingScore = PendingScore(slotIndex: slot, points: points)
    }

    private func roster(for slot: Int) -> [Player] {
        guard store.sides.indices.contains(slot) else { return [] }
        let side = store.sides[slot]
        if let team = side.linkedTeam { return team.activePlayers }
        if let player = side.linkedPlayer { return [player] }
        return []
    }

    // MARK: Preview

    private func preview(_ board: DerivedBoard) -> some View {
        ScoreboardView(
            board: board,
            sides: store.sides.map(\.boardInfo),
            theme: store.theme,
            font: .sevenSegment,
            isCompact: true,
            onTap: { handleTap($0) },
            onLongPress: { handleLongPress($0) }
        )
        .frame(height: 190)
    }

    // MARK: Controls

    @ViewBuilder
    private func controls(_ board: DerivedBoard) -> some View {
        VStack(spacing: 14) {
            venueBanners()
            castingRow()

            scoreButtons()

            if store.rules.foulTrackingEnabled || store.rules.timeoutCount > 0 {
                infractionButtons()
            }

            clockRow(board)

            HStack(spacing: 10) {
                // §5.1 mandatory mitigation: a large share of users keep Portrait Orientation Lock
                // on permanently, which defeats rotate-to-board entirely. Rotation is the delight;
                // this button is the guarantee.
                Button(action: onRequestFullScreen) {
                    Label(
                        String(localized: "Full screen", comment: "Control panel button"),
                        systemImage: "arrow.up.left.and.arrow.down.right"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.undo()
                } label: {
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

            Button(role: .destructive) {
                showingEndConfirmation = true
            } label: {
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
                Text(
                    "The full play-by-play is already saved either way.",
                    comment: "Confirmation message"
                )
            }
        }
    }

    // MARK: Casting

    /// Cast entry point, and — once connected — the board mode picker (§5.4, §6.1).
    @ViewBuilder
    private func castingRow() -> some View {
        if externalDisplay.isConnected {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "tv.fill")
                    Text("Casting to TV", comment: "Casting badge")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    // Quick-mute lives with the match, not in Settings, so silencing one game does
                    // not change the operator's preferences (§11.1).
                    Button {
                        feedback.isQuickMuted.toggle()
                        if feedback.isQuickMuted { MatchAudio.shared.stopAll() }
                        feedback.rearm(for: store)
                    } label: {
                        Image(systemName: feedback.isQuickMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                    .accessibilityLabel(
                        feedback.isQuickMuted
                            ? Text("Unmute sounds", comment: "Accessibility")
                            : Text("Mute sounds", comment: "Accessibility")
                    )
                }
                .foregroundStyle(.green)

                BoardModePicker()
            }
            .padding(12)
            .background(.green.opacity(0.12), in: .rect(cornerRadius: 12))
        } else {
            Button {
                showingCastingSheet = true
            } label: {
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
    }

    // MARK: Venue guards (§12)

    @ViewBuilder
    private func venueBanners() -> some View {
        if venue.showsLowBatteryWarning {
            banner(
                systemImage: "battery.25",
                tint: .orange,
                title: venue.batteryPercent.map {
                    String(localized: "Battery at \($0)%", comment: "Low battery title")
                } ?? String(localized: "Battery low", comment: "Low battery title"),
                detail: String(
                    localized: "Screen-on scoring with a TV attached drains fast. Plug in before the second half.",
                    comment: "Low battery detail"
                )
            )
        }

        if let explanation = venue.thermalState.operatorExplanation {
            banner(
                systemImage: "thermometer.high",
                tint: .red,
                title: String(localized: "Device is hot", comment: "Thermal title"),
                detail: explanation
            )
        }
    }

    private func banner(systemImage: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    /// Multi-point buttons — +2/+3 for basketball, +1/+6 for American football (§4.2).
    private func scoreButtons() -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(store.sides.enumerated()), id: \.offset) { slot, side in
                VStack(spacing: 6) {
                    Text(side.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color(hex: side.colorHex))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        ForEach(store.rules.scoreIncrements, id: \.self) { points in
                            Button {
                                score(slot: slot, points: points)
                            } label: {
                                Text("+\(points)")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: side.colorHex))
                        }
                    }

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

    private func infractionButtons() -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(Array(store.sides.enumerated()), id: \.offset) { slot, _ in
                HStack(spacing: 6) {
                    if store.rules.foulTrackingEnabled {
                        Button {
                            store.perform(.foul(slot: slot, delta: 1))
                        } label: {
                            Text("Foul", comment: "Add a foul")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                    }
                    if store.rules.timeoutCount > 0 {
                        Button {
                            store.perform(.timeout(slot: slot, delta: 1))
                        } label: {
                            Text("Timeout", comment: "Use a timeout")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, minHeight: 40)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
    }

    private func clockRow(_ board: DerivedBoard) -> some View {
        HStack(spacing: 10) {
            Button {
                store.perform(.toggleClock)
            } label: {
                Label(
                    board.primaryClock.isRunning
                        ? String(localized: "Stop", comment: "Clock button")
                        : String(localized: "Start", comment: "Clock button"),
                    systemImage: board.primaryClock.isRunning ? "pause.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(board.primaryClock.isRunning ? .orange : .green)

            // The break timer replaces the main clock, then hands it back at the paused value (§6.1).
            Button {
                if board.isBreak {
                    store.perform(.endBreak)
                } else {
                    store.perform(.startBreak(store.rules.breakDuration))
                }
            } label: {
                Label(
                    board.isBreak
                        ? String(localized: "End break", comment: "Break button")
                        : String(localized: "Break", comment: "Break button"),
                    systemImage: "cup.and.saucer"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(store.rules.breakDuration <= 0)

            Button {
                showingPeriodLabel = true
            } label: {
                Label(board.periodLabel, systemImage: "textformat")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .confirmationDialog(
                Text("Period label", comment: "Override dialog title"),
                isPresented: $showingPeriodLabel,
                titleVisibility: .visible
            ) {
                // OT / SO / HT / F, for when regulation labels do not fit (§4.2).
                ForEach(["OT", "SO", "HT", "F"], id: \.self) { label in
                    Button(label) { store.perform(.setPeriodLabel(label)) }
                }
                Button(String(localized: "Use default", comment: "Clear label override")) {
                    store.perform(.setPeriodLabel(nil))
                }
                Button(String(localized: "Cancel", comment: "Dialog cancel"), role: .cancel) {}
            }
        }
        .controlSize(.large)
        // Three buttons on one row is tight, and it gets tighter in German or Hebrew. Scale the
        // labels rather than letting "Break" wrap onto two lines.
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    // MARK: Board element interaction (§4.2 table)

    private func handleTap(_ element: BoardElement) {
        switch element {
        case let .score(slot): score(slot: slot, points: 1)
        case .clock: store.perform(.toggleClock)
        case .period: store.perform(.advancePeriod)
        case .possession: flipPossession()
        case .shotClock: store.perform(.resetShotClock(full: true))
        case let .fouls(slot): store.perform(.foul(slot: slot, delta: 1))
        case let .timeouts(slot): store.perform(.timeout(slot: slot, delta: 1))
        }
    }

    private func handleLongPress(_ element: BoardElement) {
        switch element {
        case let .score(slot): store.perform(.score(slot: slot, points: -1))
        case .clock: store.perform(.setClockElapsed(0))
        case .period: store.perform(.previousPeriod)
        case .possession: store.perform(.setPossession(nil))
        case .shotClock: store.perform(.resetShotClock(full: false))
        case let .fouls(slot): store.perform(.foul(slot: slot, delta: -1))
        case let .timeouts(slot): store.perform(.timeout(slot: slot, delta: -1))
        }
    }

    private func flipPossession() {
        let current = store.state.possessionSlot
        let next = current == 0 ? 1 : 0
        store.perform(.setPossession(next))
    }
}

extension MatchSide {
    var boardInfo: BoardSideInfo {
        BoardSideInfo(
            displayName: displayName,
            shortName: shortName,
            colorHex: colorHex,
            emoji: emoji
        )
    }
}
