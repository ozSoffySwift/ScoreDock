import Foundation
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    /// Exported type for a shared match (§13.5).
    static let sdGame = UTType(exportedAs: "com.ozsoffy.scoredock.game")
}

/// A whole match as JSON (§13.5).
///
/// ## Threat model (§17, risk 11)
///
/// This file arrives from a third party — AirDropped, emailed, pulled out of Files. Everything here
/// is therefore deliberately boring:
///
/// - **Plain `Codable` structs only.** No `NSKeyedUnarchiver`, no class-name resolution, nothing
///   that can instantiate a type named in the payload. There is no execution path of any kind.
/// - **A hard byte ceiling**, checked before parsing.
/// - **Embedded images validated for size and dimensions *before* they are decoded**, so a
///   decompression bomb is rejected rather than expanded.
/// - **Import produces a read-only archived match.** It never touches the recipient's players,
///   teams or presets — at most it offers to link names that already match.
struct SdGameDocument: Codable, Sendable {
    static let currentVersion = 1

    /// 25 MB. A long cricket innings with crests is real data (§17 risk 12), but nothing legitimate
    /// approaches this.
    static let maxFileBytes = 25 * 1024 * 1024

    struct Side: Codable, Sendable {
        var slotIndex: Int
        var name: String
        var shortName: String
        var emoji: String?
        var imageData: Data?
        var colorHex: String
        var finalScore: Int
        var outcome: String
    }

    struct Event: Codable, Sendable {
        var index: Int
        var timestamp: Date
        var matchClock: TimeInterval
        var period: Int
        var kind: String
        var slotIndex: Int?
        var playerName: String?
        var value: Int
        var note: String?
    }

    var version: Int
    var exportedAt: Date
    var appName: String

    var matchID: UUID
    var title: String
    var presetSlug: String
    var presetName: String
    var venue: String?
    var startedAt: Date
    var endedAt: Date?
    var status: String
    var notes: String?
    var themeID: String
    var sides: [Side]
    var events: [Event]

    enum ImportError: LocalizedError {
        case tooLarge
        case unsupportedVersion(Int)
        case malformed
        case suspiciousImage

        var errorDescription: String? {
            switch self {
            case .tooLarge:
                String(localized: "That game file is too large to open.", comment: "Import error")
            case let .unsupportedVersion(found):
                String(localized: "That game file was made by a newer version of the app (format \(found)).", comment: "Import error")
            case .malformed:
                String(localized: "That game file could not be read.", comment: "Import error")
            case .suspiciousImage:
                String(localized: "That game file contains an image that could not be used, so it was not opened.", comment: "Import error")
            }
        }
    }
}

// MARK: - Export

extension SdGameDocument {
    init(_ model: MatchExportModel) {
        version = Self.currentVersion
        exportedAt = .now
        appName = "ScoreDock"
        matchID = model.matchID
        title = model.title
        presetSlug = model.presetName
        presetName = model.presetName
        venue = model.venue
        startedAt = model.startedAt
        endedAt = model.endedAt
        status = model.status.rawValue
        notes = model.notes
        themeID = model.themeID
        sides = model.sides.map {
            Side(
                slotIndex: $0.slotIndex,
                name: $0.name,
                shortName: $0.shortName,
                emoji: $0.emoji,
                imageData: $0.imageData,
                colorHex: $0.colorHex,
                finalScore: $0.finalScore,
                outcome: $0.outcome.rawValue
            )
        }
        events = model.timeline.map {
            Event(
                index: $0.index,
                timestamp: $0.timestamp,
                matchClock: $0.matchClock,
                period: $0.period,
                kind: $0.kind.rawValue,
                slotIndex: $0.slotIndex,
                playerName: $0.playerName,
                value: $0.value,
                note: $0.note
            )
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Import

extension SdGameDocument {
    static func decode(_ data: Data) throws -> SdGameDocument {
        guard data.count <= maxFileBytes else { throw ImportError.tooLarge }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let document: SdGameDocument
        do {
            document = try decoder.decode(SdGameDocument.self, from: data)
        } catch {
            throw ImportError.malformed
        }

        guard document.version <= currentVersion else {
            throw ImportError.unsupportedVersion(document.version)
        }

        // Validate every embedded image before anything renders it.
        for side in document.sides {
            guard let imageData = side.imageData else { continue }
            guard (try? IdentityImage.normalize(imageData)) != nil else {
                throw ImportError.suspiciousImage
            }
        }

        return document
    }

    /// Creates a **read-only archived** match from an imported file.
    ///
    /// Deliberately does not create or modify any `Player`, `Team` or `UserGamePreset`: an imported
    /// file must never overwrite the recipient's own records (§13.5, §17 risk 11).
    @MainActor
    @discardableResult
    func importAsArchivedMatch(into context: ModelContext) -> Match {
        let match = Match(
            // A fresh id, so importing the same file twice does not collide with the sender's match
            // or with a previous import.
            presetSlug: presetSlug,
            title: title,
            venue: venue,
            startedAt: startedAt,
            status: .finished
        )
        match.endedAt = endedAt
        match.notes = notes
        match.themeSnapshot = BuiltInThemes.theme(id: themeID)
        context.insert(match)

        for side in sides {
            let matchSide = MatchSide(
                slotIndex: side.slotIndex,
                displayName: side.name,
                shortName: side.shortName,
                emoji: side.emoji,
                image: side.imageData,
                mark: side.emoji == nil ? (side.imageData == nil ? .initials : .image) : .emoji,
                colorHex: side.colorHex
            )
            matchSide.finalScore = side.finalScore
            matchSide.outcome = SideOutcome(storedRaw: side.outcome)
            matchSide.match = match
            context.insert(matchSide)
        }

        for event in events {
            let stored = ScoreEvent(
                index: event.index,
                timestamp: event.timestamp,
                matchClock: event.matchClock,
                period: event.period,
                kind: EventKind(storedRaw: event.kind),
                slotIndex: event.slotIndex,
                value: event.value,
                note: event.note
            )
            stored.match = match
            context.insert(stored)
        }

        try? context.save()
        return match
    }
}
