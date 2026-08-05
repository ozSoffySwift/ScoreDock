import SwiftData
import SwiftUI

/// Setup for the chess clock (§4.1, §6.3).
///
/// The rules section is a **time control**, so it is presented the way players choose one — a row of
/// familiar controls first, with the full base/increment editor underneath for anything else. §8.5's
/// point about editable defaults still holds; this just puts the common answers one tap away.
struct ChessClockSetupView: View {
    let preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var rules: ChessClockRules
    @State private var players: [SideDraft]
    @State private var title = ""
    @State private var venue = ""
    @State private var themeID: String
    @State private var runningStore: SpecialisedStore?

    /// The time controls players actually name, in the order they are usually offered.
    private static let presets: [(label: String, base: TimeInterval, increment: TimeInterval)] = [
        ("1|0", 60, 0),
        ("3|2", 180, 2),
        ("5|3", 300, 3),
        ("10|5", 600, 5),
        ("15|10", 900, 10),
        ("30|0", 1800, 0),
    ]

    init(preset: GamePreset) {
        self.preset = preset
        _rules = State(initialValue: preset.rules.specialisedRules?.chessClock ?? ChessClockRules())
        _themeID = State(initialValue: preset.defaultThemeID)
        _players = State(initialValue: [
            SideDraft(displayName: String(localized: "White", comment: "Chess side"), colorHex: "#ECEFF1"),
            SideDraft(displayName: String(localized: "Black", comment: "Chess side"), colorHex: "#78909C"),
        ])
    }

    private var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }

    var body: some View {
        Form {
            Section {
                ChessClockBoardView(
                    board: previewBoard,
                    sides: players.map {
                        BoardSideInfo(
                            displayName: $0.displayName,
                            shortName: $0.shortName,
                            colorHex: $0.colorHex,
                            emoji: $0.emoji
                        )
                    },
                    theme: theme,
                    font: settings.boardFont,
                    isCompact: true,
                    isInteractive: false
                )
                .frame(height: 220)
                .clipShape(.rect(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            playersSection
            timeControlSection
            detailsSection
            themeSection

            Section {
                Button { start() } label: {
                    Label(String(localized: "Start", comment: "Setup action"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(players.contains { $0.displayName.trimmingCharacters(in: .whitespaces).isEmpty })
            }
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $runningStore) { store in
            NavigationStack {
                SpecialisedContainerView(store: store) { runningStore = nil }
            }
        }
    }

    private var previewBoard: DerivedChessClockBoard {
        let state = ChessClockEngine.initialState(rules: rules, sideCount: 2)
        return ChessClockEngine.derived(state, rules: rules, isFinished: false, at: .now)
    }

    // MARK: Sections

    private var playersSection: some View {
        Section(String(localized: "Players", comment: "Setup section")) {
            ForEach($players) { $player in
                HStack(spacing: 10) {
                    EmojiField(emoji: $player.emoji)
                    TextField(String(localized: "Name", comment: "Setup field"), text: $player.displayName)
                        .textInputAutocapitalization(.words)
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: player.colorHex) },
                        set: { player.colorHex = $0.resolvedHex }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
        }
    }

    private var timeControlSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.label) { option in
                        Button {
                            rules.baseTime = option.base
                            rules.incrementSeconds = option.increment
                            rules.incrementMode = option.increment > 0 ? .fischer : .none
                        } label: {
                            Text(option.label)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                        .tint(isSelected(option) ? .accentColor : .secondary)
                    }
                }
                .padding(.vertical, 2)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))

            Stepper(value: baseMinutes, in: 1 ... 180) {
                LabeledContent(
                    String(localized: "Base time", comment: "Setup field"),
                    value: String(localized: "\(Int(rules.baseTime / 60)) min", comment: "Minutes value")
                )
            }

            // Distinct from the seconds stepper below it — two adjacent rows both reading
            // "Increment" told the operator nothing about which was which.
            Picker(String(localized: "Increment mode", comment: "Setup field"), selection: $rules.incrementMode) {
                Text("Fischer", comment: "Increment mode").tag(ChessClockRules.Increment.fischer)
                Text("Bronstein", comment: "Increment mode").tag(ChessClockRules.Increment.bronstein)
                Text("None", comment: "Increment mode").tag(ChessClockRules.Increment.none)
            }

            if rules.incrementMode != .none {
                Stepper(value: incrementSeconds, in: 0 ... 60) {
                    LabeledContent(
                        String(localized: "Seconds added", comment: "Setup field"),
                        value: String(localized: "\(Int(rules.incrementSeconds)) s", comment: "Seconds value")
                    )
                }
            }

            Toggle(String(localized: "Flag ends the game", comment: "Setup field"), isOn: $rules.flagEndsGame)
        } header: {
            Text("Time control", comment: "Setup section")
        } footer: {
            Text(
                "Fischer adds the increment after every move. Bronstein returns only the time the move actually used, so a fast move can never bank time.",
                comment: "Increment explanation"
            )
        }
    }

    private func isSelected(_ option: (label: String, base: TimeInterval, increment: TimeInterval)) -> Bool {
        rules.baseTime == option.base && rules.incrementSeconds == option.increment
    }

    private var baseMinutes: Binding<Int> {
        Binding(
            get: { max(1, Int(rules.baseTime / 60)) },
            set: { rules.baseTime = TimeInterval($0 * 60) }
        )
    }

    private var incrementSeconds: Binding<Int> {
        Binding(
            get: { Int(rules.incrementSeconds) },
            set: { rules.incrementSeconds = TimeInterval($0) }
        )
    }

    private var detailsSection: some View {
        Section(String(localized: "Details", comment: "Setup section")) {
            TextField(String(localized: "Title", comment: "Setup field"), text: $title)
            TextField(String(localized: "Venue", comment: "Setup field"), text: $venue)
        }
    }

    private var themeSection: some View {
        Section(String(localized: "Theme", comment: "Setup section")) {
            ThemePickerRow(selection: $themeID)
        }
    }

    // MARK: Start

    private func start() {
        var configured = SpecialisedRules(board: .chessClock)
        configured.chessClock = rules

        let match = MatchBuilder.make(
            preset: preset,
            rules: .specialised(configured),
            title: title,
            venue: venue,
            themeID: themeID,
            attributionEnabled: false,
            sides: players,
            in: context
        )
        PresetPreferenceStore(context: context).markUsed(preset)
        runningStore = SpecialisedStore(match: match, context: context)
    }
}
