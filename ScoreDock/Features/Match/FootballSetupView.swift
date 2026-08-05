import SwiftData
import SwiftUI

/// Setup for the American football board (§4.1, §6.3).
struct FootballSetupView: View {
    let preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var rules: AmericanFootballRules
    @State private var teams: [SideDraft]
    @State private var title = ""
    @State private var venue = ""
    @State private var themeID: String
    @State private var runningStore: SpecialisedStore?

    init(preset: GamePreset) {
        self.preset = preset
        _rules = State(initialValue: preset.rules.specialisedRules?.americanFootball ?? AmericanFootballRules())
        _themeID = State(initialValue: preset.defaultThemeID)
        _teams = State(initialValue: SideDraft.defaults())
    }

    private var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }

    var body: some View {
        Form {
            Section {
                FootballBoardView(
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
                .frame(height: 180)
                .clipShape(.rect(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            teamsSection
            clockSection
            rulesSection
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

    private var previewBoard: DerivedFootballBoard {
        var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)
        state.sides[0].score = 21
        state.sides[1].score = 17
        state.possessionSlot = 0
        state.down = 3
        state.yardsToGo = 7
        state.ballOn = 62
        return AmericanFootballEngine.derived(state, rules: rules, isFinished: false, at: .now)
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

    private var clockSection: some View {
        Section {
            Stepper(value: $rules.quarterCount, in: 1 ... 8) {
                LabeledContent(
                    String(localized: "Quarters", comment: "Setup field"),
                    value: "\(rules.quarterCount)"
                )
            }
            Stepper(value: quarterMinutes, in: 1 ... 30) {
                LabeledContent(
                    String(localized: "Quarter length", comment: "Setup field"),
                    value: String(localized: "\(Int(rules.quarterLength / 60)) min", comment: "Minutes value")
                )
            }
            Stepper(value: playClockNormal, in: 5 ... 60) {
                LabeledContent(
                    String(localized: "Play clock", comment: "Setup field"),
                    value: String(localized: "\(Int(rules.playClockNormal)) s", comment: "Seconds value")
                )
            }
            Stepper(value: playClockShort, in: 5 ... 60) {
                LabeledContent(
                    String(localized: "Short play clock", comment: "Setup field"),
                    value: String(localized: "\(Int(rules.playClockShort)) s", comment: "Seconds value")
                )
            }
        } header: {
            Text("Clocks", comment: "Setup section")
        } footer: {
            // §8.5: this preset's quarter length is one of the values still awaiting verification.
            Text(
                "15-minute quarters are the professional and college standard; high school plays 12. Check the code you are officiating.",
                comment: "Quarter length note"
            )
        }
    }

    private var rulesSection: some View {
        Section(String(localized: "Rules", comment: "Setup section")) {
            Stepper(value: $rules.timeoutsPerHalf, in: 0 ... 6) {
                LabeledContent(
                    String(localized: "Timeouts per half", comment: "Setup field"),
                    value: "\(rules.timeoutsPerHalf)"
                )
            }
            Stepper(value: $rules.downsToConvert, in: 3 ... 4) {
                LabeledContent(
                    String(localized: "Downs to convert", comment: "Setup field"),
                    value: "\(rules.downsToConvert)"
                )
            }
            Stepper(value: $rules.yardsToConvert, in: 1 ... 20) {
                LabeledContent(
                    String(localized: "Yards to convert", comment: "Setup field"),
                    value: "\(rules.yardsToConvert)"
                )
            }
        }
    }

    private var detailsSection: some View {
        Section(String(localized: "Details", comment: "Setup section")) {
            TextField(String(localized: "Title", comment: "Setup field"), text: $title)
            TextField(String(localized: "Venue", comment: "Setup field"), text: $venue)
        }
    }

    private var quarterMinutes: Binding<Int> {
        Binding(
            get: { max(1, Int(rules.quarterLength / 60)) },
            set: { rules.quarterLength = TimeInterval($0 * 60) }
        )
    }

    private var playClockNormal: Binding<Int> {
        Binding(get: { Int(rules.playClockNormal) }, set: { rules.playClockNormal = TimeInterval($0) })
    }

    private var playClockShort: Binding<Int> {
        Binding(get: { Int(rules.playClockShort) }, set: { rules.playClockShort = TimeInterval($0) })
    }

    // MARK: Start

    private func start() {
        var configured = SpecialisedRules(board: .americanFootball)
        configured.americanFootball = rules

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
