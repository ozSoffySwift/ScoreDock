import Foundation

/// What to include in an export (§13.5, §13.6).
struct ExportOptions: Sendable, Hashable {
    /// §13.6 — some of these matches involve children. Anonymising replaces names with initials or
    /// "Player 1", **and strips identity images**, because a photo defeats the purpose entirely.
    var anonymisePlayers = false

    /// §13.5 growth note: a small app mark, on by default, and free to remove. A watermark the user
    /// cannot remove reads as an upsell and undercuts the free-forever positioning.
    var includeWatermark = true

    /// Full play-by-play, or scores only. §19.2 leaves the default open; the share sheet remembers
    /// the last choice per format, which is the suggestion made there.
    var includeTimeline = true
}

/// A flattened, export-ready snapshot of a match.
///
/// Built once and rendered five ways (§13.5). Keeping this a `Sendable` value means the heavy
/// formats — PDF pagination, a 3× image render — never reach back into SwiftData mid-render, which
/// is what would otherwise make a background export unsafe.
struct MatchExportModel: Sendable {
    struct Side: Sendable, Hashable {
        var slotIndex: Int
        var name: String
        var shortName: String
        var emoji: String?
        var imageData: Data?
        var colorHex: String
        var finalScore: Int
        var outcome: SideOutcome
    }

    struct Entry: Sendable, Hashable, Identifiable {
        var index: Int
        var timestamp: Date
        var matchClock: TimeInterval
        var period: Int
        var kind: EventKind
        var slotIndex: Int?
        var sideName: String?
        var playerName: String?
        var value: Int
        var note: String?
        var isUndone: Bool

        var id: Int { index }
    }

    var matchID: UUID
    var title: String
    var presetName: String
    var venue: String?
    var startedAt: Date
    var endedAt: Date?
    var status: MatchStatus
    var notes: String?
    var themeID: String
    var sides: [Side]
    var summary: MatchSummary
    var timeline: [Entry]
    var options: ExportOptions
    var attributionEnabled: Bool

    /// The board the match ended on, so the share card can render the *real* thing rather than
    /// re-describing the result in its own arrangement (§13.4). Nil only if the rules could not be
    /// decoded, in which case the card falls back to a plain score line.
    var board: ExportedBoard?

    var scoreLine: String {
        sides.map { "\($0.name) \($0.finalScore)" }.joined(separator: " – ")
    }

    /// `🐺 Wolves 62 – 58 Eagles 🦅` — emoji survives losslessly into plain text and reads perfectly
    /// in a group chat with no attachment (§7.1a).
    ///
    /// The two sides are mirrored around the dash, so the scores meet in the middle and each side's
    /// mark sits on its own outer edge. That is the layout §7.1a shows, and it reads like a result
    /// rather than like a list.
    var emojiScoreLine: String {
        guard sides.count == 2 else {
            return sides
                .map { [$0.emoji, $0.name, "\($0.finalScore)"].compactMap(\.self).joined(separator: " ") }
                .joined(separator: " – ")
        }
        let home = [sides[0].emoji, sides[0].name, "\(sides[0].finalScore)"]
            .compactMap(\.self).joined(separator: " ")
        let away = ["\(sides[1].finalScore)", sides[1].name, sides[1].emoji]
            .compactMap(\.self).joined(separator: " ")
        return "\(home) – \(away)"
    }
}

@MainActor
enum MatchExportBuilder {
    static func build(_ match: Match, options: ExportOptions) -> MatchExportModel {
        let summary = MatchStatistics.summarize(match)
        let orderedSides = match.orderedSides
        let undone = MatchReplay.undoneIndices(in: match.orderedEvents)

        // Player names are resolved once here, so the timeline never has to reach into the store
        // while rendering.
        var playerNames: [UUID: String] = [:]
        if match.attributionEnabled {
            for (offset, id) in Set(match.orderedEvents.compactMap(\.attributedPlayerID)).sorted(by: { $0.uuidString < $1.uuidString }).enumerated() {
                playerNames[id] = options.anonymisePlayers
                    ? String(localized: "Player \(offset + 1)", comment: "Anonymised player")
                    : (match.linkedPlayerName(for: id) ?? String(localized: "Player \(offset + 1)", comment: "Anonymised player"))
            }
        }

        let sides = orderedSides.map { side in
            MatchExportModel.Side(
                slotIndex: side.slotIndex,
                name: options.anonymisePlayers ? anonymisedName(for: side) : side.displayName,
                shortName: options.anonymisePlayers ? "\(side.slotIndex + 1)" : side.shortName,
                // Anonymising strips the emoji and image too — a crest identifies a club as surely
                // as its name does (§13.6).
                emoji: options.anonymisePlayers ? nil : side.emoji,
                imageData: options.anonymisePlayers ? nil : side.image,
                colorHex: side.colorHex,
                finalScore: match.isInProgress
                    ? (summary.finalScores.indices.contains(side.slotIndex) ? summary.finalScores[side.slotIndex] : 0)
                    : side.finalScore,
                outcome: side.outcome
            )
        }

        let timeline = match.orderedEvents.map { event in
            MatchExportModel.Entry(
                index: event.index,
                timestamp: event.timestamp,
                matchClock: event.matchClock,
                period: event.period,
                kind: event.kind,
                slotIndex: event.slotIndex,
                sideName: event.slotIndex.flatMap { slot in
                    sides.first { $0.slotIndex == slot }?.name
                },
                playerName: event.attributedPlayerID.flatMap { playerNames[$0] },
                value: event.value,
                note: event.note,
                isUndone: undone.contains(event.index)
            )
        }

        return MatchExportModel(
            matchID: match.id,
            title: match.title?.isEmpty == false
                ? match.title!
                : (BuiltInCatalog.bySlug[match.presetSlug]?.name
                    ?? String(localized: "Match", comment: "Fallback match title")),
            presetName: BuiltInCatalog.bySlug[match.presetSlug]?.name ?? match.presetSlug,
            venue: options.anonymisePlayers ? nil : match.venue,
            startedAt: match.startedAt,
            endedAt: match.endedAt,
            status: match.status,
            notes: match.notes,
            themeID: match.themeSnapshot?.id ?? BuiltInThemes.defaultID,
            sides: sides,
            summary: summary,
            timeline: timeline,
            options: options,
            attributionEnabled: match.attributionEnabled,
            board: board(for: match)
        )
    }

    private static func anonymisedName(for side: MatchSide) -> String {
        // Initials where there are any, otherwise a numbered placeholder.
        let initials = side.initials
        return initials == "?" ? String(localized: "Team \(side.slotIndex + 1)", comment: "Anonymised side") : initials
    }
}

private extension Match {
    /// Resolves an attributed player's display name from the sides' linked records.
    func linkedPlayerName(for id: UUID) -> String? {
        for side in orderedSides {
            if let player = side.linkedPlayer, player.id == id { return player.displayName }
            if let roster = side.linkedTeam?.roster {
                for membership in roster where membership.player?.id == id {
                    return membership.player?.displayName
                }
            }
        }
        return nil
    }
}
