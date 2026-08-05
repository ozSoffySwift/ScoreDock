import SwiftData
import SwiftUI

/// Setup for rally-scored games (§4.1, §6.2).
///
/// Same contract as the team setup: a live preview at the top, every rule editable, nothing locked
/// — which is half the §8.5 mitigation for defaults that vary by league.
struct SetMatchSetupView: View {
    let preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var rules: SetMatchRules
    @State private var sides: [SideDraft] = SideDraft.defaults()
    @State private var title = ""
    @State private var venue = ""
    @State private var themeID: String
    @State private var runningStore: SetMatchStore?

    init(preset: GamePreset) {
        self.preset = preset
        _rules = State(initialValue: preset.rules.setMatchRules ?? SetMatchRules())
        _themeID = State(initialValue: preset.defaultThemeID)
    }

    private var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }
    private var isDarts: Bool { rules.notation == .dartsCountdown }
    private var isTennis: Bool { rules.notation == .tennis }

    var body: some View {
        Form {
            Section {
                SetMatchBoardView(
                    board: previewBoard,
                    sides: sides.map {
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

            Section(String(localized: "Sides", comment: "Setup section")) {
                ForEach($sides) { $side in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            EmojiField(emoji: $side.emoji)
                            TextField(
                                String(localized: "Side name", comment: "Setup field"),
                                text: $side.displayName
                            )
                            .textInputAutocapitalization(.words)
                        }
                        HStack(spacing: 10) {
                            TextField(
                                String(localized: "Short name", comment: "Setup field"),
                                text: $side.shortName
                            )
                            .textInputAutocapitalization(.characters)
                            .font(.caption)
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: side.colorHex) },
                                set: { side.colorHex = $0.resolvedHex }
                            ), supportsOpacity: false)
                            .labelsHidden()
                        }
                        if !teams.isEmpty {
                            Picker(
                                String(localized: "Saved team", comment: "Setup field"),
                                selection: Binding(
                                    get: { side.linkedTeam },
                                    set: { team in
                                        side.linkedTeam = team
                                        if let team {
                                            side.displayName = team.name
                                            side.shortName = team.shortName
                                            side.emoji = team.emoji
                                            side.colorHex = team.primaryColorHex
                                        }
                                    }
                                )
                            ) {
                                Text("None", comment: "No linked team").tag(nil as Team?)
                                ForEach(teams) { Text($0.name).tag($0 as Team?) }
                            }
                            .font(.caption)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section(String(localized: "Details", comment: "Setup section")) {
                TextField(String(localized: "Match title", comment: "Setup field"), text: $title)
                TextField(String(localized: "Venue", comment: "Setup field"), text: $venue)
            }

            scoringSection
            if !isDarts { tiebreakSection }
            if isDarts { dartsSection }
            serveSection
            themeSection

            Section {
                Button {
                    start()
                } label: {
                    Label(String(localized: "Start match", comment: "Setup action"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(sides.contains { $0.displayName.trimmingCharacters(in: .whitespaces).isEmpty })
            }
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $runningStore) { store in
            NavigationStack {
                SetMatchContainerView(store: store) { runningStore = nil }
            }
        }
    }

    // MARK: Sections

    private var scoringSection: some View {
        Section {
            Stepper(value: $rules.setsToWin, in: 1 ... 5) {
                LabeledContent(
                    String(localized: "Sets to win", comment: "Setup field"),
                    value: "\(rules.setsToWin)"
                )
            }

            if !isDarts {
                Stepper(value: $rules.pointsPerSet, in: 1 ... 50) {
                    LabeledContent(
                        isTennis
                            ? String(localized: "Games per set", comment: "Setup field")
                            : String(localized: "Points per set", comment: "Setup field"),
                        value: "\(rules.pointsPerSet)"
                    )
                }
                Stepper(value: $rules.decidingSetPoints, in: 1 ... 50) {
                    LabeledContent(
                        String(localized: "Deciding set", comment: "Setup field"),
                        value: "\(rules.decidingSetPoints)"
                    )
                }
                Toggle(String(localized: "Win by two", comment: "Setup field"), isOn: $rules.winByTwo)
                Stepper(value: hardCap, in: 0 ... 60) {
                    LabeledContent(
                        String(localized: "Hard cap", comment: "Setup field"),
                        value: rules.hardCap.map { "\($0)" }
                            ?? String(localized: "None", comment: "No hard cap")
                    )
                }
            }
        } header: {
            Text("Scoring", comment: "Setup section")
        } footer: {
            Text(
                "Rules vary by league — check yours. Everything here is editable and is saved with this match.",
                comment: "Rules disclaimer"
            )
        }
    }

    private var tiebreakSection: some View {
        Section {
            Toggle(String(localized: "Tiebreak", comment: "Setup field"), isOn: $rules.tiebreakEnabled)
            if rules.tiebreakEnabled {
                Stepper(value: $rules.tiebreakPoints, in: 3 ... 21) {
                    LabeledContent(
                        String(localized: "Tiebreak to", comment: "Setup field"),
                        value: "\(rules.tiebreakPoints)"
                    )
                }
            }
            if isTennis {
                Toggle(
                    String(localized: "Match tiebreak in deciding set", comment: "Setup field"),
                    isOn: $rules.matchTiebreak
                )
                if rules.matchTiebreak {
                    Stepper(value: $rules.matchTiebreakPoints, in: 5 ... 21) {
                        LabeledContent(
                            String(localized: "Match tiebreak to", comment: "Setup field"),
                            value: "\(rules.matchTiebreakPoints)"
                        )
                    }
                }
            }
        } header: {
            Text("Tiebreak", comment: "Setup section")
        }
    }

    private var dartsSection: some View {
        Section {
            Picker(String(localized: "Start score", comment: "Setup field"), selection: $rules.startScore) {
                Text("301").tag(301)
                Text("501").tag(501)
                Text("701").tag(701)
            }
            Stepper(value: $rules.legsPerSet, in: 1 ... 11) {
                LabeledContent(
                    String(localized: "Legs per set", comment: "Setup field"),
                    value: "\(rules.legsPerSet)"
                )
            }
            Toggle(String(localized: "Finish on a double", comment: "Setup field"), isOn: $rules.doubleOut)
        } header: {
            Text("Darts", comment: "Setup section")
        } footer: {
            Text(
                "A visit that goes past zero — or leaves one, when finishing on a double — busts and the score reverts.",
                comment: "Darts footer"
            )
        }
    }

    private var serveSection: some View {
        Section {
            Toggle(String(localized: "Track serve", comment: "Setup field"), isOn: $rules.serveTracking)
            if rules.serveTracking, !isDarts {
                Stepper(value: $rules.servesPerRotation, in: 1 ... 5) {
                    LabeledContent(
                        String(localized: "Serves each", comment: "Setup field"),
                        value: "\(rules.servesPerRotation)"
                    )
                }
            }
        } header: {
            Text("Serve", comment: "Setup section")
        } footer: {
            Text(
                "Set this to 1 and the winner of each rally serves. Set it higher and serve alternates every that many points, as in table tennis.",
                comment: "Serve footer"
            )
        }
    }

    private var themeSection: some View {
        Section {
            ThemePickerRow(selection: $themeID)
        } header: {
            Text("Theme", comment: "Setup section")
        }
    }

    // MARK: Helpers

    private var hardCap: Binding<Int> {
        Binding(
            get: { rules.hardCap ?? 0 },
            set: { rules.hardCap = $0 <= 0 ? nil : $0 }
        )
    }

    /// A representative board rather than an empty one — mid-set, so the layout is judged as it
    /// will actually look.
    private var previewBoard: DerivedSetMatchBoard {
        var state = SetMatchEngine.initialState(rules: rules, sideCount: sides.count)
        state.sides[0].setsWon = 1
        if isTennis {
            state.sides[0].gamesWon = 4
            state.sides[1].gamesWon = 3
            state.sides[0].points = 3
            state.sides[1].points = 2
        } else if isDarts {
            state.sides[0].remaining = 170
            state.sides[1].remaining = 301
            state.sides[0].legsWon = 1
        } else {
            state.sides[0].points = min(18, rules.pointsPerSet)
            state.sides[1].points = max(0, min(15, rules.pointsPerSet - 3))
        }
        state.completedSets = [[rules.pointsPerSet, max(0, rules.pointsPerSet - 4)]]
        return SetMatchEngine.derived(state, rules: rules, at: .now)
    }

    private func start() {
        let match = MatchBuilder.make(
            preset: preset,
            rules: .setMatch(rules),
            title: title,
            venue: venue,
            themeID: themeID,
            attributionEnabled: false,
            sides: sides,
            in: context
        )
        PresetPreferenceStore(context: context).markUsed(preset)
        runningStore = SetMatchStore(match: match, context: context)
    }
}
