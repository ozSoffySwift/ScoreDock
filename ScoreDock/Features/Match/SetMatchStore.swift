import Foundation
import OSLog
import SwiftData
import SwiftUI

/// The running-match store for the set-match engine (§6.2).
///
/// A sibling of `LiveMatchStore` rather than a generic over both. The genuinely tricky parts —
/// undo resolution, snapshot validity, action/event coding — already live in `MatchReplay` and
/// `EventCoding` and are shared; what is duplicated here is the thin orchestration around them.
/// That is a deliberate call: abstracting on the second instance would mean guessing at the shape
/// the specialised engines (§6.3) need, and they are the ones most likely to break the guess.
@Observable
@MainActor
final class SetMatchStore: Identifiable {
    nonisolated let id = UUID()

    let match: Match
    let rules: SetMatchRules
    let theme: ThemeSpec

    private(set) var state: SetMatchState

    var onAction: ((EngineAction) -> Void)?

    private let context: ModelContext
    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "match")
    private static let snapshotInterval = 50

    init?(match: Match, context: ModelContext) {
        guard let rules = match.rulesSnapshot?.setMatchRules else {
            Self.logger.error("Match \(match.id) has no set-match rules; cannot open.")
            return nil
        }
        self.match = match
        self.rules = rules
        self.context = context
        self.theme = match.themeSnapshot ?? BuiltInThemes.theme(id: nil)
        self.state = SetMatchEngine.initialState(rules: rules, sideCount: max(2, match.orderedSides.count))
        rebuild()
    }

    // MARK: Reading

    func board() -> DerivedSetMatchBoard {
        SetMatchEngine.derived(state, rules: rules, at: .now)
    }

    var sides: [MatchSide] { match.orderedSides }
    var canUndo: Bool { MatchReplay.nextUndoTarget(in: match.orderedEvents) != nil }
    var canRedo: Bool { MatchReplay.nextRedoTarget(in: match.orderedEvents) != nil }

    // MARK: Performing

    func perform(_ action: EngineAction, at now: Date = .now) {
        guard !state.isFinished else { return }

        append(action, at: now)
        SetMatchEngine.apply(action, to: &state, rules: rules, at: now)

        if match.status == .setup { match.status = .live }
        snapshotIfDue()
        save()
        onAction?(action)

        // A set-match ends itself: there is no clock to run out, so reaching the target set count
        // *is* the final whistle.
        if state.isFinished { close(status: .finished, at: now) }
    }

    // MARK: Undo

    func undo(at now: Date = .now) {
        guard let target = MatchReplay.nextUndoTarget(in: match.orderedEvents) else { return }
        recordUndo(of: target.index, at: now)
    }

    func redo(at now: Date = .now) {
        guard let target = MatchReplay.nextRedoTarget(in: match.orderedEvents) else { return }
        recordUndo(of: target.index, at: now)
    }

    private func recordUndo(of targetIndex: Int, at now: Date) {
        let event = ScoreEvent(
            index: match.nextEventIndex,
            timestamp: now,
            period: state.currentSetNumber,
            kind: .undo,
            value: targetIndex
        )
        event.match = match
        context.insert(event)

        if targetIndex <= match.snapshotEventIndex {
            match.stateBlob = nil
            match.snapshotEventIndex = 0
        }

        // Undo can reopen a match the engine had already ended — which for a rally sport is the
        // most likely thing an operator needs, having awarded the winning point by mistake.
        if match.status == .finished {
            match.status = .live
            match.endedAt = nil
        }

        rebuild()
        save()
    }

    // MARK: Finishing

    func finish(at now: Date = .now) {
        perform(.finishMatch, at: now)
        close(status: .finished, at: now)
    }

    func abandon(at now: Date = .now) {
        perform(.finishMatch, at: now)
        close(status: .abandoned, at: now)
    }

    private func close(status: MatchStatus, at now: Date) {
        match.status = status
        match.endedAt = now

        let result = SetMatchEngine.outcome(state, rules: rules, at: now)
        for side in match.orderedSides {
            // Sets won is the result, not points — a player can win fewer total points and still
            // take the match, which is the whole character of set scoring.
            side.finalScore = state.side(side.slotIndex)?.setsWon ?? 0
            side.finalSets = state.completedSets.map { $0.indices.contains(side.slotIndex) ? $0[side.slotIndex] : 0 }
            side.resultRank = result?.rankBySlot[side.slotIndex]
            side.outcome = status == .finished
                ? (result?.outcome(forSlot: side.slotIndex) ?? .unfinished)
                : .unfinished
        }

        writeSnapshot()
        save()
    }

    // MARK: Persistence

    private func append(_ action: EngineAction, at now: Date) {
        let event = ScoreEvent(
            index: match.nextEventIndex,
            timestamp: now,
            // No match clock in a rally sport; the set number carries the "when in the game" role
            // that §13.2 asks for.
            matchClock: 0,
            period: state.currentSetNumber,
            kind: action.eventKind,
            slotIndex: action.eventSlotIndex,
            attributedPlayerID: action.eventPlayerID,
            value: action.eventValue,
            note: action.eventNote
        )
        event.match = match
        context.insert(event)
    }

    private func rebuild() {
        let events = match.orderedEvents

        var snapshot: (state: SetMatchState, upToIndex: Int)?
        if MatchReplay.isSnapshotValid(upToIndex: match.snapshotEventIndex, events: events),
           let blob = match.stateBlob,
           let decoded = try? JSONDecoder().decode(SetMatchState.self, from: blob) {
            snapshot = (decoded, match.snapshotEventIndex)
        }

        state = MatchReplay.state(
            SetMatchEngine.self,
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
            Self.logger.error("Failed to save match: \(String(describing: error), privacy: .public)")
        }
    }
}
