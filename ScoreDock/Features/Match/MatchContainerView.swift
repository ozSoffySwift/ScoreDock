import OSLog
import SwiftUI
import UIKit

/// Hosts a running match and decides which surface the device shows (§5.1, §5.3).
///
/// Rotation swaps *which view is on screen* with a crossfade. It does **not** push a navigation
/// destination and does **not** re-instantiate the engine — `store` is created once by the caller
/// and every surface renders the same state.
///
/// ### The §5.3 behaviour matrix
///
/// | Device | External display | Device shows | TV shows |
/// |---|---|---|---|
/// | Portrait | none | Control panel | — |
/// | Landscape | none | Board (interactive) | — |
/// | Portrait | connected | Control panel + Casting badge | Board |
/// | **Landscape** | **connected** | **Control panel** | **Board** |
///
/// The last row is the one that matters. When a TV is already showing the board, rotating the
/// device must not replace the operator's controls with a second copy of it — that is the worst
/// possible outcome. So while an external display is connected, rotate-to-board is suppressed and
/// the panel keeps its portrait layout. A properly designed landscape panel is deferred (§5.3);
/// this behaviour is correct, just not optimal.
struct MatchContainerView: View {
    let store: LiveMatchStore
    var onFinish: () -> Void

    @State private var orientation = OrientationReader()
    @State private var externalDisplay = ExternalDisplay.shared
    @State private var active = ActiveMatch.shared
    @State private var venue = VenueMonitor()
    @State private var feedback: MatchFeedback
    @State private var showingFullScreenBoard = false
    @State private var showingReport = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "orientation")

    init(store: LiveMatchStore, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        _feedback = State(initialValue: MatchFeedback(settings: AppSettings.shared))
    }

    /// Rotate-to-board, suppressed while casting — see `MatchSurface` for the rule.
    private var showsBoardOnDevice: Bool {
        MatchSurface.deviceShowsBoard(
            isLandscape: orientation.orientation == .landscape,
            isCasting: externalDisplay.isConnected
        )
    }

    var body: some View {
        ZStack {
            if showsBoardOnDevice {
                BoardView(store: store)
                    .transition(.opacity)
            } else if isPad {
                // §4.2a: a distinct layout, not the iPhone one stretched. Selected on idiom rather
                // than size class — an iPad in Split View is still an iPad at a scorer's table.
                PadControlPanelView(
                    store: store,
                    onRequestFullScreen: { showingFullScreenBoard = true },
                    onFinish: finish
                )
                .transition(.opacity)
            } else {
                ControlPanelView(
                    store: store,
                    onRequestFullScreen: { showingFullScreenBoard = true },
                    onFinish: finish
                )
                .transition(.opacity)
            }
        }
        .environment(feedback)
        .environment(venue)
        // Reduce Motion removes the board crossfade (§15).
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsBoardOnDevice)
        .navigationBarBackButtonHidden(showsBoardOnDevice)
        .toolbar(showsBoardOnDevice ? .hidden : .visible, for: .navigationBar)
        .fullScreenCover(isPresented: $showingFullScreenBoard) {
            BoardView(store: store, onExit: { showingFullScreenBoard = false })
                .environment(feedback)
                .environment(venue)
                .onAppear { requestOrientation(.landscape) }
                .onDisappear { requestOrientation(.all) }
        }
        .sheet(isPresented: $showingReport, onDismiss: onFinish) {
            NavigationStack {
                MatchReportView(match: store.match)
            }
        }
        .task { begin() }
        .onDisappear { end() }
        // Any state change re-arms the scheduled sounds; `rearm` is idempotent so this needs no
        // knowledge of what actually changed (§6.4).
        .onChange(of: store.state) { _, _ in feedback.rearm(for: store) }
        .onChange(of: reduceMotion, initial: true) { _, value in
            feedback.applyAccessibility(reduceMotion: value)
        }
        .onChange(of: scenePhase) { _, phase in
            // Coming back from the background, the clock has moved on — anything that was scheduled
            // is stale, so re-arm against the real remaining time.
            if phase == .active { feedback.rearm(for: store) }
        }
    }

    // MARK: Lifecycle

    private func begin() {
        // Publishes the store to the external display scene, which has no SwiftUI environment (§5.2).
        active.begin(.team(store))
        feedback.start()
        feedback.applyAccessibility(reduceMotion: reduceMotion)
        store.onAction = { [feedback] action in feedback.actionOccurred(action) }
        feedback.rearm(for: store)
        venue.start()
    }

    private func end() {
        store.onAction = nil
        feedback.cancel()
        MatchAudio.shared.stopAll()
        venue.stop()
        active.end()
    }

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// At the final whistle the app presents the Match Report (§13.4) rather than dropping the
    /// operator back to the picker — the report *is* the end of the match.
    private func finish() {
        end()
        showingReport = true
    }

    // MARK: Orientation

    private func requestOrientation(_ mask: UIInterfaceOrientationMask) {
        AppDelegate.setOrientation(mask) { error in
            // Logged rather than swallowed. Even when refused the board still renders correctly —
            // `ScoreboardView` letterboxes to a board shape — but the operator gets a portrait
            // board, and we want that visible rather than mysterious.
            Self.logger.warning("Orientation request refused: \(error.localizedDescription, privacy: .public)")
        }
    }
}
