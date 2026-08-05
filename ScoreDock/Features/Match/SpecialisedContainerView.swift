import SwiftUI
import UIKit

/// Hosts a running game on one of the bespoke boards (§5.1, §5.3, §6.3).
///
/// Same surface rules as the other three containers: rotate to the board, suppressed while casting,
/// with the full-screen button as the guaranteed path.
struct SpecialisedContainerView: View {
    let store: SpecialisedStore
    var onFinish: () -> Void

    @State private var orientation = OrientationReader()
    @State private var externalDisplay = ExternalDisplay.shared
    @State private var active = ActiveMatch.shared
    @State private var venue = VenueMonitor()
    @State private var feedback: MatchFeedback
    @State private var showingFullScreenBoard = false
    @State private var showingReport = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: SpecialisedStore, onFinish: @escaping () -> Void) {
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
                SpecialisedFullBoardView(store: store).transition(.opacity)
            } else {
                SpecialisedControlPanelView(
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
            SpecialisedFullBoardView(store: store, onExit: { showingFullScreenBoard = false })
                .environment(feedback)
                .environment(venue)
                .onAppear { AppDelegate.setOrientation(.landscape) }
                .onDisappear { AppDelegate.setOrientation(.all) }
        }
        .sheet(isPresented: $showingReport, onDismiss: onFinish) {
            NavigationStack { MatchReportView(match: store.match) }
        }
        .task {
            // Publishes the store to the external display scene, which has no SwiftUI environment
            // to read it from (§5.2). Every engine does this, not just the team one.
            active.begin(.specialised(store))
            feedback.start()
            feedback.applyAccessibility(reduceMotion: reduceMotion)
            feedback.rearm(for: store)
            store.onAction = { [feedback] action in feedback.actionOccurred(action) }
            venue.start()
        }
        // Any state change re-arms the scheduled sounds; `rearm` is idempotent, so this needs no
        // knowledge of *what* changed — only that something did.
        .onChange(of: store.state) { _, _ in feedback.rearm(for: store) }
        .onDisappear {
            store.onAction = nil
            MatchAudio.shared.stopAll()
            venue.stop()
            active.end()
        }
        // A flag ends the game with no tap behind it, so the report is offered on the transition
        // rather than only from the End game button.
        .onChange(of: store.state.isFinished) { _, finished in
            if finished { showingReport = true }
        }
    }

    private func finish() {
        showingReport = true
    }
}

/// Picks the operator's screen for a bespoke board (§6.3).
///
/// Same reasoning as `SpecialisedSetupView`: a chess clock's controls are a pause button and an
/// arbiter's time correction, a race timer's are a start gun and a lap hint. One panel with five
/// conditional halves would serve neither.
struct SpecialisedControlPanelView: View {
    let store: SpecialisedStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    var body: some View {
        switch store.rules.board {
        case .chessClock:
            ChessClockControlPanelView(
                store: store,
                onRequestFullScreen: onRequestFullScreen,
                onFinish: onFinish
            )
        case .raceTimer:
            RaceTimerControlPanelView(
                store: store,
                onRequestFullScreen: onRequestFullScreen,
                onFinish: onFinish
            )
        case .americanFootball:
            FootballControlPanelView(
                store: store,
                onRequestFullScreen: onRequestFullScreen,
                onFinish: onFinish
            )
        case .cricket:
            CricketControlPanelView(
                store: store,
                onRequestFullScreen: onRequestFullScreen,
                onFinish: onFinish
            )
        case .baseball:
            BaseballControlPanelView(
                store: store,
                onRequestFullScreen: onRequestFullScreen,
                onFinish: onFinish
            )
        }
    }
}

/// The full-screen bespoke board (§4.3).
struct SpecialisedFullBoardView: View {
    @Bindable var store: SpecialisedStore
    var onExit: (() -> Void)?

    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @Environment(VenueMonitor.self) private var venue

    @State private var showsToolbar = false
    @State private var toolbarHideTask: Task<Void, Never>?
    @State private var isLocked = false

    private var tickInterval: TimeInterval {
        let running = switch store.board() {
        case let .chessClock(board): board.isRunning
        case let .raceTimer(board): board.raceClock.isRunning
        case let .americanFootball(board): board.gameClock.isRunning || board.playClock.isRunning
        // Neither cricket nor baseball has a clock, so their boards never need a fast tick.
        case .cricket, .baseball: false
        case .unavailable: false
        }
        guard running else { return 1 }
        return venue.isThermallyThrottled ? 1 : 0.1
    }

    var body: some View {
        ZStack {
            store.theme.backgroundColor.ignoresSafeArea()

            TimelineView(.periodic(from: .now, by: tickInterval)) { context in
                let derived = store.board(at: context.date)

                Group {
                    switch derived {
                    case let .chessClock(board):
                        ChessClockBoardView(
                            board: board,
                            sides: store.sides.map(\.boardInfo),
                            theme: store.theme,
                            font: settings.boardFont,
                            isInteractive: !isLocked && !board.isFinished,
                            onPress: { store.perform(.specialised(.pressClock(slot: $0))) }
                        )
                    case let .raceTimer(board):
                        RaceTimerBoardView(
                            board: board,
                            sides: store.sides.map(\.boardInfo),
                            theme: store.theme,
                            font: settings.boardFont,
                            isInteractive: !isLocked && !board.isFinished,
                            onLap: { store.perform(.specialised(.recordLap(slot: $0))) },
                            onFinish: { store.perform(.specialised(.finishRacer(slot: $0))) }
                        )
                    case let .americanFootball(board):
                        FootballBoardView(
                            board: board,
                            sides: store.sides.map(\.boardInfo),
                            theme: store.theme,
                            font: settings.boardFont,
                            isInteractive: !isLocked && !board.isFinished,
                            onTap: { store.perform(.setPossession($0)) }
                        )
                    case let .cricket(board):
                        CricketBoardView(
                            board: board,
                            sides: store.sides.map(\.boardInfo),
                            theme: store.theme,
                            font: settings.boardFont,
                            isInteractive: false
                        )
                    case let .baseball(board):
                        BaseballBoardView(
                            board: board,
                            sides: store.sides.map(\.boardInfo),
                            theme: store.theme,
                            font: settings.boardFont,
                            isInteractive: false
                        )
                    case let .unavailable(board):
                        UnavailableBoardView(board: board, theme: store.theme)
                    }
                }
                .ignoresSafeArea()
                .onChange(of: flaggedSlot(in: derived)) { _, flagged in
                    if flagged != nil { store.checkForTimeExpiry(at: context.date) }
                }
            }

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
        // The clock faces are the buttons here, so revealing the toolbar has to be a *separate*
        // gesture — a stray tap that both pressed the clock and showed the chrome would cost a
        // player their move.
        .simultaneousGesture(
            TapGesture(count: 2).onEnded { revealToolbar() }
        )
        .onAppear { setIdleTimer(disabled: true) }
        .onDisappear { setIdleTimer(disabled: false) }
        .onChange(of: scenePhase) { _, phase in setIdleTimer(disabled: phase == .active) }
    }

    private func flaggedSlot(in board: DerivedSpecialisedBoard) -> Int? {
        guard case let .chessClock(clock) = board else { return nil }
        return clock.flaggedSlot
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

/// Shown when a match names a board this build does not implement yet.
///
/// It should be unreachable — the router refuses to open one — but a match synced from a newer
/// build could carry one, and an empty screen would look like data loss.
struct UnavailableBoardView: View {
    var board: SpecialisedBoard
    var theme: ThemeSpec

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge")
                .font(.largeTitle)
            Text("This board is not available in this version of ScoreDock.", comment: "Unavailable board")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(theme.labelColor)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.backgroundColor)
    }
}
