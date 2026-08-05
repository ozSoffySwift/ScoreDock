import Foundation

/// One side's mutable match state.
struct TeamSideState: Codable, Sendable, Hashable {
    var score: Int = 0
    /// Team fouls as the board displays them. Reset per period when the rules say so.
    var fouls: Int = 0
    var timeoutsUsed: Int = 0

    init(score: Int = 0, fouls: Int = 0, timeoutsUsed: Int = 0) {
        self.score = score
        self.fouls = fouls
        self.timeoutsUsed = timeoutsUsed
    }
}

/// The team engine's complete state (§6.1).
///
/// Everything here is a value, and every clock is date-anchored — so encoding this to
/// `Match.stateBlob` and decoding it after a crash restores the operator to exactly where they
/// were, including a clock that has kept correct time while the app was dead (§12).
struct TeamState: Codable, Sendable, Hashable {
    var sides: [TeamSideState]
    var period: Int = 1

    /// OT / SO / HT / F. Overrides the rules' labelling when regulation labels do not fit (§4.2).
    var periodLabelOverride: String?

    /// Elapsed time within the current period. Direction is a rendering concern, not a storage one:
    /// a countdown is `periodLength - elapsed`.
    var clock: MatchClock = MatchClock()

    var shotClock: MatchClock = MatchClock()
    /// The value the shot clock was last reset to — full or short — since the two differ (§4.2).
    var shotClockDuration: TimeInterval = 24

    /// Non-nil while a break is running. The break *replaces* the main timer, which stays paused at
    /// exactly its current value and resumes from there (§6.1).
    var breakClock: MatchClock?
    var breakDuration: TimeInterval = 0

    var possessionSlot: Int?
    var isFinished: Bool = false

    init(sideCount: Int = 2, shotClockDuration: TimeInterval = 24) {
        sides = Array(repeating: TeamSideState(), count: max(1, sideCount))
        self.shotClockDuration = shotClockDuration
    }

    /// Safe accessor — an out-of-range slot from a corrupted log must not trap.
    func side(_ slot: Int) -> TeamSideState? {
        sides.indices.contains(slot) ? sides[slot] : nil
    }

    var isOnBreak: Bool { breakClock != nil }
}
