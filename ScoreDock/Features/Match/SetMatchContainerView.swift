import SwiftUI
import UIKit

/// Hosts a running set-match game (§5.1, §5.3).
///
/// Same surface rules as the team container: rotate to the board, suppressed while casting, with
/// the full-screen button as the guaranteed path.
struct SetMatchContainerView: View {
    let store: SetMatchStore
    var onFinish: () -> Void

    @State private var orientation = OrientationReader()
    @State private var externalDisplay = ExternalDisplay.shared
    @State private var active = ActiveMatch.shared
    @State private var venue = VenueMonitor()
    @State private var feedback: MatchFeedback
    @State private var showingFullScreenBoard = false
    @State private var showingReport = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: SetMatchStore, onFinish: @escaping () -> Void) {
        self.store = store
        self.onFinish = onFinish
        _feedback = State(initialValue: MatchFeedback(settings: AppSettings.shared))
    }

    private var showsBoardOnDevice: Bool {
        MatchSurface.deviceShowsBoard(
            isLandscape: orientation.orientation == .landscape,
            isCasting: externalDisplay.isConnected
        )
    }

    var body: some View {
        ZStack {
            if showsBoardOnDevice {
                SetMatchFullBoardView(store: store).transition(.opacity)
            } else {
                SetMatchControlPanelView(
                    store: store,
                    onRequestFullScreen: { showingFullScreenBoard = true },
                    onFinish: finish
                )
                .transition(.opacity)
            }
        }
        .environment(feedback)
        .environment(venue)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: showsBoardOnDevice)
        .navigationBarBackButtonHidden(showsBoardOnDevice)
        .toolbar(showsBoardOnDevice ? .hidden : .visible, for: .navigationBar)
        .fullScreenCover(isPresented: $showingFullScreenBoard) {
            SetMatchFullBoardView(store: store, onExit: { showingFullScreenBoard = false })
                .environment(feedback)
                .onAppear { AppDelegate.setOrientation(.landscape) }
                .onDisappear { AppDelegate.setOrientation(.all) }
        }
        .sheet(isPresented: $showingReport, onDismiss: onFinish) {
            NavigationStack { MatchReportView(match: store.match) }
        }
        .task {
            // Publishes the store to the external display scene, which has no SwiftUI environment
            // to read it from (§5.2). Every engine does this, not just the team one.
            active.begin(.setMatch(store))
            feedback.start()
            feedback.applyAccessibility(reduceMotion: reduceMotion)
            store.onAction = { [feedback] action in feedback.actionOccurred(action) }
            venue.start()
        }
        .onDisappear {
            store.onAction = nil
            MatchAudio.shared.stopAll()
            venue.stop()
            active.end()
        }
        // A rally match ends itself the moment the deciding point lands, so the report has to be
        // offered on that transition rather than only from the End match button.
        .onChange(of: store.state.isFinished) { _, finished in
            if finished { showingReport = true }
        }
    }

    private func finish() {
        showingReport = true
    }
}

/// The full-screen set-match board (§4.3).
struct SetMatchFullBoardView: View {
    @Bindable var store: SetMatchStore
    var onExit: (() -> Void)?

    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase

    @State private var showsToolbar = false
    @State private var toolbarHideTask: Task<Void, Never>?
    @State private var isLocked = false

    var body: some View {
        ZStack {
            store.theme.backgroundColor.ignoresSafeArea()

            SetMatchBoardView(
                board: store.board(),
                sides: store.sides.map(\.boardInfo),
                theme: store.theme,
                font: settings.boardFont,
                isInteractive: !isLocked,
                onTap: { store.perform(.score(slot: $0, points: 1)) },
                onLongPress: { store.perform(.score(slot: $0, points: -1)) }
            )
            .ignoresSafeArea()

            if showsToolbar {
                VStack {
                    HStack(spacing: 18) {
                        Button { isLocked.toggle(); revealToolbar() } label: {
                            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                        }
                        if let onExit {
                            Button { onExit() } label: { Image(systemName: "xmark") }
                        }
                    }
                    .font(.title3)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: .capsule)
                    .padding(.top, 12)
                    Spacer()
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(store.theme.preferredColorScheme)
        .contentShape(.rect)
        .simultaneousGesture(TapGesture().onEnded { revealToolbar() })
        .onAppear { setIdleTimer(disabled: true) }
        .onDisappear { setIdleTimer(disabled: false) }
        .onChange(of: scenePhase) { _, phase in setIdleTimer(disabled: phase == .active) }
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

    private func setIdleTimer(disabled: Bool) {
        UIApplication.shared.isIdleTimerDisabled = disabled && store.match.status == .live
    }
}
