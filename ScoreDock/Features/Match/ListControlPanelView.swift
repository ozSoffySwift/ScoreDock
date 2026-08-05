import SwiftUI
import UIKit

/// The operator's screen for list and table boards (§4.2, §6.5).
///
/// The controls differ per style far more than they do between the other engines: adding a point to
/// a leaderboard, recording a league result, advancing someone through a bracket and filling in a
/// round of a score sheet are four different jobs.
struct ListControlPanelView: View {
    @Bindable var store: ListStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(MatchFeedback.self) private var feedback

    @State private var externalDisplay = ExternalDisplay.shared
    @State private var showingCastingSheet = false
    @State private var showingEndConfirmation = false
    /// Step size for leaderboard and score-sheet entry — board games rarely score in ones.
    @State private var step = 1

    var body: some View {
        let board = store.board()

        VStack(spacing: 0) {
            ListBoardView(
                board: board,
                sides: store.sides.map(\.boardInfo),
                theme: store.theme,
                font: .sevenSegment,
                isCompact: true,
                onTapRow: { store.perform(.score(slot: $0, points: step)) },
                onTapMatch: { match, slot in store.perform(.setBracketWinner(match: match, slot: slot)) }
            )
            .frame(height: 230)

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    switch board.style {
                    case .leaderboard, .scoreSheet:
                        if board.style == .scoreSheet { roundRow(board) }
                        stepPicker
                        scoreRows(board)
                    case .standings:
                        standingsRows(board)
                    case .bracket:
                        bracketHint
                    }

                    commonControls
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: Leaderboard and score sheet

    private var stepPicker: some View {
        Picker(String(localized: "Step", comment: "Score increment picker"), selection: $step) {
            ForEach([1, 5, 10, 25], id: \.self) { Text("+\($0)").tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func roundRow(_ board: DerivedListBoard) -> some View {
        HStack(spacing: 10) {
            Button { store.perform(.previousPeriod) } label: {
                Image(systemName: "chevron.left").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(board.currentRound == 0)

            Text("Round \(board.currentRound + 1) of \(board.roundCount)", comment: "Score sheet round")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)

            Button { store.perform(.advancePeriod) } label: {
                Image(systemName: "chevron.right").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(board.currentRound >= board.roundCount - 1)
        }
    }

    private func scoreRows(_ board: DerivedListBoard) -> some View {
        VStack(spacing: 8) {
            ForEach(Array(store.sides.enumerated()), id: \.offset) { slot, side in
                HStack(spacing: 10) {
                    Text(side.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: side.colorHex))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        store.perform(.score(slot: slot, points: -step))
                    } label: {
                        Image(systemName: "minus").frame(width: 54, height: 44)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.perform(.score(slot: slot, points: step))
                    } label: {
                        Text("+\(step)").frame(width: 72, height: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: side.colorHex))
                }
            }
        }
    }

    // MARK: Standings

    private func standingsRows(_ board: DerivedListBoard) -> some View {
        VStack(spacing: 12) {
            ForEach(Array(store.sides.enumerated()), id: \.offset) { slot, side in
                VStack(alignment: .leading, spacing: 6) {
                    Text(side.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color(hex: side.colorHex))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        ForEach(RecordField.allCases, id: \.self) { field in
                            Button {
                                store.perform(.adjustRecord(slot: slot, field: field, delta: 1))
                            } label: {
                                Text(field.shortLabel)
                                    .font(.caption.weight(.bold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.bordered)
                            // Long-press subtracts, matching the board's tap/long-press pairing (§4.2).
                            .simultaneousGesture(
                                LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                    store.perform(.adjustRecord(slot: slot, field: field, delta: -1))
                                }
                            )
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) { EmptyView() }
    }

    // MARK: Bracket

    private var bracketHint: some View {
        Label {
            Text(
                "Tap a name in the bracket to advance them. Byes advance on their own, and changing an earlier result clears the rounds after it.",
                comment: "Bracket hint"
            )
            .font(.footnote)
        } icon: {
            Image(systemName: "hand.tap")
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shared

    private var commonControls: some View {
        VStack(spacing: 12) {
            if store.rules.style == .standings || store.rules.style == .leaderboard {
                Text("Long-press a button to subtract.", comment: "Long press hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
    }
}

/// Hosts a running list or table board.
struct ListContainerView: View {
    let store: ListStore
    var onFinish: () -> Void

    @State private var orientation = OrientationReader()
    @State private var externalDisplay = ExternalDisplay.shared
    @State private var active = ActiveMatch.shared
    @State private var venue = VenueMonitor()
    @State private var feedback: MatchFeedback
    @State private var showingFullScreenBoard = false
    @State private var showingReport = false

    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(store: ListStore, onFinish: @escaping () -> Void) {
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
                fullBoard.transition(.opacity)
            } else {
                ListControlPanelView(
                    store: store,
                    onRequestFullScreen: { showingFullScreenBoard = true },
                    onFinish: { showingReport = true }
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
            fullBoard
                .overlay(alignment: .topTrailing) {
                    Button { showingFullScreenBoard = false } label: {
                        Image(systemName: "xmark")
                            .padding(12)
                            .background(.ultraThinMaterial, in: .circle)
                    }
                    .padding()
                }
                .onAppear { AppDelegate.setOrientation(.landscape) }
                .onDisappear { AppDelegate.setOrientation(.all) }
        }
        .sheet(isPresented: $showingReport, onDismiss: onFinish) {
            NavigationStack { MatchReportView(match: store.match) }
        }
        .task {
            // Publishes the store to the external display scene, which has no SwiftUI environment
            // to read it from (§5.2). Every engine does this, not just the team one.
            active.begin(.list(store))
            feedback.start()
            feedback.applyAccessibility(reduceMotion: reduceMotion)
            store.onAction = { [feedback] action in feedback.actionOccurred(action) }
            venue.start()
        }
        .onDisappear {
            store.onAction = nil
            venue.stop()
            active.end()
        }
    }

    private var fullBoard: some View {
        ZStack {
            store.theme.backgroundColor.ignoresSafeArea()
            ListBoardView(
                board: store.board(),
                sides: store.sides.map(\.boardInfo),
                theme: store.theme,
                font: settings.boardFont,
                onTapRow: { store.perform(.score(slot: $0, points: 1)) },
                onTapMatch: { match, slot in store.perform(.setBracketWinner(match: match, slot: slot)) }
            )
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .preferredColorScheme(store.theme.preferredColorScheme)
    }
}
