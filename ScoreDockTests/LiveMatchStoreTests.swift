import Foundation
import SwiftData
import Testing

@testable import ScoreDock

/// The M1 exit criterion in test form: a full basketball game runs, and its complete timestamped
/// log is saved.
@Suite("Live match store (§13.1)")
@MainActor
struct LiveMatchStoreTests {
    static let tip = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.tip.addingTimeInterval(seconds) }

    private func makeStore() throws -> (LiveMatchStore, ModelContext) {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let preset = try #require(BuiltInCatalog.bySlug["basketball"])
        let rules = try #require(preset.rules.teamRules)

        let match = MatchBuilder.make(
            preset: GamePreset(
                origin: .builtIn(slug: preset.slug),
                name: preset.name,
                emoji: preset.emoji,
                engine: preset.engine,
                category: preset.category,
                rules: preset.rules,
                defaultThemeID: preset.defaultThemeID,
                sortIndex: 0
            ),
            rules: .team(rules),
            title: "Round 3",
            venue: "Community Hall",
            themeID: "dark",
            attributionEnabled: false,
            sides: [
                SideDraft(displayName: "Wolves", emoji: "🐺", colorHex: "#42A5F5"),
                SideDraft(displayName: "Eagles", emoji: "🦅", colorHex: "#EF5350"),
            ],
            in: context
        )
        let store = try #require(LiveMatchStore(match: match, context: context))
        return (store, context)
    }

    // MARK: The headline test

    @Test("A full basketball game runs and saves a complete timestamped log")
    func fullGame() throws {
        let (store, _) = try makeStore()
        var clock: TimeInterval = 0
        func tick(_ seconds: TimeInterval) -> Date { clock += seconds; return at(clock) }

        // Q1 — tip-off.
        store.perform(.toggleClock, at: tick(0))
        store.perform(.score(slot: 0, points: 2), at: tick(45))
        store.perform(.score(slot: 1, points: 3), at: tick(30))
        store.perform(.foul(slot: 0, delta: 1), at: tick(20))
        store.perform(.setPossession(1), at: tick(1))
        store.perform(.resetShotClock(full: true), at: tick(1))
        store.perform(.timeout(slot: 1, delta: 1), at: tick(60))
        store.perform(.toggleClock, at: tick(1))
        store.perform(.advancePeriod, at: tick(5))

        // Q2, then half-time.
        store.perform(.toggleClock, at: tick(1))
        store.perform(.score(slot: 0, points: 3), at: tick(90))
        store.perform(.score(slot: 0, points: 2), at: tick(40))
        store.perform(.toggleClock, at: tick(10))
        store.perform(.advancePeriod, at: tick(2))
        store.perform(.startBreak(900), at: tick(1))
        store.perform(.endBreak, at: tick(900))

        // Q3 and Q4.
        store.perform(.toggleClock, at: tick(1))
        store.perform(.score(slot: 1, points: 2), at: tick(60))
        store.perform(.foul(slot: 1, delta: 1), at: tick(15))
        store.perform(.toggleClock, at: tick(30))
        store.perform(.advancePeriod, at: tick(2))
        store.perform(.toggleClock, at: tick(1))
        store.perform(.score(slot: 0, points: 2), at: tick(100))
        store.perform(.score(slot: 1, points: 1), at: tick(20))
        store.perform(.toggleClock, at: tick(5))

        store.finish(at: tick(2))

        // --- Final state ---
        #expect(store.state.sides[0].score == 9)
        #expect(store.state.sides[1].score == 6)
        #expect(store.state.period == 4)
        #expect(store.state.isFinished)

        let match = store.match
        #expect(match.status == .finished)
        #expect(match.endedAt != nil)

        // --- Denormalised for stats (§7.2) ---
        let sides = match.orderedSides
        #expect(sides[0].finalScore == 9)
        #expect(sides[1].finalScore == 6)
        #expect(sides[0].outcome == .win)
        #expect(sides[1].outcome == .loss)
        #expect(sides[0].resultRank == 1)
        #expect(sides[1].resultRank == 2)

        // --- The log itself (§13.1–13.3) ---
        let events = match.orderedEvents
        #expect(events.count == 26, "one event per action, nothing merged or dropped")

        // Indices are contiguous and ordered.
        #expect(events.map(\.index) == Array(0 ..< events.count))

        // Every event carries both clocks (§13.2).
        for stored in events {
            #expect(stored.timestamp >= Self.tip, "missing wall-clock time")
            #expect(stored.matchClock >= 0, "missing match-clock time")
            #expect(stored.period >= 1)
        }

        // Wall-clock time only moves forward.
        #expect(zip(events, events.dropFirst()).allSatisfy { $0.timestamp <= $1.timestamp })

        // Everything §13.3 requires is actually present.
        let kinds = Set(events.map(\.kind))
        #expect(kinds.isSuperset(of: [
            .score, .foul, .timeout, .periodAdvance, .possession,
            .shotClockReset, .breakStart, .breakEnd, .clockToggle, .matchFinish,
        ]))

        // A score in Q2 is stamped with the period it happened in, not the final one.
        let q2Scores = events.filter { $0.kind == .score && $0.period == 2 }
        #expect(q2Scores.count == 2)
        #expect(q2Scores.map(\.value).sorted() == [2, 3])
    }

    // MARK: Continuous writing

    /// §13.1: the log is written as the match runs, not assembled at the end — so a crash or a
    /// force-quit still leaves a complete record.
    @Test("Events are persisted as they happen, not at the final whistle")
    func logIsWrittenContinuously() throws {
        let (store, context) = try makeStore()
        store.perform(.toggleClock, at: at(0))
        store.perform(.score(slot: 0, points: 2), at: at(10))

        // Query the store directly rather than the in-memory relationship.
        let stored = try context.fetch(FetchDescriptor<ScoreEvent>())
        #expect(stored.count == 2)
        #expect(store.match.status == .live, "scoring flips a setup match to live")
    }

    /// §12: on next launch an in-progress match is restored from the event log.
    @Test("A match reopens from its log with the clock still correct")
    func crashRecovery() throws {
        let (store, context) = try makeStore()
        store.perform(.toggleClock, at: at(0))
        store.perform(.score(slot: 0, points: 3), at: at(30))
        store.perform(.foul(slot: 1, delta: 2), at: at(45))

        // Simulate a relaunch: brand new store over the same match.
        let reopened = try #require(LiveMatchStore(match: store.match, context: context))

        #expect(reopened.state.sides[0].score == 3)
        #expect(reopened.state.sides[1].fouls == 2)
        // The clock kept running while the app was dead.
        #expect(reopened.board(at: at(120)).primaryClock.value == store.board(at: at(120)).primaryClock.value)
        #expect(reopened.board(at: at(120)).primaryClock.value == 600 - 120)
    }

    // MARK: Undo

    @Test("Undo reverses the last action without erasing it")
    func undoAppendsRatherThanDeletes() throws {
        let (store, _) = try makeStore()
        store.perform(.score(slot: 0, points: 2), at: at(0))
        store.perform(.score(slot: 0, points: 3), at: at(5))
        #expect(store.state.sides[0].score == 5)

        store.undo(at: at(6))
        #expect(store.state.sides[0].score == 2)

        // History is intact: three events, not one.
        #expect(store.match.orderedEvents.count == 3)
        #expect(store.match.orderedEvents.last?.kind == .undo)
    }

    @Test("Undo is unlimited and redo restores")
    func unlimitedUndoAndRedo() throws {
        let (store, _) = try makeStore()
        for index in 0 ..< 10 {
            store.perform(.score(slot: 0, points: 1), at: at(TimeInterval(index)))
        }
        #expect(store.state.sides[0].score == 10)

        for _ in 0 ..< 10 { store.undo(at: at(100)) }
        #expect(store.state.sides[0].score == 0)
        #expect(!store.canUndo)

        store.redo(at: at(200))
        #expect(store.state.sides[0].score == 1)
        #expect(store.canUndo)
    }

    @Test("Undo can reopen a finished match")
    func undoReopensFinishedMatch() throws {
        let (store, _) = try makeStore()
        store.perform(.score(slot: 0, points: 2), at: at(0))
        store.finish(at: at(10))
        #expect(store.match.status == .finished)

        store.undo(at: at(20))
        #expect(store.match.status == .live)
        #expect(store.match.endedAt == nil)
        #expect(!store.state.isFinished)
        // And scoring works again.
        store.perform(.score(slot: 1, points: 3), at: at(25))
        #expect(store.state.sides[1].score == 3)
    }

    // MARK: Expiry

    @Test("A countdown that reaches zero stops itself, and the stop is logged")
    func expiredClockStops() throws {
        let (store, _) = try makeStore()
        store.perform(.toggleClock, at: at(0))
        #expect(store.state.clock.isRunning)

        // 10-minute period; ask well past the buzzer.
        store.stopIfExpired(at: at(700))

        #expect(!store.state.clock.isRunning)
        #expect(store.match.orderedEvents.last?.kind == .clockToggle, "the stop is in the log")
    }

    @Test("Abandoning keeps the log but records no winner")
    func abandon() throws {
        let (store, _) = try makeStore()
        store.perform(.score(slot: 0, points: 5), at: at(0))
        store.abandon(at: at(10))

        #expect(store.match.status == .abandoned)
        #expect(store.match.orderedSides[0].finalScore == 5)
        #expect(store.match.orderedSides.allSatisfy { $0.outcome == .unfinished })
        #expect(store.match.orderedEvents.count >= 2, "the log survives an abandoned match")
    }
}
