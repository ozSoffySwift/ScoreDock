import SwiftUI

/// The operator's screen for a baseball board (§4.2, §6.3).
///
/// The pitch row is the hot path — ball and strike are pressed hundreds of times a game — so they
/// are the two largest targets and never move. The bases are toggles rather than buttons that "do"
/// something, because baserunning is the one part of the game a scoreboard should not try to infer.
struct BaseballControlPanelView: View {
    @Bindable var store: SpecialisedStore

    var onRequestFullScreen: () -> Void
    var onFinish: () -> Void

    @Environment(AppSettings.self) private var settings

    @State private var showingEndConfirmation = false
    @State private var showingCastingSheet = false
    @State private var externalDisplay = ExternalDisplay.shared

    var body: some View {
        VStack(spacing: 0) {
            if case let .baseball(board) = store.board() {
                BaseballBoardView(
                    board: board,
                    sides: store.sides.map(\.boardInfo),
                    theme: store.theme,
                    font: settings.boardFont,
                    isCompact: true,
                    isInteractive: false
                )
                .frame(height: 210)
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
    private func controls(_ board: DerivedBaseballBoard) -> some View {
        VStack(spacing: 14) {
            pitchSection
            playSection
            basesSection(board)
            inningSection(board)
            matchSection
        }
        .sheet(isPresented: $showingCastingSheet) { CastingSheet() }
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
        }
    }

    private var pitchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Pitch", comment: "Control section"))

            ControlButtonGrid(items: [PitchOutcome.ball, .strike, .foul], columns: 3) { outcome in
                Text(outcome.shortLabel)
                    .font(outcome == .foul ? .subheadline.weight(.semibold) : .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } action: { outcome in
                store.perform(.specialised(.pitch(outcome)))
            }
            .buttonStyle(.bordered)
        }
    }

    private var playSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Play", comment: "Control section"))

            ControlButtonGrid(items: [PitchOutcome.hit, .out, .error, .run], columns: 4) { outcome in
                Text(outcome.shortLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } action: { outcome in
                store.perform(.specialised(.pitch(outcome)))
            }
            .buttonStyle(.bordered)
            .tint(.secondary)
        }
    }

    private func basesSection(_ board: DerivedBaseballBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Runners", comment: "Control section"))

            ControlButtonGrid(items: BaseControl.allCases, columns: 4) { control in
                Text(control.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(control.isOn(board.bases) ? Color.accentColor : .secondary)
            } action: { control in
                switch control {
                case .first: setBases(board, first: !board.bases.first)
                case .second: setBases(board, second: !board.bases.second)
                case .third: setBases(board, third: !board.bases.third)
                case .clear: store.perform(.specialised(.setBases(first: false, second: false, third: false)))
                }
            }
            .buttonStyle(.bordered)

            Text(
                "A walk or a hit moves only the runners who are forced. Set the rest here.",
                comment: "Runners hint"
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    /// The four runner controls as one list, so the grid can lay them out together.
    private enum BaseControl: CaseIterable, Hashable {
        case first, second, third, clear

        var label: String {
            switch self {
            case .first: String(localized: "1st", comment: "Base")
            case .second: String(localized: "2nd", comment: "Base")
            case .third: String(localized: "3rd", comment: "Base")
            case .clear: String(localized: "Clear", comment: "Bases control")
            }
        }

        func isOn(_ bases: BaseOccupancy) -> Bool {
            switch self {
            case .first: bases.first
            case .second: bases.second
            case .third: bases.third
            case .clear: false
            }
        }
    }

    private func setBases(
        _ board: DerivedBaseballBoard,
        first: Bool? = nil,
        second: Bool? = nil,
        third: Bool? = nil
    ) {
        store.perform(.specialised(.setBases(
            first: first ?? board.bases.first,
            second: second ?? board.bases.second,
            third: third ?? board.bases.third
        )))
    }

    private func inningSection(_ board: DerivedBaseballBoard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel(String(localized: "Inning", comment: "Control section"))

            Button {
                store.perform(.specialised(.advanceHalfInning))
            } label: {
                Label(
                    String(localized: "Next half-inning", comment: "Baseball control"),
                    systemImage: "arrow.turn.down.right"
                )
                .frame(maxWidth: .infinity, minHeight: 42)
            }
            .buttonStyle(.bordered)

            if isComplete {
                // Reported, not enforced: a walk-off ends play mid-inning, and the home side never
                // bats the bottom of the ninth when it is already ahead.
                Label(
                    String(localized: "Regulation is complete — end the game when play stops.", comment: "Baseball hint"),
                    systemImage: "checkmark.circle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var isComplete: Bool {
        guard let state = store.state.baseball else { return false }
        return BaseballEngine.isComplete(state, rules: store.rules.baseball ?? BaseballRules())
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
                Label(String(localized: "End game", comment: "Control"), systemImage: "flag.checkered")
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
