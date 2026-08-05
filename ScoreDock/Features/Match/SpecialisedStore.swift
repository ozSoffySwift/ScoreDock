import Foundation
import OSLog
import SwiftData
import SwiftUI

/// The running-match store for the five bespoke boards (§6.3).
///
/// Fourth sibling of `LiveMatchStore`, `SetMatchStore` and `ListStore` — and the fourth case the M4
/// note said to wait for. Having now seen all four, the duplication is genuinely thin: the hard
/// parts (undo resolution, snapshot validity, action coding) already live in `MatchReplay` and
/// `EventCoding`, and what repeats is roughly thirty lines of orchestration that differ in their
/// engine type. Extracting a generic base would trade that for a protocol with four associated
/// types and no behaviour of its own, so the sibling shape stays.
///
/// The one thing this store does that the others do not is `checkForTimeExpiry`: a chess flag falls
/// with no action to trigger it, so *nothing happens* at the moment the game is decided unless
/// something is watching the clock.
@Observable
@MainActor
final class SpecialisedStore: Identifiable {
    nonisolated let id = UUID()

    let match: Match
    let rules: SpecialisedRules
    let theme: ThemeSpec

    private(set) var state: SpecialisedState

    var onAction: ((EngineAction) -> Void)?

    private let context: ModelContext
    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "match")
    private static let snapshotInterval = 50

    init?(match: Match, context: ModelContext) {
        guard let rules = match.rulesSnapshot?.specialisedRules else {
            Self.logger.error("Match \(match.id) has no specialised rules; cannot open.")
            return nil
        }
        guard SpecialisedEngine.implementedBoards.contains(rules.board) else {
            Self.logger.error("Board \(rules.board.rawValue) is not implemented in this build.")
            return nil
        }
        self.match = match
        self.rules = rules
        self.context = context
        self.theme = match.themeSnapshot ?? BuiltInThemes.theme(id: nil)
        self.state = SpecialisedEngine.initialState(rules: rules, sideCount: match.orderedSides.count)
        rebuild()
    }

    // MARK: Reading

    func board(at now: Date = .now) -> DerivedSpecialisedBoard {
        SpecialisedEngine.derived(state, rules: rules, at: now)
    }

    var sides: [MatchSide] { match.orderedSides }
    var canUndo: Bool { MatchReplay.nextUndoTarget(in: match.orderedEvents) != nil }
    var canRedo: Bool { MatchReplay.nextRedoTarget(in: match.orderedEvents) != nil }

    // MARK: Performing

    func perform(_ action: EngineAction, at now: Date = .now) {
        guard !state.isFinished else { return }

        append(action, at: now)
        SpecialisedEngine.apply(action, to: &state, rules: rules, at: now)

        if match.status == .setup { match.status = .live }
        if state.isFinished { close(status: .finished, at: now) }
        snapshotIfDue()
        save()
        onAction?(action)
    }

    /// Stops the main clock when a countdown reaches zero.
    ///
    /// A quarter that runs out has to stop itself, and the stop is logged like any other action so
    /// the play-by-play shows a clock that expired rather than one that simply went quiet (§13.3).
    func stopClockIfRunning(at now: Date = .now) {
        guard !state.isFinished else { return }
        guard state.americanFootball?.clock.isRunning == true else { return }
        perform(.toggleClock, at: now)
    }

    /// Ends the game the moment a clock runs out, when the rules say it should.
    ///
    /// Every other board in the app changes only when the operator taps something, so the event log
    /// is naturally complete. A chess flag is the exception: it falls on its own, and if nothing
    /// noticed, the log would show a game that simply stopped. Called from the board's tick, so the
    /// finish is recorded as a real event with a real timestamp — which is what keeps undo and the
    /// play-by-play honest.
    func checkForTimeExpiry(at now: Date = .now) {
        guard !state.isFinished else { return }
        guard case let .chessClock(board) = board(at: now) else { return }
        guard board.flaggedSlot != nil, rules.chessClock?.flagEndsGame ?? true else { return }
        perform(.finishMatch, at: now)
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

        let result = SpecialisedEngine.outcome(state, rules: rules, at: now)

        for side in match.orderedSides {
            side.finalScore = finalScore(forSlot: side.slotIndex, at: now)
            side.resultRank = result?.rankBySlot[side.slotIndex]
            // A chess game with no flag has no result this app can claim, so `result` is nil and
            // every side stays `.unfinished` — see `ChessClockEngine.outcome`.
            side.outcome = status == .finished
                ? (result?.outcome(forSlot: side.slotIndex) ?? .unfinished)
                : .unfinished
        }

        writeSnapshot()
        save()
    }

    /// The one number worth denormalising per board (§7.2).
    ///
    /// It has to be the number the share card can print as a score, because that is what §13.5 does
    /// with it. For a chess clock that is the **result**, written the way chess writes it: 1–0 to
    /// whoever is left standing, and 0–0 for a game with no flag, whose sides are `.unfinished`.
    /// Move count was the first thing tried here and it was actively misleading — a 12-move game
    /// each way produced a card reading "12 – 12", which looks like a drawn score.
    private func finalScore(forSlot slot: Int, at now: Date) -> Int {
        switch board(at: now) {
        case .chessClock:
            let result = SpecialisedEngine.outcome(state, rules: rules, at: now)
            return result?.winningSlots.contains(slot) == true ? 1 : 0
        case let .raceTimer(board):
            // Laps completed is the race's real count, and it prints as a score sensibly — "12 – 11"
            // is a lap board. The finishing *times* are on the board and in the log.
            return board.rows.first { $0.slotIndex == slot }?.lapsCompleted ?? 0
        case let .americanFootball(board):
            return board.sides.first { $0.slotIndex == slot }?.score ?? 0
        case .cricket:
            // Runs aggregated across a side's innings, which is what decides a cricket match and
            // what a share card should print.
            guard let cricket = state.cricket else { return 0 }
            return cricket.innings.filter { $0.battingSlot == slot }.reduce(0) { $0 + $1.runs }
        case let .baseball(board):
            return board.sides.first { $0.slotIndex == slot }?.runs ?? 0
        case .unavailable:
            return 0
        }
    }

    // MARK: Persistence

    private func append(_ action: EngineAction, at now: Date) {
        let event = ScoreEvent(
            index: match.nextEventIndex,
            timestamp: now,
            matchClock: 0,
            period: 1,
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

        var snapshot: (state: SpecialisedState, upToIndex: Int)?
        if MatchReplay.isSnapshotValid(upToIndex: match.snapshotEventIndex, events: events),
           let blob = match.stateBlob,
           let decoded = try? JSONDecoder().decode(SpecialisedState.self, from: blob) {
            snapshot = (decoded, match.snapshotEventIndex)
        }

        state = MatchReplay.state(
            SpecialisedEngine.self,
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
