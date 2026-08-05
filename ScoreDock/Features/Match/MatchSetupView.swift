import SwiftData
import SwiftUI

/// Configure the board before the whistle (§4.1).
///
/// Every preset parameter is editable and nothing is locked — which is half of the §8.5 mitigation
/// for rule defaults that vary by league. A live preview sits at the top and updates as settings
/// change, so the operator sees the board they are about to run.
struct MatchSetupView: View {
    let preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Team.name) private var teams: [Team]

    @State private var rules: TeamRules
    @State private var sides: [SideDraft] = SideDraft.defaults()
    @State private var title = ""
    @State private var venue = ""
    @State private var themeID: String
    @State private var attributionEnabled = false
    @State private var runningStore: LiveMatchStore?

    init(preset: GamePreset) {
        self.preset = preset
        _rules = State(initialValue: preset.rules.teamRules ?? TeamRules())
        _themeID = State(initialValue: preset.defaultThemeID)
    }

    private var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }

    var body: some View {
        Form {
            previewSection
            sidesSection
            detailsSection
            clockSection
            if rules.foulTrackingEnabled || rules.timeoutCount > 0 { infractionSection }
            shotClockSection
            themeSection
            attributionSection
            startSection
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $runningStore) { store in
            NavigationStack {
                MatchContainerView(store: store) { runningStore = nil }
            }
        }
    }

    // MARK: Preview

    private var previewSection: some View {
        Section {
            ScoreboardView(
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
            .frame(height: 170)
            .clipShape(.rect(cornerRadius: 12))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// A representative board rather than an empty one — an all-zero preview tells you nothing
    /// about whether the layout works.
    private var previewBoard: DerivedBoard {
        var state = TeamEngine.initialState(rules: rules, sideCount: sides.count)
        state.sides[0].score = rules.scoreIncrements.contains(3) ? 68 : 2
        if state.sides.count > 1 {
            state.sides[1].score = rules.scoreIncrements.contains(3) ? 64 : 1
        }
        state.sides[0].fouls = 3
        state.period = min(2, rules.periodCount)
        if rules.possessionArrowEnabled { state.possessionSlot = 0 }
        return TeamEngine.derived(state, rules: rules, at: .now)
    }

    // MARK: Sides

    private var sidesSection: some View {
        Section {
            ForEach($sides) { $side in
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        // Identity mark control sits beside the name field (§4.1). Image upload
                        // and saved-player linking arrive with the Library in M3.
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
                        ColorPicker("", selection: sideColor($side), supportsOpacity: false)
                            .labelsHidden()
                    }
                    if !teams.isEmpty {
                        Picker(
                            String(localized: "Saved team", comment: "Setup field"),
                            selection: linkedTeam($side)
                        ) {
                            Text("None", comment: "No linked team").tag(nil as Team?)
                            ForEach(teams) { team in
                                Text(team.name).tag(team as Team?)
                            }
                        }
                        .font(.caption)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Sides", comment: "Setup section")
        }
    }

    private func sideColor(_ side: Binding<SideDraft>) -> Binding<Color> {
        Binding(
            get: { Color(hex: side.wrappedValue.colorHex) },
            set: { side.wrappedValue.colorHex = $0.resolvedHex }
        )
    }

    private func linkedTeam(_ side: Binding<SideDraft>) -> Binding<Team?> {
        Binding(
            get: { side.wrappedValue.linkedTeam },
            set: { team in
                side.wrappedValue.linkedTeam = team
                // Prefill from the team, which is what the linking is for.
                if let team {
                    side.wrappedValue.displayName = team.name
                    side.wrappedValue.shortName = team.shortName
                    side.wrappedValue.emoji = team.emoji
                    side.wrappedValue.colorHex = team.primaryColorHex
                }
            }
        )
    }

    // MARK: Match details

    private var detailsSection: some View {
        Section {
            TextField(String(localized: "Match title", comment: "Setup field"), text: $title)
            TextField(String(localized: "Venue", comment: "Setup field"), text: $venue)
        } header: {
            Text("Details", comment: "Setup section")
        } footer: {
            Text("Optional. Both appear on the shared match report.", comment: "Setup footer")
        }
    }

    // MARK: Rules

    private var clockSection: some View {
        Section {
            Stepper(value: $rules.periodCount, in: 1 ... 20) {
                LabeledContent(
                    String(localized: "Periods", comment: "Setup field"),
                    value: "\(rules.periodCount)"
                )
            }
            Stepper(value: periodMinutes, in: 0 ... 120) {
                LabeledContent(
                    String(localized: "Period length", comment: "Setup field"),
                    value: RuleSummary.duration(rules.periodLength)
                )
            }
            Picker(String(localized: "Clock", comment: "Setup field"), selection: $rules.countsUp) {
                Text("Counts down", comment: "Clock direction").tag(false)
                Text("Counts up", comment: "Clock direction").tag(true)
            }
            Toggle(String(localized: "Show tenths near the end", comment: "Setup field"), isOn: $rules.showTenths)
            Stepper(value: breakMinutes, in: 0 ... 60) {
                LabeledContent(
                    String(localized: "Break", comment: "Setup field"),
                    value: RuleSummary.duration(rules.breakDuration)
                )
            }
        } header: {
            Text("Clock", comment: "Setup section")
        } footer: {
            // §8.5: shown so an operator never assumes our defaults are their league's.
            Text(
                "Rules vary by league — check yours. Everything here is editable and is saved with this match.",
                comment: "Rules disclaimer"
            )
        }
    }

    private var infractionSection: some View {
        Section {
            Toggle(String(localized: "Track fouls", comment: "Setup field"), isOn: $rules.foulTrackingEnabled)
            if rules.foulTrackingEnabled {
                Stepper(value: $rules.foulLimit, in: 0 ... 20) {
                    LabeledContent(
                        String(localized: "Foul limit", comment: "Setup field"),
                        value: "\(rules.foulLimit)"
                    )
                }
                Stepper(value: bonusThreshold, in: 0 ... 20) {
                    LabeledContent(
                        String(localized: "Bonus at", comment: "Setup field"),
                        value: rules.bonusThreshold.map { "\($0)" }
                            ?? String(localized: "Off", comment: "Bonus disabled")
                    )
                }
                Toggle(
                    String(localized: "Fouls reset each period", comment: "Setup field"),
                    isOn: $rules.foulsResetPerPeriod
                )
            }
            Stepper(value: $rules.timeoutCount, in: 0 ... 12) {
                LabeledContent(
                    String(localized: "Timeouts", comment: "Setup field"),
                    value: "\(rules.timeoutCount)"
                )
            }
            if rules.timeoutCount > 0 {
                Toggle(
                    String(localized: "Timeouts reset at half", comment: "Setup field"),
                    isOn: $rules.timeoutsResetAtHalf
                )
            }
        } header: {
            Text("Fouls & timeouts", comment: "Setup section")
        }
    }

    private var shotClockSection: some View {
        Section {
            Toggle(String(localized: "Shot clock", comment: "Setup field"), isOn: $rules.shotClockEnabled)
            if rules.shotClockEnabled {
                Stepper(value: $rules.shotClockFull, in: 5 ... 60, step: 1) {
                    LabeledContent(
                        String(localized: "Full reset", comment: "Setup field"),
                        value: "\(Int(rules.shotClockFull))s"
                    )
                }
                Stepper(value: $rules.shotClockShort, in: 5 ... 60, step: 1) {
                    LabeledContent(
                        String(localized: "Short reset", comment: "Setup field"),
                        value: "\(Int(rules.shotClockShort))s"
                    )
                }
            }
            Toggle(
                String(localized: "Possession arrow", comment: "Setup field"),
                isOn: $rules.possessionArrowEnabled
            )
        } header: {
            Text("Shot clock & possession", comment: "Setup section")
        }
    }

    private var themeSection: some View {
        Section {
            ThemePickerRow(selection: $themeID)
        } header: {
            Text("Theme", comment: "Setup section")
        }
    }

    private var attributionSection: some View {
        Section {
            Toggle(
                String(localized: "Credit points to players", comment: "Setup field"),
                isOn: $attributionEnabled
            )
        } footer: {
            // Off by default: with it off a score is one tap and nothing else, which is what a
            // referee running a clock needs (§4.1, §4.2).
            Text(
                "Off by default, so scoring stays one tap. Turn it on and each score asks who gets the credit — link a side to a saved team above so its roster is there to pick from.",
                comment: "Attribution footer"
            )
        }
    }

    private var startSection: some View {
        Section {
            Button {
                start()
            } label: {
                Label(
                    String(localized: "Start match", comment: "Setup action"),
                    systemImage: "play.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(sides.contains { $0.displayName.trimmingCharacters(in: .whitespaces).isEmpty })
        }
    }

    // MARK: Bindings and actions

    private var periodMinutes: Binding<Int> {
        Binding(
            get: { Int(rules.periodLength / 60) },
            set: { rules.periodLength = TimeInterval($0 * 60) }
        )
    }

    private var breakMinutes: Binding<Int> {
        Binding(
            get: { Int(rules.breakDuration / 60) },
            set: { rules.breakDuration = TimeInterval($0 * 60) }
        )
    }

    private var bonusThreshold: Binding<Int> {
        Binding(
            get: { rules.bonusThreshold ?? 0 },
            set: { rules.bonusThreshold = $0 <= 0 ? nil : $0 }
        )
    }

    private func start() {
        let match = MatchBuilder.make(
            preset: preset,
            rules: .team(rules),
            title: title,
            venue: venue,
            themeID: themeID,
            attributionEnabled: attributionEnabled,
            sides: sides,
            in: context
        )
        PresetPreferenceStore(context: context).markUsed(preset)
        runningStore = LiveMatchStore(match: match, context: context)
    }
}

/// Single-emoji entry, validated per §7.1a so the field cannot become a second name field.
struct EmojiField: View {
    @Binding var emoji: String?
    @State private var text = ""

    var body: some View {
        TextField("🙂", text: $text)
            .frame(width: 44)
            .multilineTextAlignment(.center)
            .font(.title3)
            .onChange(of: text) { _, newValue in
                emoji = EmojiInput.validated(newValue)
                text = emoji ?? ""
            }
            .onAppear { text = emoji ?? "" }
            .accessibilityLabel(Text("Side emoji", comment: "Accessibility"))
    }
}

