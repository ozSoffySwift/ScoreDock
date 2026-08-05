import SwiftData
import SwiftUI

/// Player leaders · team records · head-to-head (§3).
///
/// Stats are computed by aggregating `Match` + `MatchSide` + `ScoreEvent` on demand — there are no
/// denormalised stats tables in v1, because those are the classic source of drift and the
/// denormalised fields already on `MatchSide` make the common queries cheap (§7.2).
struct StatsView: View {
    @Query private var matches: [Match]

    @State private var leftKey: String?
    @State private var rightKey: String?

    private var records: [CompetitorRecord] { StatsAggregator.competitorRecords(from: matches) }
    private var players: [PlayerRecord] { StatsAggregator.playerRecords(from: matches) }
    private var finishedCount: Int { StatsAggregator.completed(matches).count }

    var body: some View {
        NavigationStack {
            Group {
                if finishedCount == 0 {
                    ContentUnavailableView(
                        String(localized: "No stats yet", comment: "Empty stats title"),
                        systemImage: "chart.bar",
                        description: Text(
                            "Once you finish a match, records and head-to-head history build up here automatically.",
                            comment: "Empty stats description"
                        )
                    )
                } else {
                    content
                }
            }
            .navigationTitle(Text("Stats", comment: "Stats title"))
        }
    }

    private var content: some View {
        List {
            Section {
                LabeledContent(
                    String(localized: "Matches played", comment: "Stat label"),
                    value: "\(finishedCount)"
                )
                if let most = StatsAggregator.mostPlayedPreset(from: matches) {
                    LabeledContent(String(localized: "Most played", comment: "Stat label")) {
                        Text(BuiltInCatalog.bySlug[most.slug]?.name ?? most.slug)
                    }
                }
            }

            Section(String(localized: "Team records", comment: "Stats section")) {
                ForEach(records) { record in
                    RecordRow(record: record)
                }
            }

            if !players.isEmpty {
                Section {
                    ForEach(players) { player in
                        LabeledContent(player.name) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(player.points)").monospacedDigit()
                                Text(
                                    "\(player.averagePoints, format: .number.precision(.fractionLength(1))) avg",
                                    comment: "Player average"
                                )
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Player leaders", comment: "Stats section")
                } footer: {
                    Text(
                        "From matches where you credited points to players.",
                        comment: "Player leaders footer"
                    )
                }
            }

            if records.count >= 2 {
                headToHeadSection
            }
        }
    }

    private var headToHeadSection: some View {
        Section {
            Picker(String(localized: "First", comment: "Head to head picker"), selection: $leftKey) {
                ForEach(records) { Text($0.name).tag($0.id as String?) }
            }
            Picker(String(localized: "Second", comment: "Head to head picker"), selection: $rightKey) {
                ForEach(records) { Text($0.name).tag($0.id as String?) }
            }

            if let left = leftKey, let right = rightKey, left != right {
                let result = StatsAggregator.headToHead(left, right, from: matches)
                if result.meetings == 0 {
                    Text("These two have not met yet.", comment: "Head to head empty")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    LabeledContent(String(localized: "Meetings", comment: "Stat label"), value: "\(result.meetings)")
                    LabeledContent(name(for: left), value: "\(result.leftWins)")
                    LabeledContent(name(for: right), value: "\(result.rightWins)")
                    if result.draws > 0 {
                        LabeledContent(String(localized: "Draws", comment: "Stat label"), value: "\(result.draws)")
                    }
                }
            }
        } header: {
            Text("Head to head", comment: "Stats section")
        }
        .onAppear {
            leftKey = leftKey ?? records.first?.id
            rightKey = rightKey ?? records.dropFirst().first?.id
        }
    }

    private func name(for key: String) -> String {
        records.first { $0.id == key }?.name ?? key
    }
}

private struct RecordRow: View {
    var record: CompetitorRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if let emoji = record.emoji, !emoji.isEmpty {
                    Text(emoji)
                }
                Text(record.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: record.colorHex))
                Spacer(minLength: 0)
                Text("\(record.won)–\(record.drawn)–\(record.lost)")
                    .font(.subheadline.monospacedDigit())
            }
            HStack(spacing: 12) {
                Text("\(record.played) played", comment: "Record detail")
                Text("\(record.winRate, format: .percent.precision(.fractionLength(0))) wins", comment: "Record detail")
                if record.pointsDifference != 0 {
                    Text(record.pointsDifference > 0
                        ? "+\(record.pointsDifference)"
                        : "\(record.pointsDifference)")
                }
                if record.longestWinStreak > 1 {
                    Text("\(record.longestWinStreak) in a row", comment: "Record detail")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    StatsView()
        .modelContainer(try! AppModelContainer.make(inMemory: true))
}
