import Foundation

/// Rebuilds engine state by replaying the event log (§6.6).
///
/// Replay is the source of truth for undo and for crash recovery. The key property that makes it
/// exact rather than approximate: **each event is applied at its own recorded `timestamp`**, not at
/// the current time. Because every clock is date-anchored (§6.4), replaying with the original
/// timestamps reproduces the original anchors, so a rebuilt clock is not merely close — it is the
/// same clock.
enum MatchReplay {
    /// Indices of events that an *effective* undo has cancelled.
    ///
    /// Undo/redo is unlimited, which means an undo can itself be undone. Resolving that needs a
    /// recursive definition rather than a single forward pass: an event is cancelled only if some
    /// undo targeting it is itself still in force.
    ///
    /// Worked example — score at 3, undo at 5 targeting 3, undo at 7 targeting 5. A naive forward
    /// pass marks both 3 and 5 cancelled and loses the score. Here, event 7 cancels event 5, which
    /// means 5 no longer cancels 3, so the score is correctly live again. That is redo.
    static func undoneIndices(in events: [ScoreEvent]) -> Set<Int> {
        // Undo events always target strictly earlier indices, so this recursion terminates; the
        // memo also guards against a malformed log containing a cycle.
        var undosTargeting: [Int: [Int]] = [:]
        for event in events where event.kind == .undo {
            undosTargeting[event.value, default: []].append(event.index)
        }
        guard !undosTargeting.isEmpty else { return [] }

        var memo: [Int: Bool] = [:]
        func isEffective(_ index: Int) -> Bool {
            if let cached = memo[index] { return cached }
            memo[index] = true
            let cancelled = (undosTargeting[index] ?? []).contains { isEffective($0) }
            memo[index] = !cancelled
            return !cancelled
        }

        var undone: Set<Int> = []
        for event in events where event.kind != .undo {
            if !isEffective(event.index) { undone.insert(event.index) }
        }
        return undone
    }

    /// The event a fresh undo should target: the most recent mutation still in force.
    static func nextUndoTarget(in events: [ScoreEvent]) -> ScoreEvent? {
        let undone = undoneIndices(in: events)
        return events
            .filter { $0.kind != .undo && !undone.contains($0.index) }
            .max { $0.index < $1.index }
    }

    /// The undo event a redo should cancel: the most recent undo still in force.
    static func nextRedoTarget(in events: [ScoreEvent]) -> ScoreEvent? {
        let undone = undoneIndices(in: events)
        return events
            .filter { $0.kind == .undo && !undone.contains($0.index) }
            .max { $0.index < $1.index }
    }

    /// Replays the log into engine state.
    ///
    /// `snapshot` is the §6.6 optimisation — resume from a stored state instead of replaying from
    /// ball one, which matters in a long cricket innings. Callers must not pass a snapshot whose
    /// index is at or after any undone event; `LiveMatchStore` drops the snapshot on undo rather
    /// than trying to repair it.
    static func state<Engine: ScoreEngine>(
        _ engine: Engine.Type,
        rules: Engine.Rules,
        sideCount: Int,
        events: [ScoreEvent],
        snapshot: (state: Engine.State, upToIndex: Int)? = nil
    ) -> Engine.State {
        let ordered = events.sorted { $0.index < $1.index }
        let undone = undoneIndices(in: ordered)

        var state = snapshot?.state ?? engine.initialState(rules: rules, sideCount: sideCount)
        let startIndex = snapshot?.upToIndex ?? Int.min

        for event in ordered {
            guard event.index > startIndex else { continue }
            guard !undone.contains(event.index) else { continue }
            guard let action = event.engineAction else { continue }
            engine.apply(action, to: &state, rules: rules, at: event.timestamp)
        }
        return state
    }

    /// Whether a stored snapshot is still valid given the log's undo history.
    static func isSnapshotValid(upToIndex: Int, events: [ScoreEvent]) -> Bool {
        guard upToIndex > 0 else { return false }
        return !undoneIndices(in: events).contains { $0 <= upToIndex }
    }
}
