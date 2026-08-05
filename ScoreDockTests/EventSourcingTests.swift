import Foundation
import SwiftData
import Testing

@testable import ScoreDock

/// §6.6 and §13. Event sourcing is what buys unlimited undo, the shareable log, crash recovery and
/// dispute resolution at once — so replay has to be exact, not approximately right.
@Suite("Event sourcing (§6.6, §13)")
@MainActor
struct EventSourcingTests {
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.t0.addingTimeInterval(seconds) }

    private var basketball: TeamRules {
        BuiltInCatalog.bySlug["basketball"]?.rules.teamRules ?? TeamRules()
    }

    /// A match wired into an in-memory store, as the app would build it.
    private func makeMatch(rules: TeamRules? = nil) throws -> (Match, ModelContext) {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let match = Match(
            presetSlug: "basketball",
            rulesSnapshot: .team(rules ?? basketball),
            themeSnapshot: BuiltInThemes.theme(id: "dark"),
            status: .setup
        )
        context.insert(match)
        for (slot, name) in ["Wolves", "Eagles"].enumerated() {
            let side = MatchSide(slotIndex: slot, displayName: name, shortName: name.prefix(3).uppercased())
            side.match = match
            context.insert(side)
        }
        try context.save()
        return (match, context)
    }

    private func event(
        _ index: Int,
        _ kind: EventKind,
        value: Int = 0,
        slot: Int? = nil,
        at seconds: TimeInterval = 0,
        in match: Match,
        context: ModelContext
    ) {
        let stored = ScoreEvent(
            index: index,
            timestamp: at(seconds),
            kind: kind,
            slotIndex: slot,
            value: value
        )
        stored.match = match
        context.insert(stored)
    }

    // MARK: Undo resolution

    @Test("A plain log has nothing undone")
    func noUndos() throws {
        let (match, context) = try makeMatch()
        event(0, .score, value: 2, slot: 0, in: match, context: context)
        event(1, .score, value: 3, slot: 1, in: match, context: context)

        #expect(MatchReplay.undoneIndices(in: match.orderedEvents).isEmpty)
        #expect(MatchReplay.nextUndoTarget(in: match.orderedEvents)?.index == 1)
        #expect(MatchReplay.nextRedoTarget(in: match.orderedEvents) == nil)
    }

    @Test("An undo cancels its target")
    func singleUndo() throws {
        let (match, context) = try makeMatch()
        event(0, .score, value: 2, slot: 0, in: match, context: context)
        event(1, .score, value: 3, slot: 0, in: match, context: context)
        event(2, .undo, value: 1, in: match, context: context)

        #expect(MatchReplay.undoneIndices(in: match.orderedEvents) == [1])
        // Next undo steps back to the one before it.
        #expect(MatchReplay.nextUndoTarget(in: match.orderedEvents)?.index == 0)
    }

    /// The case a naive forward pass gets wrong: undoing an undo is a redo, and must revive the
    /// original event rather than leaving both cancelled.
    @Test("Undoing an undo revives the original event")
    func redoRevivesOriginal() throws {
        let (match, context) = try makeMatch()
        event(3, .score, value: 3, slot: 0, in: match, context: context)
        event(5, .undo, value: 3, in: match, context: context)
        event(7, .undo, value: 5, in: match, context: context)

        #expect(
            MatchReplay.undoneIndices(in: match.orderedEvents).isEmpty,
            "event 7 cancels event 5, so event 3 is live again"
        )
    }

    @Test("Undo and redo alternate indefinitely")
    func repeatedUndoRedo() throws {
        let (match, context) = try makeMatch()
        event(0, .score, value: 2, slot: 0, in: match, context: context)

        // undo, redo, undo, redo…
        event(1, .undo, value: 0, in: match, context: context)
        #expect(MatchReplay.undoneIndices(in: match.orderedEvents) == [0])

        event(2, .undo, value: 1, in: match, context: context)
        #expect(MatchReplay.undoneIndices(in: match.orderedEvents).isEmpty)

        event(3, .undo, value: 2, in: match, context: context)
        #expect(MatchReplay.undoneIndices(in: match.orderedEvents) == [0])
    }

    // MARK: Replay

    @Test("Replay reproduces state exactly, using each event's own timestamp")
    func replayUsesRecordedTimestamps() throws {
        let rules = basketball
        let (match, context) = try makeMatch(rules: rules)

        // Clock starts at t+0, a basket at t+30.
        event(0, .clockToggle, at: 0, in: match, context: context)
        event(1, .score, value: 3, slot: 0, at: 30, in: match, context: context)

        let state = MatchReplay.state(
            TeamEngine.self, rules: rules, sideCount: 2, events: match.orderedEvents
        )

        #expect(state.sides[0].score == 3)
        // The clock was anchored at the *recorded* start, so a minute after t0 it reads 60s elapsed.
        #expect(state.clock.elapsed(at: at(60)) == 60)
    }

    @Test("Replay skips undone events")
    func replaySkipsUndone() throws {
        let rules = basketball
        let (match, context) = try makeMatch(rules: rules)
        event(0, .score, value: 2, slot: 0, in: match, context: context)
        event(1, .score, value: 3, slot: 0, in: match, context: context)
        event(2, .undo, value: 1, in: match, context: context)

        let state = MatchReplay.state(
            TeamEngine.self, rules: rules, sideCount: 2, events: match.orderedEvents
        )
        #expect(state.sides[0].score == 2)
    }

    @Test("Replay from a snapshot matches replay from scratch")
    func snapshotReplayMatches() throws {
        let rules = basketball
        let (match, context) = try makeMatch(rules: rules)
        for index in 0 ..< 20 {
            event(index, .score, value: 1, slot: index % 2, at: TimeInterval(index), in: match, context: context)
        }

        let events = match.orderedEvents
        let full = MatchReplay.state(TeamEngine.self, rules: rules, sideCount: 2, events: events)

        // Snapshot after the first 10, then replay only the rest.
        let firstTen = Array(events.prefix(10))
        let partial = MatchReplay.state(TeamEngine.self, rules: rules, sideCount: 2, events: firstTen)
        let resumed = MatchReplay.state(
            TeamEngine.self,
            rules: rules,
            sideCount: 2,
            events: events,
            snapshot: (partial, firstTen.last!.index)
        )

        #expect(resumed == full)
    }

    @Test("A snapshot is invalid once an earlier event is undone")
    func snapshotInvalidation() throws {
        let (match, context) = try makeMatch()
        for index in 0 ..< 5 {
            event(index, .score, value: 1, slot: 0, in: match, context: context)
        }
        #expect(MatchReplay.isSnapshotValid(upToIndex: 4, events: match.orderedEvents))

        event(5, .undo, value: 2, in: match, context: context)
        #expect(!MatchReplay.isSnapshotValid(upToIndex: 4, events: match.orderedEvents))
        #expect(!MatchReplay.isSnapshotValid(upToIndex: 0, events: match.orderedEvents))
    }

    // MARK: Action coding

    @Test("Every action survives the round trip through a stored event")
    func actionRoundTrip() {
        let cases: [EngineAction] = [
            .score(slot: 0, points: 3, playerID: nil),
            .score(slot: 1, points: -1, playerID: UUID()),
            .foul(slot: 0, delta: 1),
            .foul(slot: 1, delta: -1),
            .timeout(slot: 0, delta: 1),
            .advancePeriod,
            .previousPeriod,
            .setPeriodLabel("OT"),
            .setPeriodLabel(nil),
            .toggleClock,
            .setClockElapsed(0),
            .setClockElapsed(7.4),
            .toggleShotClock,
            .resetShotClock(full: true),
            .resetShotClock(full: false),
            .setPossession(1),
            .setPossession(nil),
            .startBreak(900),
            .endBreak,
            .finishMatch,
        ]

        for action in cases {
            let rebuilt = EngineAction.from(
                kind: action.eventKind,
                slotIndex: action.eventSlotIndex,
                value: action.eventValue,
                playerID: action.eventPlayerID,
                note: action.eventNote
            )
            #expect(rebuilt == action, "\(action) did not round-trip")
        }
    }

    @Test("Undo and correction markers decode to no action")
    func markersHaveNoAction() {
        #expect(EngineAction.from(kind: .undo, slotIndex: nil, value: 3, playerID: nil, note: nil) == nil)
        #expect(EngineAction.from(kind: .correction, slotIndex: nil, value: 0, playerID: nil, note: nil) == nil)
    }
}
