import Foundation
import SwiftData

/// One entry in the play-by-play log (§13.2).
///
/// Every state mutation appends one of these. That single decision buys unlimited undo, the
/// shareable game log, per-player attribution, crash recovery and dispute resolution at once (§6.6).
@Model
final class ScoreEvent {
    /// Inverse of `Match.events`; required by CloudKit (§7.5).
    var match: Match?

    /// Explicit ordering. CloudKit relationships are unordered sets, so this — not array position —
    /// is what makes the log a sequence.
    var index: Int = 0

    /// Wall-clock time. Answers "when did this happen in real life", which is what lets someone
    /// line the log up against video footage afterwards.
    var timestamp: Date = Date.now

    /// Game clock at that moment. Answers "when in the game", which is what a referee, coach or
    /// player actually remembers. Both are stored because neither is sufficient alone (§13.2).
    var matchClock: TimeInterval = 0

    var period: Int = 1
    var kindRaw: String = EventKind.score.rawValue

    /// Which side, where the event has one. Nil for match-wide events such as a period advance.
    var slotIndex: Int?

    /// Optional player credit (§4.1). Stored as the player's `id` rather than as a relationship so
    /// the log stays self-contained and survives the player record being deleted — the report can
    /// still say a point was attributed, even once the name is gone.
    var attributedPlayerID: UUID?

    var value: Int = 0
    var note: String?

    init(
        index: Int = 0,
        timestamp: Date = .now,
        matchClock: TimeInterval = 0,
        period: Int = 1,
        kind: EventKind = .score,
        slotIndex: Int? = nil,
        attributedPlayerID: UUID? = nil,
        value: Int = 0,
        note: String? = nil
    ) {
        self.index = index
        self.timestamp = timestamp
        self.matchClock = matchClock
        self.period = period
        self.kindRaw = kind.rawValue
        self.slotIndex = slotIndex
        self.attributedPlayerID = attributedPlayerID
        self.value = value
        self.note = note
    }
}

extension ScoreEvent {
    var kind: EventKind {
        get { EventKind(storedRaw: kindRaw) }
        set { kindRaw = newValue.rawValue }
    }
}
