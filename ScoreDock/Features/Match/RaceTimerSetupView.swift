import SwiftData
import SwiftUI

/// Setup for the race timer (§4.1, §6.3).
///
/// The field is variable in size, like a leaderboard's, so this adds and removes racers rather than
/// editing a fixed home and visitor.
struct RaceTimerSetupView: View {
    let preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var rules: RaceTimerRules
    @State private var racers: [SideDraft]
    @State private var title = ""
    @State private var venue = ""
    @State private var themeID: String
    @State private var runningStore: SpecialisedStore?
    @State private var isFixedDistance: Bool

    private static let palette = [
        "#42A5F5", "#EF5350", "#66BB6A", "#FFA726", "#AB47BC", "#26C6DA",
        "#EC407A", "#9CCC65", "#FF7043", "#5C6BC0", "#FFCA28", "#78909C",
    ]

    init(preset: GamePreset) {
        self.preset = preset
        let raceRules = preset.rules.specialisedRules?.raceTimer ?? RaceTimerRules()
        _rules = State(initialValue: raceRules)
        _themeID = State(initialValue: preset.defaultThemeID)
        _isFixedDistance = State(initialValue: raceRules.lapCount != nil)
        _racers = State(initialValue: (0 ..< max(2, raceRules.racerCount)).map { index in
            SideDraft(
                displayName: String(localized: "Racer \(index + 1)", comment: "Default racer name"),
                colorHex: Self.palette[index % Self.palette.count]
            )
        })
    }

    private var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }

    var body: some View {
        Form {
            Section {
                RaceTimerBoardView(
                    board: previewBoard,
                    sides: racers.map {
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

            racersSection
            raceSection
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
                .disabled(racers.count < 1
                    || racers.contains { $0.displayName.trimmingCharacters(in: .whitespaces).isEmpty })
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

    private var previewBoard: DerivedRaceTimerBoard {
        var configured = rules
        configured.racerCount = racers.count
        let state = RaceTimerEngine.initialState(rules: configured, sideCount: racers.count)
        return RaceTimerEngine.derived(state, rules: configured, isFinished: false, at: .now)
    }

    // MARK: Sections

    private var racersSection: some View {
        Section(String(localized: "Racers", comment: "Setup section")) {
            ForEach($racers) { $racer in
                HStack(spacing: 10) {
                    EmojiField(emoji: $racer.emoji)
                    TextField(String(localized: "Name", comment: "Setup field"), text: $racer.displayName)
                        .textInputAutocapitalization(.words)
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: racer.colorHex) },
                        set: { racer.colorHex = $0.resolvedHex }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
            .onDelete { offsets in
                guard racers.count > 1 else { return }
                racers.remove(atOffsets: offsets)
            }

            Button {
                racers.append(SideDraft(
                    displayName: String(localized: "Racer \(racers.count + 1)", comment: "Default racer name"),
                    colorHex: Self.palette[racers.count % Self.palette.count]
                ))
            } label: {
                Label(String(localized: "Add racer", comment: "Action"), systemImage: "plus")
            }
        }
    }

    private var raceSection: some View {
        Section {
            Toggle(String(localized: "Fixed number of laps", comment: "Setup field"), isOn: $isFixedDistance)

            if isFixedDistance {
                Stepper(value: lapCount, in: 1 ... 200) {
                    LabeledContent(
                        String(localized: "Laps", comment: "Setup field"),
                        value: "\(rules.lapCount ?? 1)"
                    )
                }
            }

            Toggle(String(localized: "Fastest time wins", comment: "Setup field"), isOn: $rules.lowerTimeWins)
        } header: {
            Text("Race", comment: "Setup section")
        } footer: {
            Text(
                isFixedDistance
                    ? String(localized: "A racer finishes automatically on their final lap.", comment: "Race setup footer")
                    : String(localized: "Long-press a racer on the board to finish them.", comment: "Race setup footer")
            )
        }
        .onChange(of: isFixedDistance) { _, fixed in
            rules.lapCount = fixed ? (rules.lapCount ?? 4) : nil
        }
    }

    private var lapCount: Binding<Int> {
        Binding(
            get: { rules.lapCount ?? 1 },
            set: { rules.lapCount = $0 }
        )
    }

    private var detailsSection: some View {
        Section(String(localized: "Details", comment: "Setup section")) {
            TextField(String(localized: "Title", comment: "Setup field"), text: $title)
            TextField(String(localized: "Venue", comment: "Setup field"), text: $venue)
        }
    }

    // MARK: Start

    private func start() {
        var configured = SpecialisedRules(board: .raceTimer)
        var raceRules = rules
        // The field size is decided here, not in the preset, so it has to be carried into the
        // frozen rules snapshot.
        raceRules.racerCount = racers.count
        configured.raceTimer = raceRules

        let match = MatchBuilder.make(
            preset: preset,
            rules: .specialised(configured),
            title: title,
            venue: venue,
            themeID: themeID,
            attributionEnabled: false,
            sides: racers,
            in: context
        )
        PresetPreferenceStore(context: context).markUsed(preset)
        runningStore = SpecialisedStore(match: match, context: context)
    }
}
