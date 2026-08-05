import SwiftData
import SwiftUI

/// Setup for the cricket board (§4.1, §6.3).
///
/// Format leads, because in cricket it decides almost everything else — a T20 is twenty overs and
/// one innings a side, an ODI fifty, a Test unlimited overs and two. Picking one moves the rest, and
/// every value stays editable underneath (§8.5).
struct CricketSetupView: View {
    let preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var rules: CricketRules
    @State private var teams: [SideDraft]
    @State private var title = ""
    @State private var venue = ""
    @State private var themeID: String
    @State private var runningStore: SpecialisedStore?

    init(preset: GamePreset) {
        self.preset = preset
        _rules = State(initialValue: preset.rules.specialisedRules?.cricket ?? CricketRules())
        _themeID = State(initialValue: preset.defaultThemeID)
        _teams = State(initialValue: SideDraft.defaults())
    }

    private var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }

    var body: some View {
        Form {
            Section {
                CricketBoardView(
                    board: previewBoard,
                    sides: teams.map {
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
                .frame(height: 190)
                .clipShape(.rect(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            teamsSection
            formatSection
            detailsSection

            Section(String(localized: "Theme", comment: "Setup section")) {
                ThemePickerRow(selection: $themeID)
            }

            Section {
                Button { start() } label: {
                    Label(String(localized: "Start", comment: "Setup action"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(teams.contains { $0.displayName.trimmingCharacters(in: .whitespaces).isEmpty })
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

    private var previewBoard: DerivedCricketBoard {
        var state = CricketEngine.initialState(rules: rules, sideCount: 2)
        state.innings[0].runs = 84
        state.innings[0].wickets = 2
        state.innings[0].legalBalls = 58
        state.innings[0].extras = 6
        state.innings[0].partnership = 31
        return CricketEngine.derived(state, rules: rules, sideCount: 2, isFinished: false, at: .now)
    }

    // MARK: Sections

    private var teamsSection: some View {
        Section(String(localized: "Teams", comment: "Setup section")) {
            ForEach($teams) { $team in
                HStack(spacing: 10) {
                    EmojiField(emoji: $team.emoji)
                    TextField(String(localized: "Name", comment: "Setup field"), text: $team.displayName)
                        .textInputAutocapitalization(.words)
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: team.colorHex) },
                        set: { team.colorHex = $0.resolvedHex }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
        }
    }

    private var formatSection: some View {
        Section {
            Picker(String(localized: "Format", comment: "Setup field"), selection: $rules.format) {
                Text("T20", comment: "Cricket format").tag(CricketRules.Format.t20)
                Text("ODI", comment: "Cricket format").tag(CricketRules.Format.odi)
                Text("Test", comment: "Cricket format").tag(CricketRules.Format.test)
            }
            .pickerStyle(.segmented)
            .onChange(of: rules.format) { _, format in
                // Moving the format moves the values it implies; everything stays editable below.
                switch format {
                case .t20: rules.oversPerInnings = 20; rules.inningsPerSide = 1
                case .odi: rules.oversPerInnings = 50; rules.inningsPerSide = 1
                case .test: rules.oversPerInnings = 0; rules.inningsPerSide = 2
                }
            }

            if rules.format != .test {
                Stepper(value: $rules.oversPerInnings, in: 1 ... 100) {
                    LabeledContent(
                        String(localized: "Overs per innings", comment: "Setup field"),
                        value: "\(rules.oversPerInnings)"
                    )
                }
            }

            Stepper(value: $rules.ballsPerOver, in: 1 ... 12) {
                LabeledContent(
                    String(localized: "Balls per over", comment: "Setup field"),
                    value: "\(rules.ballsPerOver)"
                )
            }

            Stepper(value: $rules.wicketsPerInnings, in: 1 ... 11) {
                LabeledContent(
                    String(localized: "Wickets", comment: "Setup field"),
                    value: "\(rules.wicketsPerInnings)"
                )
            }

            Stepper(value: $rules.inningsPerSide, in: 1 ... 2) {
                LabeledContent(
                    String(localized: "Innings each", comment: "Setup field"),
                    value: "\(rules.inningsPerSide)"
                )
            }

            Toggle(String(localized: "Show run rate", comment: "Setup field"), isOn: $rules.showRunRate)
            Toggle(String(localized: "Show required rate", comment: "Setup field"), isOn: $rules.showRequiredRate)
        } header: {
            Text("Format", comment: "Setup section")
        } footer: {
            Text(
                "A Test has no over limit, so the innings ends on wickets or a declaration.",
                comment: "Cricket format footer"
            )
        }
    }

    private var detailsSection: some View {
        Section(String(localized: "Details", comment: "Setup section")) {
            TextField(String(localized: "Title", comment: "Setup field"), text: $title)
            TextField(String(localized: "Venue", comment: "Setup field"), text: $venue)
        }
    }

    // MARK: Start

    private func start() {
        var configured = SpecialisedRules(board: .cricket)
        configured.cricket = rules

        let match = MatchBuilder.make(
            preset: preset,
            rules: .specialised(configured),
            title: title,
            venue: venue,
            themeID: themeID,
            attributionEnabled: false,
            sides: teams,
            in: context
        )
        PresetPreferenceStore(context: context).markUsed(preset)
        runningStore = SpecialisedStore(match: match, context: context)
    }
}
