import SwiftUI

/// The iPad control panel (§4.2a).
///
/// **A genuinely different layout, not the iPhone one stretched.** The scorer's table is the iPad's
/// natural home and the extra space changes what is possible:
///
/// - The preview sits at roughly twice the iPhone's relative size, readable at arm's length by an
///   operator who is watching the game rather than the tablet.
/// - Every control is visible at once — no scrolling, no disclosure groups. On iPhone the break
///   timer, period override and multi-point buttons compete for space; here they coexist.
/// - When attribution is on, the **roster stays permanently visible** instead of appearing as a
///   sheet per score. That is the difference between attribution being pleasant and being a chore.
/// - Hit targets are 60 pt, not 44. A 44 pt minimum is an iPhone constraint; an operator glancing
///   down mid-play at a tablet deserves more.
///
/// It is a distinct view composed from the same components and driven by the same `LiveMatchStore`
/// — shared logic, separate layout. §4.2a warns explicitly against one adaptive layout serving
/// both, because that produces a panel that is mediocre on each.
struct PadControlPanelView: View {
    @Bindable var store: LiveMatchStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(MatchFeedback.self) private var feedback
    @Environment(VenueMonitor.self) private var venue

    @State private var externalDisplay = ExternalDisplay.shared
    @State private var active = ActiveMatch.shared
    @State private var showingCastingSheet = false
    @State private var showingEndConfirmation = false
    @State private var showingPeriodLabel = false
    /// Armed player per side, for the roster rail. Nil means the next score is unattributed.
    @State private var armedPlayer: [Int: UUID] = [:]

    private static let targetHeight: CGFloat = 60

    private var tickInterval: TimeInterval {
        guard store.state.clock.isRunning || store.state.breakClock?.isRunning == true else { return 1 }
        guard !venue.isThermallyThrottled else { return 1 }
        return store.rules.showTenths ? 0.1 : 1
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let board = store.board(at: context.date)

            HStack(alignment: .top, spacing: 20) {
                leftColumn(board)
                    .frame(maxWidth: .infinity)
                rightColumn(board)
                    .frame(width: 380)
            }
            .padding(20)
            .onChange(of: board.primaryClock.hasExpired) { _, isExpired in
                if isExpired { store.stopIfExpired() }
            }
        }
    }

    // MARK: Left — preview and roster

    private func leftColumn(_ board: DerivedBoard) -> some View {
        VStack(spacing: 16) {
            ScoreboardView(
                board: board,
                sides: store.sides.map(\.boardInfo),
                theme: store.theme,
                font: .sevenSegment,
                onTap: { handleTap($0) },
                onLongPress: { handleLongPress($0) }
            )
            .frame(height: 320)
            .clipShape(.rect(cornerRadius: 16))

            if store.match.attributionEnabled {
                rosterRail
            }

            Spacer(minLength: 0)
        }
    }

    /// Permanently visible rosters (§4.2a). Arm a player, then score — the credit applies and the
    /// selection clears, so the common case is two taps with no sheet in the way.
    private var rosterRail: some View {
        HStack(alignment: .top, spacing: 16) {
            ForEach(Array(store.sides.enumerated()), id: \.offset) { slot, side in
                VStack(alignment: .leading, spacing: 8) {
                    Text(side.displayName)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color(hex: side.colorHex))

                    let roster = roster(for: slot)
                    if roster.isEmpty {
                        Text("Link a saved team in Setup to credit players.", comment: "Empty rail")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 6) {
                                rosterButton(
                                    title: String(localized: "No credit", comment: "Attribution escape"),
                                    isArmed: armedPlayer[slot] == nil,
                                    tint: .secondary
                                ) { armedPlayer[slot] = nil }

                                ForEach(roster) { player in
                                    rosterButton(
                                        title: player.displayName,
                                        isArmed: armedPlayer[slot] == player.id,
                                        tint: Color(hex: side.colorHex)
                                    ) { armedPlayer[slot] = player.id }
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func rosterButton(
        title: String,
        isArmed: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title).lineLimit(1)
                Spacer(minLength: 0)
                if isArmed { Image(systemName: "checkmark") }
            }
            .font(.callout.weight(isArmed ? .bold : .regular))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
        }
        .buttonStyle(.bordered)
        .tint(isArmed ? tint : .gray)
    }

    // MARK: Right — every control at once

    private func rightColumn(_ board: DerivedBoard) -> some View {
        VStack(spacing: 12) {
            if venue.showsLowBatteryWarning || venue.thermalState.operatorExplanation != nil {
                venueBanner
            }

            castingControl

            ForEach(Array(store.sides.enumerated()), id: \.offset) { slot, side in
                VStack(spacing: 8) {
                    Text(side.displayName)
                        .font(.headline)
                        .foregroundStyle(Color(hex: side.colorHex))

                    HStack(spacing: 8) {
                        ForEach(store.rules.scoreIncrements, id: \.self) { points in
                            Button {
                                score(slot: slot, points: points)
                            } label: {
                                Text("+\(points)")
                                    .font(.title3.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: Self.targetHeight)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(hex: side.colorHex))
                        }
                    }

                    HStack(spacing: 8) {
                        compact(String(localized: "−1", comment: "Subtract a point")) {
                            store.perform(.score(slot: slot, points: -1))
                        }
                        if store.rules.foulTrackingEnabled {
                            compact(String(localized: "Foul", comment: "Add a foul")) {
                                store.perform(.foul(slot: slot, delta: 1))
                            }
                        }
                        if store.rules.timeoutCount > 0 {
                            compact(String(localized: "Timeout", comment: "Use a timeout")) {
                                store.perform(.timeout(slot: slot, delta: 1))
                            }
                        }
                    }
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    store.perform(.toggleClock)
                } label: {
                    Label(
                        board.primaryClock.isRunning
                            ? String(localized: "Stop", comment: "Clock button")
                            : String(localized: "Start", comment: "Clock button"),
                        systemImage: board.primaryClock.isRunning ? "pause.fill" : "play.fill"
                    )
                    .frame(maxWidth: .infinity, minHeight: Self.targetHeight)
                }
                .buttonStyle(.borderedProminent)
                .tint(board.primaryClock.isRunning ? .orange : .green)

                compact(board.isBreak
                    ? String(localized: "End break", comment: "Break button")
                    : String(localized: "Break", comment: "Break button")
                ) {
                    store.perform(board.isBreak ? .endBreak : .startBreak(store.rules.breakDuration))
                }
                .disabled(store.rules.breakDuration <= 0)
            }

            HStack(spacing: 8) {
                compact(String(localized: "Period +", comment: "Advance period")) {
                    store.perform(.advancePeriod)
                }
                compact(board.periodLabel) { showingPeriodLabel = true }
                    .confirmationDialog(
                        Text("Period label", comment: "Override dialog title"),
                        isPresented: $showingPeriodLabel,
                        titleVisibility: .visible
                    ) {
                        ForEach(["OT", "SO", "HT", "F"], id: \.self) { label in
                            Button(label) { store.perform(.setPeriodLabel(label)) }
                        }
                        Button(String(localized: "Use default", comment: "Clear label override")) {
                            store.perform(.setPeriodLabel(nil))
                        }
                        Button(String(localized: "Cancel", comment: "Dialog cancel"), role: .cancel) {}
                    }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                compact(String(localized: "Undo", comment: "Control panel button")) { store.undo() }
                    .disabled(!store.canUndo)
                compact(String(localized: "Full screen", comment: "Control panel button"), action: onRequestFullScreen)
            }

            Button(role: .destructive) {
                showingEndConfirmation = true
            } label: {
                Text("End match", comment: "Control panel button")
                    .frame(maxWidth: .infinity, minHeight: Self.targetHeight)
            }
            .buttonStyle(.bordered)
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
    }

    @ViewBuilder
    private var castingControl: some View {
        if externalDisplay.isConnected {
            VStack(spacing: 8) {
                HStack {
                    Label(String(localized: "Casting to TV", comment: "Casting badge"), systemImage: "tv.fill")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button {
                        feedback.isQuickMuted.toggle()
                        if feedback.isQuickMuted { MatchAudio.shared.stopAll() }
                        feedback.rearm(for: store)
                    } label: {
                        Image(systemName: feedback.isQuickMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }
                }
                .foregroundStyle(.green)

                BoardModePicker()
            }
            .padding(10)
            .background(.green.opacity(0.12), in: .rect(cornerRadius: 12))
        } else {
            compact(String(localized: "Cast to TV", comment: "Control panel button")) {
                showingCastingSheet = true
            }
            .sheet(isPresented: $showingCastingSheet) { CastingSheet() }
        }
    }

    private var venueBanner: some View {
        VStack(alignment: .leading, spacing: 4) {
            if venue.showsLowBatteryWarning {
                Label(
                    venue.batteryPercent.map {
                        String(localized: "Battery at \($0)% — plug in", comment: "Low battery")
                    } ?? String(localized: "Battery low — plug in", comment: "Low battery"),
                    systemImage: "battery.25"
                )
                .foregroundStyle(.orange)
            }
            if let explanation = venue.thermalState.operatorExplanation {
                Label(explanation, systemImage: "thermometer.high")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.orange.opacity(0.12), in: .rect(cornerRadius: 12))
    }

    private func compact(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, minHeight: Self.targetHeight)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .buttonStyle(.bordered)
    }

    // MARK: Actions

    /// Uses the armed roster selection rather than presenting a sheet — the whole point of the rail.
    private func score(slot: Int, points: Int) {
        store.perform(.score(slot: slot, points: points, playerID: armedPlayer[slot]))
        armedPlayer[slot] = nil
    }

    private func roster(for slot: Int) -> [Player] {
        guard store.sides.indices.contains(slot) else { return [] }
        let side = store.sides[slot]
        if let team = side.linkedTeam { return team.activePlayers }
        if let player = side.linkedPlayer { return [player] }
        return []
    }

    private func handleTap(_ element: BoardElement) {
        switch element {
        case let .score(slot): score(slot: slot, points: 1)
        case .clock: store.perform(.toggleClock)
        case .period: store.perform(.advancePeriod)
        case .possession: store.perform(.setPossession(store.state.possessionSlot == 0 ? 1 : 0))
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
}
