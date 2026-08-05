import Foundation
import SwiftData

/// One played game, with its own complete event log.
///
/// Every run creates its own record — two runs of the same preset back to back, the same two teams
/// meeting six times in a season, or a game abandoned at half-time. Nothing is ever merged,
/// overwritten or reused between plays (§13.1).
@Model
final class Match {
    var id: UUID = UUID()

    /// A built-in slug (`"basketball-nba"`) or a `UserGamePreset.id` string. A plain column rather
    /// than a relationship, because built-ins are bundled catalog data and not stored rows (§7.4).
    var presetSlug: String = ""

    /// Frozen at kickoff. Editing a preset afterwards must never rewrite history, so the match
    /// carries its own copy of the rules it was actually played under.
    ///
    /// Stored as encoded `Data`, not as the `AnyRuleSet` value itself. SwiftData treats a `Codable`
    /// enum with associated values as a *composite attribute* and tries to decompose it into
    /// columns, which traps at encode time with "unknown property payload for composite
    /// description". §7.3 asks for an encoded attribute anyway, so this is the faithful reading —
    /// and it keeps the blob genuinely opaque, which is the whole point.
    var rulesData: Data?

    /// Frozen for the same reason — the Match Report renders in the theme the game was played in (§13.4).
    var themeData: Data?

    var title: String?
    var venue: String?

    /// Free text the operator can add before sharing (§13.4).
    var notes: String?
    var startedAt: Date = Date.now
    var endedAt: Date?
    var statusRaw: String = MatchStatus.setup.rawValue

    /// Encoded engine `State` for crash recovery, written alongside `snapshotEventIndex`.
    ///
    /// Replay is the source of truth; this is the optimisation that keeps replay instant. Snapshot
    /// every 50 events so a long cricket innings does not replay from ball one (§6.6).
    var stateBlob: Data?
    var snapshotEventIndex: Int = 0

    /// Whether this match credits scores to individual players (§4.1). Off by default: with it off
    /// a score is one tap and nothing else, which is what a referee running a clock needs.
    var attributionEnabled: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \MatchSide.match)
    var sides: [MatchSide]? = []

    @Relationship(deleteRule: .cascade, inverse: \ScoreEvent.match)
    var events: [ScoreEvent]? = []

    init(
        id: UUID = UUID(),
        presetSlug: String = "",
        rulesSnapshot: AnyRuleSet? = nil,
        themeSnapshot: ThemeSpec? = nil,
        title: String? = nil,
        venue: String? = nil,
        startedAt: Date = .now,
        status: MatchStatus = .setup,
        attributionEnabled: Bool = false
    ) {
        self.id = id
        self.presetSlug = presetSlug
        self.rulesData = CodableBlob.encode(rulesSnapshot)
        self.themeData = CodableBlob.encode(themeSnapshot)
        self.title = title
        self.venue = venue
        self.startedAt = startedAt
        self.statusRaw = status.rawValue
        self.attributionEnabled = attributionEnabled
    }
}

extension Match {
    /// The rules this match was played under. Decoding failure yields nil rather than throwing —
    /// a blob written by a newer build should degrade, not crash a history screen (§7.3).
    var rulesSnapshot: AnyRuleSet? {
        get { CodableBlob.decode(rulesData) }
        set { rulesData = CodableBlob.encode(newValue) }
    }

    var themeSnapshot: ThemeSpec? {
        get { CodableBlob.decode(themeData) }
        set { themeData = CodableBlob.encode(newValue) }
    }

    var status: MatchStatus {
        get { MatchStatus(storedRaw: statusRaw) }
        set { statusRaw = newValue.rawValue }
    }

    /// Sides in board order — home first. Sorted on `slotIndex` rather than trusting array order,
    /// which CloudKit does not preserve (§7.5).
    var orderedSides: [MatchSide] {
        (sides ?? []).sorted { $0.slotIndex < $1.slotIndex }
    }

    /// The log in the order it happened, by explicit `index` for the same reason.
    var orderedEvents: [ScoreEvent] {
        (events ?? []).sorted { $0.index < $1.index }
    }

    /// Next value for `ScoreEvent.index`. Derived from the maximum rather than the count so that a
    /// partially-loaded or partially-synced relationship can never collide two events onto one index.
    var nextEventIndex: Int {
        ((events ?? []).map(\.index).max() ?? -1) + 1
    }

    var isInProgress: Bool { status == .live || status == .setup }

    /// Points scored per side.
    ///
    /// A closed match uses the denormalised `finalScore` (§7.2). An in-progress one sums its live
    /// log instead — otherwise History shows "0 – 0" for a game that has points on the board, which
    /// reads as data loss.
    ///
    /// This is the sum of `.score` events, which is the whole story only for a scoreboard. A
    /// standings table's figure is *points* derived from win/draw records, and a bracket has no total
    /// at all — so summary text goes through `MatchSummaryLine`, not this.
    var displayScores: [Int] {
        let sides = orderedSides
        guard isInProgress else { return sides.map(\.finalScore) }

        let events = orderedEvents
        let undone = MatchReplay.undoneIndices(in: events)
        var totals = Array(repeating: 0, count: sides.count)
        for event in events where event.kind == .score && !undone.contains(event.index) {
            guard let slot = event.slotIndex, totals.indices.contains(slot) else { continue }
            // Mirrors the engine's per-application clamp, so a corrected score never goes negative.
            totals[slot] = max(0, totals[slot] + event.value)
        }
        return totals
    }
}
