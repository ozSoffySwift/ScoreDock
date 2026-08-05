import SwiftData
import SwiftUI

/// Setup for list and table boards (§4.1, §6.5).
///
/// The one structural difference from the other setups: the number of participants is **variable**.
/// A leaderboard might have three people or thirty, so this screen adds and removes rows rather
/// than editing a fixed home and visitor.
struct ListSetupView: View {
    let preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Team.name) private var teams: [Team]
    @Query(sort: \Player.name) private var players: [Player]

    @State private var rules: ListRules
    @State private var participants: [SideDraft]
    @State private var title = ""
    @State private var venue = ""
    @State private var themeID: String
    @State private var runningStore: ListStore?

    /// Enough distinct colours that a full leaderboard stays legible without the operator having to
    /// pick every one by hand.
    private static let palette = [
        "#42A5F5", "#EF5350", "#66BB6A", "#FFA726", "#AB47BC", "#26C6DA",
        "#EC407A", "#9CCC65", "#FF7043", "#5C6BC0", "#FFCA28", "#78909C",
    ]

    init(preset: GamePreset) {
        self.preset = preset
        let listRules = preset.rules.listRules ?? ListRules()
        _rules = State(initialValue: listRules)
        _themeID = State(initialValue: preset.defaultThemeID)

        let count = listRules.style == .bracket
            ? min(listRules.bracketSize, 8)
            : max(2, listRules.participantCount)
        _participants = State(initialValue: (0 ..< count).map { index in
            SideDraft(
                displayName: Self.defaultName(index, style: listRules.style),
                colorHex: Self.palette[index % Self.palette.count]
            )
        })
    }

    private static func defaultName(_ index: Int, style: ListStyle) -> String {
        switch style {
        case .standings, .bracket:
            String(localized: "Team \(index + 1)", comment: "Default participant name")
        case .leaderboard, .scoreSheet:
            String(localized: "Player \(index + 1)", comment: "Default participant name")
        }
    }

    private var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }

    var body: some View {
        Form {
            Section {
                ListBoardView(
                    board: previewBoard,
                    sides: participants.map {
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
                .frame(height: 200)
                .clipShape(.rect(cornerRadius: 12))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            participantsSection
            detailsSection
            rulesSection
            themeSection

            Section {
                Button { start() } label: {
                    Label(String(localized: "Start", comment: "Setup action"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(participants.count < 2
                    || participants.contains { $0.displayName.trimmingCharacters(in: .whitespaces).isEmpty })
            }
        }
        .navigationTitle(preset.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $runningStore) { store in
            NavigationStack {
                ListContainerView(store: store) { runningStore = nil }
            }
        }
    }

    // MARK: Participants

    private var participantsSection: some View {
        Section {
            ForEach($participants) { $participant in
                HStack(spacing: 10) {
                    EmojiField(emoji: $participant.emoji)
                    TextField(
                        String(localized: "Name", comment: "Setup field"),
                        text: $participant.displayName
                    )
                    .textInputAutocapitalization(.words)
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: participant.colorHex) },
                        set: { participant.colorHex = $0.resolvedHex }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
            .onDelete { offsets in
                // Two is the floor: a table with one row is not a table.
                guard participants.count > 2 else { return }
                participants.remove(atOffsets: offsets)
            }

            Button {
                participants.append(SideDraft(
                    displayName: Self.defaultName(participants.count, style: rules.style),
                    colorHex: Self.palette[participants.count % Self.palette.count]
                ))
            } label: {
                Label(String(localized: "Add participant", comment: "Action"), systemImage: "plus")
            }
            .disabled(participants.count >= 32)

            if !savedNames.isEmpty {
                Menu {
                    ForEach(savedNames, id: \.name) { saved in
                        Button(saved.name) {
                            participants.append(SideDraft(
                                displayName: saved.name,
                                emoji: saved.emoji,
                                colorHex: saved.colorHex,
                                linkedTeam: saved.team,
                                linkedPlayer: saved.player
                            ))
                        }
                    }
                } label: {
                    Label(String(localized: "Add from Library", comment: "Action"), systemImage: "person.2")
                }
            }
        } header: {
            Text("Participants", comment: "Setup section")
        } footer: {
            Text("Swipe to remove. Two is the minimum.", comment: "Participants footer")
        }
    }

    private var detailsSection: some View {
        Section(String(localized: "Details", comment: "Setup section")) {
            TextField(String(localized: "Title", comment: "Setup field"), text: $title)
            TextField(String(localized: "Venue", comment: "Setup field"), text: $venue)
        }
    }

    // MARK: Rules, per style

    @ViewBuilder
    private var rulesSection: some View {
        switch rules.style {
        case .leaderboard:
            Section {
                Picker(String(localized: "Ranking", comment: "Setup field"), selection: $rules.higherIsBetter) {
                    Text("Highest first", comment: "Ranking direction").tag(true)
                    Text("Lowest first", comment: "Ranking direction").tag(false)
                }
                Toggle(
                    String(localized: "Ties share a rank", comment: "Setup field"),
                    isOn: $rules.sharedRanksOnTie
                )
            } header: {
                Text("Leaderboard", comment: "Setup section")
            } footer: {
                Text("Lowest first suits golf and race times.", comment: "Ranking footer")
            }

        case .standings:
            Section {
                Stepper(value: $rules.pointsForWin, in: 0 ... 10) {
                    LabeledContent(
                        String(localized: "Points for a win", comment: "Setup field"),
                        value: "\(rules.pointsForWin)"
                    )
                }
                Stepper(value: $rules.pointsForDraw, in: 0 ... 10) {
                    LabeledContent(
                        String(localized: "Points for a draw", comment: "Setup field"),
                        value: "\(rules.pointsForDraw)"
                    )
                }
                Stepper(value: $rules.pointsForLoss, in: 0 ... 10) {
                    LabeledContent(
                        String(localized: "Points for a loss", comment: "Setup field"),
                        value: "\(rules.pointsForLoss)"
                    )
                }
            } header: {
                Text("Points", comment: "Setup section")
            } footer: {
                Text(
                    "Three for a win is the association-football convention, not a rule — check your league.",
                    comment: "Standings points footer"
                )
            }

            Section(String(localized: "Columns", comment: "Setup section")) {
                ForEach(StandingsColumn.allCases, id: \.self) { column in
                    Toggle(column.shortLabel, isOn: binding(for: column))
                }
            }

        case .bracket:
            Section {
                Picker(String(localized: "Bracket size", comment: "Setup field"), selection: $rules.bracketSize) {
                    ForEach([4, 8, 16, 32], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Bracket", comment: "Setup section")
            } footer: {
                Text(
                    "Empty places become byes and advance on their own. \(participants.count) of \(rules.bracketSize) places filled.",
                    comment: "Bracket footer"
                )
            }

        case .scoreSheet:
            Section {
                Stepper(value: $rules.roundCount, in: 1 ... 30) {
                    LabeledContent(
                        String(localized: "Rounds", comment: "Setup field"),
                        value: "\(rules.roundCount)"
                    )
                }
                Picker(String(localized: "Ranking", comment: "Setup field"), selection: $rules.higherIsBetter) {
                    Text("Highest first", comment: "Ranking direction").tag(true)
                    Text("Lowest first", comment: "Ranking direction").tag(false)
                }
            } header: {
                Text("Score sheet", comment: "Setup section")
            } footer: {
                Text(
                    "Totals are always the sum of the rounds, so the two can never drift apart.",
                    comment: "Score sheet footer"
                )
            }
        }
    }

    /// Toggling a column keeps the canonical order rather than order-of-tapping — a table whose
    /// columns reshuffle as you configure it is disorienting.
    private func binding(for column: StandingsColumn) -> Binding<Bool> {
        Binding(
            get: { rules.columns.contains(column) },
            set: { isOn in
                if isOn {
                    guard !rules.columns.contains(column) else { return }
                    rules.columns = StandingsColumn.allCases.filter {
                        rules.columns.contains($0) || $0 == column
                    }
                } else {
                    rules.columns.removeAll { $0 == column }
                }
            }
        )
    }

    private var themeSection: some View {
        Section(String(localized: "Theme", comment: "Setup section")) {
            ThemePickerRow(selection: $themeID)
        }
    }

    // MARK: Library

    private struct SavedName {
        var name: String
        var emoji: String?
        var colorHex: String
        var team: Team?
        var player: Player?
    }

    /// Teams first for a league or a bracket, players first for a leaderboard or score sheet —
    /// whichever the board is actually about.
    private var savedNames: [SavedName] {
        let teamNames = teams.filter { !$0.isArchived }.map {
            SavedName(name: $0.name, emoji: $0.emoji, colorHex: $0.primaryColorHex, team: $0, player: nil)
        }
        let playerNames = players.filter { !$0.isArchived }.map {
            SavedName(
                name: $0.displayName,
                emoji: $0.emoji,
                colorHex: $0.colorHex ?? "#1E88E5",
                team: nil,
                player: $0
            )
        }
        return rules.style == .standings || rules.style == .bracket
            ? teamNames + playerNames
            : playerNames + teamNames
    }

    // MARK: Preview

    /// A representative table rather than an empty one — an all-zero preview says nothing about
    /// whether the layout works.
    private var previewBoard: DerivedListBoard {
        var state = ListEngine.initialState(rules: rules, sideCount: participants.count)
        for index in state.entries.indices {
            switch rules.style {
            case .leaderboard:
                state.entries[index].total = max(0, 40 - index * 7)
            case .standings:
                state.entries[index].won = max(0, 5 - index)
                state.entries[index].drawn = index % 2
                state.entries[index].lost = index
                state.entries[index].goalsFor = max(0, 14 - index * 3)
                state.entries[index].goalsAgainst = index * 3
            case .scoreSheet:
                state.entries[index].rounds = (0 ..< max(1, rules.roundCount)).map { round in
                    round <= 1 ? max(0, 12 - index * 3 - round) : 0
                }
                state.entries[index].total = state.entries[index].rounds.reduce(0, +)
            case .bracket:
                break
            }
        }
        if rules.style == .bracket, var bracket = state.bracket, !bracket.winners.isEmpty {
            bracket.winners[0] = 0
            state.bracket = bracket
        }
        return ListEngine.derived(state, rules: rules, at: .now)
    }

    private func start() {
        var configured = rules
        // The participant count is decided here, not in the preset, so it has to be carried into
        // the frozen rules snapshot.
        configured.participantCount = participants.count

        let match = MatchBuilder.make(
            preset: preset,
            rules: .list(configured),
            title: title,
            venue: venue,
            themeID: themeID,
            attributionEnabled: false,
            sides: participants,
            in: context
        )
        PresetPreferenceStore(context: context).markUsed(preset)
        runningStore = ListStore(match: match, context: context)
    }
}
