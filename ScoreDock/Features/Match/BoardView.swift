import SwiftUI
import UIKit

/// The full-screen board (§4.3).
///
/// Nothing but the scoreboard — no chrome, no status bar, no controls — except a translucent
/// toolbar that fades in on tap and out again after three seconds.
///
/// Tap targets stay live here, so a phone lying flat on the scorer's table is still fully operable.
struct BoardView: View {
    @Bindable var store: LiveMatchStore

    /// Shown when the board is presented as a full-screen cover rather than reached by rotating.
    var onExit: (() -> Void)?

    @Environment(AppSettings.self) private var settings
    @Environment(MatchFeedback.self) private var feedback
    @Environment(VenueMonitor.self) private var venue
    @Environment(\.scenePhase) private var scenePhase

    @State private var showsToolbar = false
    @State private var toolbarHideTask: Task<Void, Never>?
    @State private var zoom: CGFloat = 1
    /// Disables every board tap target. Essential when a phone sits on a table near spectators (§12).
    @State private var isLocked = false

    /// Drops to 1 Hz when the device is thermally throttled, which also drops tenths (§12).
    private var tickInterval: TimeInterval {
        guard store.state.clock.isRunning || store.state.breakClock?.isRunning == true else { return 1 }
        guard !venue.isThermallyThrottled else { return 1 }
        return store.rules.showTenths ? 0.1 : 1
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: tickInterval)) { context in
            let board = store.board(at: context.date)
            let drift = burnInOffset(at: context.date)

            ZStack {
                store.theme.backgroundColor.ignoresSafeArea()

                ScoreboardView(
                    board: board,
                    sides: store.sides.map(\.boardInfo),
                    theme: store.theme,
                    font: settings.boardFont,
                    isInteractive: !isLocked,
                    onTap: { handleTap($0) },
                    onLongPress: { handleLongPress($0) }
                )
                .scaleEffect(zoom)
                // Burn-in protection: ±2 pt on a slow 90-second cycle — imperceptible to viewers,
                // sufficient to protect OLED phone and TV panels over a three-hour match (§12).
                .offset(x: drift.width, y: drift.height)
                .ignoresSafeArea()

                if showsToolbar {
                    toolbar
                        .transition(.opacity)
                }
            }
            .onChange(of: board.primaryClock.hasExpired) { _, isExpired in
                if isExpired { store.stopIfExpired() }
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(store.theme.preferredColorScheme)
        .contentShape(.rect)
        // A tap anywhere that is not a board element reveals the toolbar.
        .simultaneousGesture(TapGesture().onEnded { revealToolbar() })
        .onAppear { setIdleTimer(disabled: true) }
        .onDisappear { setIdleTimer(disabled: false) }
        .onChange(of: scenePhase) { _, phase in
            // Never leave the idle timer globally disabled (§12).
            setIdleTimer(disabled: phase == .active)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        VStack {
            HStack(spacing: 18) {
                Button {
                    zoom = max(0.6, zoom - 0.1)
                    revealToolbar()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .accessibilityLabel(Text("Zoom out", comment: "Board toolbar"))

                Button {
                    zoom = min(1.6, zoom + 0.1)
                    revealToolbar()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .accessibilityLabel(Text("Zoom in", comment: "Board toolbar"))

                // Quick-mute, per §11.1 — reachable without leaving the board.
                Button {
                    feedback.isQuickMuted.toggle()
                    if feedback.isQuickMuted { MatchAudio.shared.stopAll() }
                    feedback.rearm(for: store)
                    revealToolbar()
                } label: {
                    Image(systemName: feedback.isQuickMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                }
                .accessibilityLabel(
                    feedback.isQuickMuted
                        ? Text("Unmute sounds", comment: "Board toolbar")
                        : Text("Mute sounds", comment: "Board toolbar")
                )

                Button {
                    isLocked.toggle()
                    revealToolbar()
                } label: {
                    Image(systemName: isLocked ? "lock.fill" : "lock.open")
                }
                .accessibilityLabel(
                    isLocked
                        ? Text("Unlock board controls", comment: "Board toolbar")
                        : Text("Lock board controls", comment: "Board toolbar")
                )

                if let onExit {
                    Button {
                        onExit()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(Text("Exit full screen", comment: "Board toolbar"))
                }
            }
            .font(.title3)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: .capsule)
            .padding(.top, 12)

            Spacer()
        }
    }

    private func revealToolbar() {
        withAnimation(.easeOut(duration: 0.2)) { showsToolbar = true }
        toolbarHideTask?.cancel()
        toolbarHideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.3)) { showsToolbar = false }
        }
    }

    // MARK: Venue behaviour

    private func burnInOffset(at date: Date) -> CGSize {
        guard settings.burnInProtection else { return .zero }
        let phase = date.timeIntervalSinceReferenceDate / 90 * 2 * .pi
        return CGSize(width: sin(phase) * 2, height: cos(phase) * 2)
    }

    private func setIdleTimer(disabled: Bool) {
        // Only while a match is actually live — a finished board should let the screen sleep.
        let shouldDisable = disabled && store.match.status == .live
        UIApplication.shared.isIdleTimerDisabled = shouldDisable
    }

    // MARK: Interaction (same §4.2 table as the control panel)

    private func handleTap(_ element: BoardElement) {
        switch element {
        case let .score(slot): store.perform(.score(slot: slot, points: 1))
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
