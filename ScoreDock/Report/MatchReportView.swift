import SwiftData
import SwiftUI

/// The Match Report (§13.4).
///
/// Presented at the final whistle, and reachable forever from History. It never expires.
struct MatchReportView: View {
    @Bindable var match: Match

    @Environment(AppSettings.self) private var settings
    @State private var filter: TimelineFilter = .all
    @State private var showingShare = false

    private var model: MatchExportModel {
        MatchExportBuilder.build(match, options: ExportOptions(includeWatermark: settings.shareWatermark))
    }

    enum TimelineFilter: Hashable {
        case all
        case scoresOnly
        case side(Int)
        case player(String)
    }

    var body: some View {
        let model = model

        List {
            headerSection(model)
            if !model.summary.periodLines.isEmpty { periodSection(model) }
            statsSection(model)
            if match.attributionEnabled, !model.summary.playerTotals.isEmpty { playerSection(model) }
            notesSection
            timelineSection(model)
        }
        .navigationTitle(Text("Match report", comment: "Report title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingShare = true
                } label: {
                    Label(String(localized: "Share", comment: "Action"), systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            MatchShareSheet(match: match)
        }
    }

    // MARK: Sections

    private func headerSection(_ model: MatchExportModel) -> some View {
        Section {
            ShareCardPreview(model: model, font: settings.boardFont)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }
    }

    private func periodSection(_ model: MatchExportModel) -> some View {
        Section(String(localized: "By period", comment: "Report section")) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(model.summary.periodLines) { line in
                        Text("P\(line.period)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Text("Total", comment: "Period table total")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(model.sides, id: \.slotIndex) { side in
                    GridRow {
                        Text(side.shortName.isEmpty ? side.name : side.shortName)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        ForEach(model.summary.periodLines) { line in
                            Text("\(line.scores.indices.contains(side.slotIndex) ? line.scores[side.slotIndex] : 0)")
                                .font(.subheadline.monospacedDigit())
                        }
                        Text("\(side.finalScore)")
                            .font(.subheadline.weight(.bold).monospacedDigit())
                    }
                }
            }
        }
    }

    private func statsSection(_ model: MatchExportModel) -> some View {
        Section(String(localized: "Summary", comment: "Report section")) {
            LabeledContent(
                String(localized: "Scoring plays", comment: "Stat"),
                value: "\(model.summary.scoringPlays)"
            )
            if model.summary.leadChanges > 0 {
                LabeledContent(
                    String(localized: "Lead changes", comment: "Stat"),
                    value: "\(model.summary.leadChanges)"
                )
            }
            if let lead = model.summary.largestLead, lead.margin > 0 {
                LabeledContent(String(localized: "Largest lead", comment: "Stat")) {
                    Text("\(name(lead.slotIndex, in: model)) +\(lead.margin)")
                }
            }
            if let run = model.summary.longestRun, run.points > 1 {
                LabeledContent(String(localized: "Longest run", comment: "Stat")) {
                    Text("\(name(run.slotIndex, in: model)) \(run.points)")
                }
            }
            ForEach(model.sides, id: \.slotIndex) { side in
                let time = model.summary.timeInLead.indices.contains(side.slotIndex)
                    ? model.summary.timeInLead[side.slotIndex]
                    : 0
                if time > 0 {
                    LabeledContent(
                        String(localized: "\(side.name) led for", comment: "Stat"),
                        value: ClockDisplay.format(time, showsTenths: false)
                    )
                }
            }
        }
    }

    private func playerSection(_ model: MatchExportModel) -> some View {
        // Shown only when attribution was on for this match (§13.4).
        let totals = Dictionary(
            model.timeline.compactMap { entry -> (String, Int)? in
                guard entry.kind == .score, !entry.isUndone, entry.value > 0,
                      let player = entry.playerName else { return nil }
                return (player, entry.value)
            },
            uniquingKeysWith: +
        )

        return Section(String(localized: "Scorers", comment: "Report section")) {
            ForEach(totals.sorted { $0.value > $1.value }, id: \.key) { name, points in
                LabeledContent(name, value: "\(points)")
            }
        }
    }

    private var notesSection: some View {
        Section {
            TextField(
                String(localized: "Add a note before sharing", comment: "Report notes field"),
                text: Binding($match.notes, replacingNilWith: ""),
                axis: .vertical
            )
            .lineLimit(2 ... 6)
        } header: {
            Text("Notes", comment: "Report section")
        }
    }

    private func timelineSection(_ model: MatchExportModel) -> some View {
        let entries = filtered(model)

        return Section {
            Picker(String(localized: "Show", comment: "Timeline filter"), selection: $filter) {
                Text("All events", comment: "Timeline filter").tag(TimelineFilter.all)
                Text("Scores only", comment: "Timeline filter").tag(TimelineFilter.scoresOnly)
                ForEach(model.sides, id: \.slotIndex) { side in
                    Text(side.name).tag(TimelineFilter.side(side.slotIndex))
                }
            }
            .pickerStyle(.menu)

            if entries.isEmpty {
                Text("Nothing to show for this filter.", comment: "Empty timeline")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    TimelineRow(entry: entry)
                }
            }
        } header: {
            Text("Play by play", comment: "Report section")
        } footer: {
            Text(
                "Every action is stamped with both the time of day and the game clock, so this lines up against video afterwards.",
                comment: "Timeline footer"
            )
        }
    }

    private func filtered(_ model: MatchExportModel) -> [MatchExportModel.Entry] {
        switch filter {
        case .all: model.timeline
        case .scoresOnly: model.timeline.filter { $0.kind == .score }
        case let .side(slot): model.timeline.filter { $0.slotIndex == slot }
        case let .player(name): model.timeline.filter { $0.playerName == name }
        }
    }

    private func name(_ slot: Int, in model: MatchExportModel) -> String {
        model.sides.first { $0.slotIndex == slot }?.name ?? "—"
    }
}

private struct TimelineRow: View {
    var entry: MatchExportModel.Entry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ClockDisplay.format(entry.matchClock, showsTenths: false))
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text("P\(entry.period)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 52, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.subheadline)
                    // §13.3: undo does not erase history. It is shown struck through, because the
                    // log's job is to tell the truth about what the operator did.
                    .strikethrough(entry.isUndone)
                    .foregroundStyle(entry.isUndone ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    if let player = entry.playerName {
                        Text("·")
                        Text(player)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var headline: String {
        switch entry.kind {
        case .score:
            let side = entry.sideName ?? ""
            return entry.value >= 0 ? "\(side) +\(entry.value)" : "\(side) \(entry.value)"
        case .foul:
            return String(localized: "\(entry.sideName ?? "") foul", comment: "Timeline event")
        case .timeout:
            return String(localized: "\(entry.sideName ?? "") timeout", comment: "Timeline event")
        case .periodAdvance:
            return entry.value < 0
                ? String(localized: "Back a period", comment: "Timeline event")
                : String(localized: "Period advanced", comment: "Timeline event")
        case .periodLabel:
            return String(localized: "Period label changed", comment: "Timeline event")
        case .possession:
            return String(localized: "Possession", comment: "Timeline event")
        case .shotClockReset:
            return String(localized: "Shot clock reset", comment: "Timeline event")
        case .shotClockToggle:
            return String(localized: "Shot clock", comment: "Timeline event")
        case .breakStart:
            return String(localized: "Break started", comment: "Timeline event")
        case .breakEnd:
            return String(localized: "Break ended", comment: "Timeline event")
        case .clockToggle:
            return String(localized: "Clock", comment: "Timeline event")
        case .clockSet:
            return String(localized: "Clock set", comment: "Timeline event")
        case .bracketResult:
            return String(localized: "\(entry.sideName ?? "") advances", comment: "Timeline event")
        case .recordAdjust:
            let field = entry.note.flatMap(RecordField.init(rawValue:))?.shortLabel ?? ""
            let sign = entry.value >= 0 ? "+" : ""
            return String(
                localized: "\(entry.sideName ?? "") \(field) \(sign)\(entry.value)",
                comment: "Timeline event"
            )
        case .matchFinish:
            return String(localized: "Match finished", comment: "Timeline event")

        // Specialised boards (§6.3), written the way a scorer reads them back rather than as enum
        // names — this timeline *is* §13.3's play-by-play.
        case .clockPress:
            return String(localized: "\(entry.sideName ?? "") moved", comment: "Timeline event")
        case .lap:
            return String(localized: "\(entry.sideName ?? "") lap", comment: "Timeline event")
        case .racerFinish:
            return String(localized: "\(entry.sideName ?? "") finished", comment: "Timeline event")
        case .downSet:
            return String(
                localized: "Down \(entry.value) & \(entry.note ?? "")",
                comment: "Timeline event"
            )
        case .ballOn:
            return String(localized: "Ball on \(entry.value)", comment: "Timeline event")
        case .delivery:
            // "4" for a boundary, "1NB" for a single off a no-ball — how a scorebook reads.
            let extra = entry.note.flatMap(CricketExtra.init(rawValue:))?.shortLabel
            return extra.map { "\(entry.value)\($0)" } ?? "\(entry.value)"
        case .wicket:
            let how = entry.note.flatMap(WicketKind.init(rawValue:))?.shortLabel ?? ""
            return String(localized: "Wicket — \(how)", comment: "Timeline event")
        case .inningsEnd:
            return String(localized: "Innings ended", comment: "Timeline event")
        case .pitch:
            return entry.note.flatMap(PitchOutcome.init(rawValue:))?.shortLabel
                ?? String(localized: "Pitch", comment: "Timeline event")
        case .baseRunners:
            return String(localized: "Runners set", comment: "Timeline event")
        case .halfInning:
            return String(localized: "Half-inning", comment: "Timeline event")

        case .undo:
            return String(localized: "Undo", comment: "Timeline event")
        case .correction:
            return String(localized: "Correction", comment: "Timeline event")
        }
    }
}

/// A scaled preview of the share card, so the report header is literally what gets shared.
///
/// `scaleEffect` is a *rendering* transform — it does not change the view's layout size. Scaling a
/// 1920 × 1080 card and then framing it produces a blank row, because the card is still laid out at
/// full size inside whatever space the row offered. The fix is to establish a definite frame first
/// (`Color.clear` with the card's aspect), then draw the full-size card into it as an overlay.
struct ShareCardPreview: View {
    var model: MatchExportModel
    var font: BoardFont

    private var cardSize: CGSize { ShareCardAspect.landscape.size }

    var body: some View {
        Color.clear
            .aspectRatio(cardSize.width / cardSize.height, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    ShareCardView(model: model, aspect: .landscape, font: font)
                        .frame(width: cardSize.width, height: cardSize.height)
                        .scaleEffect(geometry.size.width / cardSize.width, anchor: .topLeading)
                }
            }
            .clipShape(.rect(cornerRadius: 12))
    }
}
