import Foundation

/// The five share formats (§13.5).
enum ShareFormat: String, CaseIterable, Identifiable, Sendable {
    case image, text, pdf, csv, sdgame

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .image: String(localized: "Image", comment: "Share format")
        case .text: String(localized: "Text", comment: "Share format")
        case .pdf: String(localized: "PDF", comment: "Share format")
        case .csv: String(localized: "CSV", comment: "Share format")
        case .sdgame: String(localized: "Game file", comment: "Share format")
        }
    }

    var detail: String {
        switch self {
        case .image: String(localized: "A scorecard image for group chats and social.", comment: "Share format detail")
        case .text: String(localized: "Plain text that reads inline in any message.", comment: "Share format detail")
        case .pdf: String(localized: "The full formatted report, for leagues and printing.", comment: "Share format detail")
        case .csv: String(localized: "One row per event, for your own analysis.", comment: "Share format detail")
        case .sdgame: String(localized: "The whole match. A friend with the app gets the full report.", comment: "Share format detail")
        }
    }

    var symbolName: String {
        switch self {
        case .image: "photo"
        case .text: "text.alignleft"
        case .pdf: "doc.richtext"
        case .csv: "tablecells"
        case .sdgame: "square.and.arrow.up.on.square"
        }
    }

    /// Whether an identity image survives this format. Emoji survives all five (§7.1a).
    var carriesImages: Bool {
        switch self {
        case .image, .pdf, .sdgame: true
        case .text, .csv: false
        }
    }

    var fileExtension: String {
        switch self {
        case .image: "png"
        case .text: "txt"
        case .pdf: "pdf"
        case .csv: "csv"
        case .sdgame: "sdgame"
        }
    }
}

// MARK: - Plain text

enum MatchTextExport {
    /// A summary that reads correctly pasted into any chat, with no attachment.
    static func render(_ model: MatchExportModel) -> String {
        var lines: [String] = []

        lines.append(model.emojiScoreLine)

        var subtitle = [model.presetName]
        if let venue = model.venue, !venue.isEmpty { subtitle.append(venue) }
        lines.append(subtitle.joined(separator: " · "))
        lines.append(model.startedAt.formatted(date: .long, time: .shortened))

        if model.status == .abandoned {
            lines.append(String(localized: "Abandoned", comment: "Text export status"))
        } else if model.status == .live || model.status == .setup {
            lines.append(String(localized: "Live, in progress", comment: "Text export status"))
        }

        if !model.summary.periodLines.isEmpty {
            lines.append("")
            for line in model.summary.periodLines {
                let scores = line.scores.map(String.init).joined(separator: "–")
                lines.append("  \(periodLabel(line.period))  \(scores)")
            }
        }

        let stats = statLines(model.summary, sides: model.sides)
        if !stats.isEmpty {
            lines.append("")
            lines.append(contentsOf: stats.map { "  \($0)" })
        }

        if !model.summary.playerTotals.isEmpty {
            lines.append("")
            lines.append(String(localized: "Scorers", comment: "Text export section"))
            let names = Dictionary(
                model.timeline.compactMap { entry -> (String, Int)? in
                    guard let player = entry.playerName, entry.kind == .score, !entry.isUndone, entry.value > 0
                    else { return nil }
                    return (player, entry.value)
                },
                uniquingKeysWith: +
            )
            for (name, points) in names.sorted(by: { $0.value > $1.value }) {
                lines.append("  \(name) \(points)")
            }
        }

        if model.options.includeTimeline {
            let plays = model.timeline.filter { $0.kind == .score && !$0.isUndone }
            if !plays.isEmpty {
                lines.append("")
                lines.append(String(localized: "Play by play", comment: "Text export section"))
                for entry in plays {
                    lines.append("  \(describe(entry))")
                }
            }
        }

        if let notes = model.notes, !notes.isEmpty {
            lines.append("")
            lines.append(notes)
        }

        if model.options.includeWatermark {
            lines.append("")
            lines.append(String(localized: "Scored with ScoreDock", comment: "Text export watermark"))
        }

        return lines.joined(separator: "\n")
    }

    static func describe(_ entry: MatchExportModel.Entry) -> String {
        var parts: [String] = [
            ClockDisplay.format(entry.matchClock, showsTenths: false),
            periodLabel(entry.period),
        ]
        if let side = entry.sideName {
            parts.append(entry.value >= 0 ? "\(side) +\(entry.value)" : "\(side) \(entry.value)")
        }
        if let player = entry.playerName { parts.append("(\(player))") }
        if let note = entry.note, !note.isEmpty { parts.append("“\(note)”") }
        return parts.joined(separator: "  ")
    }

    private static func periodLabel(_ period: Int) -> String { "P\(period)" }

    static func statLines(_ summary: MatchSummary, sides: [MatchExportModel.Side]) -> [String] {
        var lines: [String] = []
        func name(_ slot: Int) -> String {
            sides.first { $0.slotIndex == slot }?.name ?? "\(slot)"
        }
        if summary.leadChanges > 0 {
            lines.append(String(localized: "Lead changes: \(summary.leadChanges)", comment: "Stat line"))
        }
        if let lead = summary.largestLead, lead.margin > 0 {
            lines.append(String(localized: "Largest lead: \(name(lead.slotIndex)) by \(lead.margin)", comment: "Stat line"))
        }
        if let run = summary.longestRun, run.points > 1 {
            lines.append(String(localized: "Longest run: \(name(run.slotIndex)) \(run.points) unanswered", comment: "Stat line"))
        }
        return lines
    }
}

// MARK: - CSV

enum MatchCSVExport {
    static let header = [
        "index", "wall_clock", "match_clock", "period", "kind",
        "side_index", "side", "player", "value", "note", "undone",
    ]

    /// One row per event, every field (§13.5) — for coaches doing their own analysis.
    ///
    /// Includes undone events with a flag rather than dropping them: the log tells the truth about
    /// what the operator did, and an analyst may well want to see the corrections (§13.3).
    static func render(_ model: MatchExportModel) -> String {
        let formatter = ISO8601DateFormatter()
        var rows = [header.joined(separator: ",")]

        for entry in model.timeline {
            rows.append([
                "\(entry.index)",
                formatter.string(from: entry.timestamp),
                String(format: "%.1f", entry.matchClock),
                "\(entry.period)",
                entry.kind.rawValue,
                entry.slotIndex.map(String.init) ?? "",
                entry.sideName ?? "",
                entry.playerName ?? "",
                "\(entry.value)",
                entry.note ?? "",
                entry.isUndone ? "true" : "false",
            ].map(escape).joined(separator: ","))
        }

        return rows.joined(separator: "\n")
    }

    /// RFC 4180 quoting: wrap in quotes when the field contains a comma, quote, or newline, and
    /// double any embedded quotes.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
