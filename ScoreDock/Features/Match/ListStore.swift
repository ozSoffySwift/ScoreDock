import Foundation
import OSLog
import SwiftData
import SwiftUI

/// The running-match store for list and table boards (§6.5).
///
/// Third sibling of `LiveMatchStore` and `SetMatchStore`. The pattern has now repeated three times
/// and is stable, so extracting a shared generic base is worth doing at M6 — when the specialised
/// engines arrive and there is a fourth case to generalise *from* rather than *toward*.
@Observable
@MainActor
final class ListStore: Identifiable {
    nonisolated let id = UUID()

    let match: Match
    let rules: ListRules
    let theme: ThemeSpec

    private(set) var state: ListState

    var onAction: ((EngineAction) -> Void)?

    private let context: ModelContext
    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "match")
    private static let snapshotInterval = 50

    init?(match: Match, context: ModelContext) {
        guard let rules = match.rulesSnapshot?.listRules else {
            Self.logger.error("Match \(match.id) has no list rules; cannot open.")
            return nil
        }
        self.match = match
        self.rules = rules
        self.context = context
        self.theme = match.themeSnapshot ?? BuiltInThemes.theme(id: nil)
        self.state = ListEngine.initialState(rules: rules, sideCount: match.orderedSides.count)
        rebuild()
    }

    // MARK: Reading

    func board() -> DerivedListBoard {
        ListEngine.derived(state, rules: rules, at: .now)
    }

    var sides: [MatchSide] { match.orderedSides }
    var canUndo: Bool { MatchReplay.nextUndoTarget(in: match.orderedEvents) != nil }
    var canRedo: Bool { MatchReplay.nextRedoTarget(in: match.orderedEvents) != nil }

    // MARK: Performing

    func perform(_ action: EngineAction, at now: Date = .now) {
        guard !state.isFinished else { return }

        append(action, at: now)
        ListEngine.apply(action, to: &state, rules: rules, at: now)

        if match.status == .setup { match.status = .live }
        snapshotIfDue()
        save()
        onAction?(action)
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
            period: state.currentRound + 1,
            kind: .undo,
            value: targetIndex
        )
        event.match = match
        context.insert(event)

        if targetIndex <= match.snapshotEventIndex {
            match.stateBlob = nil
            match.snapshotEventIndex = 0
        }
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

        let derived = ListEngine.derived(state, rules: rules, at: now)
        let result = ListEngine.outcome(state, rules: rules, at: now)

        for side in match.orderedSides {
            let row = derived.rows.first { $0.slotIndex == side.slotIndex }
            // Standings are ranked on points; everything else on the total entered.
            side.finalScore = rules.style == .standings ? (row?.points ?? 0) : (row?.total ?? 0)
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
            matchClock: 0,
            // No clock and no periods here; the round carries the "when in the game" role (§13.2).
            period: state.currentRound + 1,
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

        var snapshot: (state: ListState, upToIndex: Int)?
        if MatchReplay.isSnapshotValid(upToIndex: match.snapshotEventIndex, events: events),
           let blob = match.stateBlob,
           let decoded = try? JSONDecoder().decode(ListState.self, from: blob) {
            snapshot = (decoded, match.snapshotEventIndex)
        }

        state = MatchReplay.state(
            ListEngine.self,
            rules: rules,
            sideCount: match.orderedSides.count,
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
