import SwiftData
import SwiftUI

/// Setup for the baseball board (§4.1, §6.3).
struct BaseballSetupView: View {
    let preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var rules: BaseballRules
    @State private var teams: [SideDraft]
    @State private var title = ""
    @State private var venue = ""
    @State private var themeID: String
    @State private var runningStore: SpecialisedStore?

    init(preset: GamePreset) {
        self.preset = preset
        _rules = State(initialValue: preset.rules.specialisedRules?.baseball ?? BaseballRules())
        _themeID = State(initialValue: preset.defaultThemeID)
        _teams = State(initialValue: [
            SideDraft(displayName: String(localized: "Home", comment: "Baseball side"), colorHex: "#42A5F5"),
            SideDraft(displayName: String(localized: "Visitors", comment: "Baseball side"), colorHex: "#EF5350"),
        ])
    }

    private var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }

    var body: some View {
        Form {
            Section {
                BaseballBoardView(
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
                .frame(height: 210)
                .clipShape(.rect(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            teamsSection
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

    private var previewBoard: DerivedBaseballBoard {
        var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
        state.sides[1].runsByInning = [0, 2, 0, 0, 1]
        state.sides[0].runsByInning = [1, 0, 0, 3]
        state.sides[1].hits = 7
        state.sides[0].hits = 9
        state.sides[0].errors = 1
        state.inning = 5
        state.isTop = false
        state.balls = 2
        state.strikes = 1
        state.outs = 1
        state.bases = BaseOccupancy(first: true, second: false, third: true)
        return BaseballEngine.derived(state, rules: rules, isFinished: false, at: .now)
    }

    // MARK: Sections

    private var teamsSection: some View {
        Section {
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
        } header: {
            Text("Teams", comment: "Setup section")
        } footer: {
            Text("The visitors bat the top of each inning; the home side bats the bottom.", comment: "Baseball teams footer")
        }
    }

    private var rulesSection: some View {
        Section(String(localized: "Rules", comment: "Setup section")) {
            Stepper(value: $rules.inningCount, in: 1 ... 15) {
                LabeledContent(
                    String(localized: "Innings", comment: "Setup field"),
                    value: "\(rules.inningCount)"
                )
            }
            Stepper(value: $rules.outsPerHalfInning, in: 1 ... 6) {
                LabeledContent(
                    String(localized: "Outs per half-inning", comment: "Setup field"),
                    value: "\(rules.outsPerHalfInning)"
                )
            }
            Stepper(value: $rules.strikesPerOut, in: 1 ... 5) {
                LabeledContent(
                    String(localized: "Strikes per out", comment: "Setup field"),
                    value: "\(rules.strikesPerOut)"
                )
            }
            Stepper(value: $rules.ballsPerWalk, in: 1 ... 6) {
                LabeledContent(
                    String(localized: "Balls per walk", comment: "Setup field"),
                    value: "\(rules.ballsPerWalk)"
                )
            }
            Toggle(String(localized: "Show hits and errors", comment: "Setup field"), isOn: $rules.showHitsAndErrors)
            Toggle(String(localized: "Allow extra innings", comment: "Setup field"), isOn: $rules.allowsExtraInnings)
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
        var configured = SpecialisedRules(board: .baseball)
        configured.baseball = rules

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
