import Foundation

/// Translation between an `EngineAction` and its persisted `ScoreEvent` shape.
///
/// This round-trip is load-bearing: undo, crash recovery and the shareable play-by-play all work by
/// replaying stored events back into actions (§6.6). If an action cannot be reconstructed exactly,
/// the log stops being a faithful record — so `EventCodingTests` asserts every case survives.
extension EngineAction {
    var eventKind: EventKind {
        switch self {
        case .score: .score
        case .foul: .foul
        case .timeout: .timeout
        case .advancePeriod, .previousPeriod: .periodAdvance
        case .setPeriodLabel: .periodLabel
        case .toggleClock: .clockToggle
        case .setClockElapsed: .clockSet
        case .toggleShotClock: .shotClockToggle
        case .resetShotClock: .shotClockReset
        case .setPossession: .possession
        case .startBreak: .breakStart
        case .endBreak: .breakEnd
        case .setBracketWinner: .bracketResult
        case .adjustRecord: .recordAdjust
        case let .specialised(action): action.eventKind
        case .finishMatch: .matchFinish
        }
    }

    var eventSlotIndex: Int? {
        switch self {
        case let .score(slot, _, _): slot
        case let .foul(slot, _): slot
        case let .timeout(slot, _): slot
        case let .setPossession(slot): slot
        case let .setBracketWinner(_, slot): slot
        case let .adjustRecord(slot, _, _): slot
        case let .specialised(action): action.eventSlotIndex
        default: nil
        }
    }

    /// The magnitude field.
    ///
    /// `setClockElapsed` stores **deciseconds** so a clock set to 7.4 s survives the round trip
    /// through an `Int` column; everything else stores whole units.
    var eventValue: Int {
        switch self {
        case let .score(_, points, _): points
        case let .foul(_, delta): delta
        case let .timeout(_, delta): delta
        case .advancePeriod: 1
        case .previousPeriod: -1
        case let .setClockElapsed(seconds): Int((seconds * 10).rounded())
        case let .resetShotClock(full): full ? 1 : 0
        case let .startBreak(duration): Int(duration.rounded())
        case let .setBracketWinner(match, _): match
        case let .adjustRecord(_, _, delta): delta
        case let .specialised(action): action.eventValue
        default: 0
        }
    }

    var eventPlayerID: UUID? {
        if case let .score(_, _, playerID) = self { return playerID }
        return nil
    }

    /// Free-text payload. Carries the standings column for `adjustRecord`, since `value` is already
    /// spoken for by the delta.
    var eventNote: String? {
        switch self {
        case let .setPeriodLabel(label): label
        case let .adjustRecord(_, field, _): field.rawValue
        case let .specialised(action): action.eventNote
        default: nil
        }
    }

    /// Rebuilds an action from a stored event. Returns nil for `.undo` and `.correction`, which are
    /// markers rather than state mutations and are handled by the replay itself.
    static func from(
        kind: EventKind,
        slotIndex: Int?,
        value: Int,
        playerID: UUID?,
        note: String?
    ) -> EngineAction? {
        switch kind {
        case .score:
            guard let slotIndex else { return nil }
            return .score(slot: slotIndex, points: value, playerID: playerID)
        case .foul:
            guard let slotIndex else { return nil }
            return .foul(slot: slotIndex, delta: value)
        case .timeout:
            guard let slotIndex else { return nil }
            return .timeout(slot: slotIndex, delta: value)
        case .periodAdvance:
            return value < 0 ? .previousPeriod : .advancePeriod
        case .periodLabel:
            return .setPeriodLabel(note)
        case .clockToggle:
            return .toggleClock
        case .clockSet:
            return .setClockElapsed(TimeInterval(value) / 10)
        case .shotClockToggle:
            return .toggleShotClock
        case .shotClockReset:
            return .resetShotClock(full: value != 0)
        case .possession:
            return .setPossession(slotIndex)
        case .breakStart:
            return .startBreak(TimeInterval(value))
        case .breakEnd:
            return .endBreak
        case .bracketResult:
            return .setBracketWinner(match: value, slot: slotIndex)
        case .recordAdjust:
            guard let slotIndex, let field = note.flatMap(RecordField.init(rawValue:)) else { return nil }
            return .adjustRecord(slot: slotIndex, field: field, delta: value)
        case .matchFinish:
            return .finishMatch
        case .clockPress, .lap, .racerFinish, .downSet, .ballOn,
             .delivery, .wicket, .inningsEnd, .pitch, .baseRunners, .halfInning:
            return SpecialisedAction
                .from(kind: kind, slotIndex: slotIndex, value: value, note: note)
                .map(EngineAction.specialised)
        case .undo, .correction:
            return nil
        }
    }
}

// MARK: - Specialised actions

/// The same round trip for the bespoke boards (§6.3).
///
/// These share the four stored columns with everything else — `slotIndex`, `value`, `note` — so each
/// case has to say which column carries what. Where an action has two numbers, the second travels in
/// `note`: `value` is already spoken for, and adding a column to `ScoreEvent` for one board's sake
/// would be a schema change every other board pays for.
extension SpecialisedAction {
    var eventKind: EventKind {
        switch self {
        case .pressClock: .clockPress
        case .recordLap: .lap
        case .finishRacer: .racerFinish
        case .setDownAndDistance: .downSet
        case .setBallOn: .ballOn
        case .delivery: .delivery
        case .wicket: .wicket
        case .endInnings: .inningsEnd
        case .pitch: .pitch
        case .setBases: .baseRunners
        case .advanceHalfInning: .halfInning
        }
    }

    var eventSlotIndex: Int? {
        switch self {
        case let .pressClock(slot): slot
        case let .recordLap(slot): slot
        case let .finishRacer(slot): slot
        default: nil
        }
    }

    var eventValue: Int {
        switch self {
        case let .setDownAndDistance(down, _): down
        case let .setBallOn(yardLine): yardLine
        case let .delivery(runs, _): runs
        case let .setBases(first, second, third):
            // A three-bit occupancy mask: 1 = first, 2 = second, 4 = third.
            (first ? 1 : 0) | (second ? 2 : 0) | (third ? 4 : 0)
        default: 0
        }
    }

    var eventNote: String? {
        switch self {
        case let .setDownAndDistance(_, yardsToGo): String(yardsToGo)
        case let .delivery(_, extra): extra?.rawValue
        case let .wicket(kind): kind.rawValue
        case let .pitch(outcome): outcome.rawValue
        default: nil
        }
    }

    static func from(kind: EventKind, slotIndex: Int?, value: Int, note: String?) -> SpecialisedAction? {
        switch kind {
        case .clockPress:
            guard let slotIndex else { return nil }
            return .pressClock(slot: slotIndex)
        case .lap:
            guard let slotIndex else { return nil }
            return .recordLap(slot: slotIndex)
        case .racerFinish:
            guard let slotIndex else { return nil }
            return .finishRacer(slot: slotIndex)
        case .downSet:
            return .setDownAndDistance(down: value, yardsToGo: note.flatMap(Int.init) ?? 0)
        case .ballOn:
            return .setBallOn(yardLine: value)
        case .delivery:
            // A nil note is a plain legal ball; an *unrecognised* one is a newer build's extra, and
            // dropping it back to a legal ball would silently change the over count. Refuse instead.
            guard let note else { return .delivery(runs: value, extra: nil) }
            guard let extra = CricketExtra(rawValue: note) else { return nil }
            return .delivery(runs: value, extra: extra)
        case .wicket:
            guard let kind = note.flatMap(WicketKind.init(rawValue:)) else { return nil }
            return .wicket(kind: kind)
        case .inningsEnd:
            return .endInnings
        case .pitch:
            guard let outcome = note.flatMap(PitchOutcome.init(rawValue:)) else { return nil }
            return .pitch(outcome)
        case .baseRunners:
            return .setBases(first: value & 1 != 0, second: value & 2 != 0, third: value & 4 != 0)
        case .halfInning:
            return .advanceHalfInning
        default:
            return nil
        }
    }
}

extension ScoreEvent {
    /// The action this event recorded, if it was a state mutation.
    var engineAction: EngineAction? {
        EngineAction.from(
            kind: kind,
            slotIndex: slotIndex,
            value: value,
            playerID: attributedPlayerID,
            note: note
        )
    }
}
