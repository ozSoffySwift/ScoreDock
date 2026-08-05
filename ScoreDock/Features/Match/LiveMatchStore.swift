import Foundation
import OSLog
import SwiftData
import SwiftUI

/// The single source of truth for a running match (§5.2).
///
/// One store, injected into both the control panel and the board, so rotation and the external
/// display are two renderers of one state rather than two copies of it. Rotation must never
/// re-instantiate this — see `MatchContainerView`.
///
/// It owns the SwiftData side of event sourcing: the log is written **continuously as the match
/// runs, not assembled at the end** (§13.1), so a crash, a force-quit or an abandoned game still
/// leaves a complete record up to the last action taken.
@Observable
@MainActor
final class LiveMatchStore: Identifiable {
    /// Stable for the lifetime of the store, so `fullScreenCover(item:)` presents it once rather
    /// than re-presenting on every evaluation.
    nonisolated let id = UUID()

    let match: Match
    let rules: TeamRules
    let theme: ThemeSpec

    private(set) var state: TeamState

    /// Called after each applied action, for sound and haptics (§11).
    ///
    /// A closure rather than a direct dependency: the store stays free of AVFoundation and UIKit,
    /// which is what keeps it testable headlessly, and the view layer decides what an action should
    /// feel like.
    var onAction: ((EngineAction) -> Void)?

    private let context: ModelContext
    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "match")

    /// Engine state is snapshotted every this many events so replay stays instant in a long match
    /// (§6.6). Replay remains the source of truth; this is only an optimisation.
    private static let snapshotInterval = 50

    init?(match: Match, context: ModelContext) {
        guard let rules = match.rulesSnapshot?.teamRules else {
            Self.logger.error("Match \(match.id) has no team rules; cannot open.")
            return nil
        }
        self.match = match
        self.rules = rules
        self.context = context
        self.theme = match.themeSnapshot ?? BuiltInThemes.theme(id: nil)
        self.state = TeamEngine.initialState(rules: rules, sideCount: max(2, match.orderedSides.count))
        rebuild()
    }

    // MARK: - Reading

    /// What the board renders at this instant. Called from inside a `TimelineView`, so it must stay
    /// cheap and must not mutate anything.
    func board(at now: Date) -> DerivedBoard {
        TeamEngine.derived(state, rules: rules, at: now)
    }

    func outcome(at now: Date = .now) -> MatchOutcome? {
        TeamEngine.outcome(state, rules: rules, at: now)
    }

    var sides: [MatchSide] { match.orderedSides }

    var canUndo: Bool { MatchReplay.nextUndoTarget(in: match.orderedEvents) != nil }
    var canRedo: Bool { MatchReplay.nextRedoTarget(in: match.orderedEvents) != nil }

    // MARK: - Performing actions

    /// Applies an action and records it. Every state mutation goes through here — there is no other
    /// way to change the match, which is what keeps the log complete by construction.
    func perform(_ action: EngineAction, at now: Date = .now) {
        guard !state.isFinished else { return }

        append(action, at: now)
        TeamEngine.apply(action, to: &state, rules: rules, at: now)

        if match.status == .setup { match.status = .live }
        snapshotIfDue()
        save()
        onAction?(action)
    }

    /// Stops a countdown that has run to zero.
    ///
    /// Logged as a real clock stop rather than silently clamped, because §13.3 requires every clock
    /// start and stop in the log. Driven from `onChange` in the view, never from inside a render
    /// pass. A count-up clock is left alone — running past the period length is added time (§6.1).
    func stopIfExpired(at now: Date = .now) {
        guard !state.isFinished, !state.isOnBreak, !rules.countsUp else { return }
        let clock = board(at: now).primaryClock
        guard clock.hasExpired, clock.isRunning else { return }
        perform(.toggleClock, at: now)
    }

    // MARK: - Undo and redo

    /// Undo is global and unlimited within a match (§4.2).
    ///
    /// It appends a compensating event rather than deleting one: the log tells the truth about what
    /// the operator actually did, including their mistakes, which is precisely what makes it useful
    /// when a result is disputed (§13.3).
    func undo(at now: Date = .now) {
        guard let target = MatchReplay.nextUndoTarget(in: match.orderedEvents) else { return }
        recordUndo(of: target.index, at: now)
    }

    /// Redo works by undoing the undo — see `MatchReplay.undoneIndices`.
    func redo(at now: Date = .now) {
        guard let target = MatchReplay.nextRedoTarget(in: match.orderedEvents) else { return }
        recordUndo(of: target.index, at: now)
    }

    private func recordUndo(of targetIndex: Int, at now: Date) {
        let event = ScoreEvent(
            index: match.nextEventIndex,
            timestamp: now,
            matchClock: board(at: now).primaryClock.value,
            period: state.period,
            kind: .undo,
            value: targetIndex
        )
        event.match = match
        context.insert(event)

        // Rewriting history invalidates any snapshot taken at or after the affected event.
        // Repairing one is more subtle than recomputing, and replay is fast — so drop it.
        if targetIndex <= match.snapshotEventIndex {
            match.stateBlob = nil
            match.snapshotEventIndex = 0
        }

        // An undo can reopen a finished match, which is the whole point of "unlimited".
        if match.status == .finished {
            match.status = .live
            match.endedAt = nil
        }

        rebuild()
        save()
    }

    // MARK: - Finishing

    func finish(at now: Date = .now) {
        perform(.finishMatch, at: now)
        close(status: .finished, at: now)
    }

    /// Ended early. Still keeps its complete log up to the last action taken (§13.1).
    func abandon(at now: Date = .now) {
        perform(.finishMatch, at: now)
        close(status: .abandoned, at: now)
    }

    private func close(status: MatchStatus, at now: Date) {
        match.status = status
        match.endedAt = now

        // Denormalise onto MatchSide so the common stats queries never replay the log (§7.2).
        let result = TeamEngine.outcome(state, rules: rules, at: now)
        for side in match.orderedSides {
            side.finalScore = state.side(side.slotIndex)?.score ?? 0
            side.resultRank = result?.rankBySlot[side.slotIndex]
            side.outcome = status == .finished
                ? (result?.outcome(forSlot: side.slotIndex) ?? .unfinished)
                : .unfinished
        }

        writeSnapshot()
        save()
    }

    // MARK: - Persistence

    private func append(_ action: EngineAction, at now: Date) {
        // The clock is read *before* the action is applied, so the event records the game time at
        // which it happened rather than the time it produced (§13.2).
        let event = ScoreEvent(
            index: match.nextEventIndex,
            timestamp: now,
            matchClock: board(at: now).primaryClock.value,
            period: state.period,
            kind: action.eventKind,
            slotIndex: action.eventSlotIndex,
            attributedPlayerID: action.eventPlayerID,
            value: action.eventValue,
            note: action.eventNote
        )
        event.match = match
        context.insert(event)
    }

    /// Rebuilds state from the log, resuming from a valid snapshot where one exists.
    private func rebuild() {
        let events = match.orderedEvents

        var snapshot: (state: TeamState, upToIndex: Int)?
        if MatchReplay.isSnapshotValid(upToIndex: match.snapshotEventIndex, events: events),
           let blob = match.stateBlob,
           let decoded = try? JSONDecoder().decode(TeamState.self, from: blob) {
            snapshot = (decoded, match.snapshotEventIndex)
        }

        state = MatchReplay.state(
            TeamEngine.self,
            rules: rules,
            sideCount: max(2, match.orderedSides.count),
            events: events,
            snapshot: snapshot
        )
    }

    private func snapshotIfDue() {
        let count = match.events?.count ?? 0
        guard count > 0, count % Self.snapshotInterval == 0 else { return }
        writeSnapshot()
    }

    private func writeSnapshot() {
        guard let blob = try? JSONEncoder().encode(state) else { return }
        match.stateBlob = blob
        match.snapshotEventIndex = match.orderedEvents.last?.index ?? 0
    }

    private func save() {
        do {
            try context.save()
        } catch {
            // Never fatal mid-match: the in-memory state is still correct and the operator can keep
            // scoring. Losing the log is bad; losing the game in progress would be worse.
            Self.logger.error("Failed to save match: \(String(describing: error), privacy: .public)")
        }
    }
}
