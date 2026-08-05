import Foundation

/// A date-anchored clock.
///
/// **§6.4, and it is non-negotiable.** Do not decrement a stored value on a `Timer` tick. Drift
/// accumulates, and backgrounding stops the timer entirely — which in a scoreboard is a fatal
/// credibility bug (§17, risk 9).
///
/// Instead the clock stores *when it started* and *how much time it had banked before that*.
/// Elapsed is always derived, never mutated by the passage of time. Backgrounding, a phone call,
/// a locked screen and a force-quit therefore cost nothing: the clock is correct the instant the
/// app comes back, because nothing was ever counting.
///
/// The anchor is a wall-clock `Date` rather than a monotonic uptime reading. That is deliberate and
/// specified: `Date` survives process death, which is what makes crash recovery (§12) possible —
/// uptime would not survive a reboot. The trade-off is that a system time change can move the
/// anchor, so `elapsed(at:)` clamps the current run to be non-negative: a backwards time jump
/// freezes the clock rather than rewinding the score.
struct MatchClock: Codable, Sendable, Hashable {
    /// Time banked from previous runs. Only ever changes when the clock is stopped or set.
    private(set) var accumulated: TimeInterval

    /// When the current run began, or nil when stopped.
    private(set) var startedAt: Date?

    init(accumulated: TimeInterval = 0, startedAt: Date? = nil) {
        self.accumulated = max(0, accumulated)
        self.startedAt = startedAt
    }

    var isRunning: Bool { startedAt != nil }

    /// Total elapsed time. The only way to read this clock.
    func elapsed(at now: Date) -> TimeInterval {
        guard let startedAt else { return accumulated }
        return accumulated + max(0, now.timeIntervalSince(startedAt))
    }

    // MARK: Mutation

    mutating func start(at now: Date) {
        guard !isRunning else { return }
        startedAt = now
    }

    mutating func stop(at now: Date) {
        guard isRunning else { return }
        accumulated = elapsed(at: now)
        startedAt = nil
    }

    mutating func toggle(at now: Date) {
        isRunning ? stop(at: now) : start(at: now)
    }

    /// Sets elapsed time directly, preserving whether the clock is running.
    ///
    /// Re-anchors to `now` so a running clock continues from the new value rather than jumping.
    mutating func setElapsed(_ value: TimeInterval, at now: Date) {
        accumulated = max(0, value)
        if isRunning { startedAt = now }
    }

    mutating func reset(to value: TimeInterval = 0, running: Bool = false, at now: Date) {
        accumulated = max(0, value)
        startedAt = running ? now : nil
    }

    /// The wall-clock instant this clock will reach `duration`, or nil if it is stopped.
    ///
    /// Buzzer scheduling is a separate concern from rendering (§6.4): the period-end sound is
    /// scheduled against this absolute time so it fires accurately even when the UI is throttled
    /// — by the background, by Low Power Mode, or by thermal throttling (§12). Consumed in M2.
    func expiry(after duration: TimeInterval, at now: Date) -> Date? {
        guard isRunning else { return nil }
        let remaining = duration - elapsed(at: now)
        guard remaining > 0 else { return nil }
        return now.addingTimeInterval(remaining)
    }
}

// MARK: - Display

/// A clock as the board renders it.
struct ClockDisplay: Sendable, Hashable {
    /// How the number is written.
    enum Style: Sendable, Hashable {
        /// `MM:SS`, or `H:MM:SS` past an hour. The match clock.
        case minutesSeconds
        /// Bare seconds — `24`, `14`, `5.3`. A shot clock never shows a minutes field, on any real
        /// venue board.
        case secondsOnly
    }

    /// The number to show, already adjusted for count direction — remaining for a countdown,
    /// elapsed for a count-up. Never negative.
    var value: TimeInterval
    var isRunning: Bool
    var showsTenths: Bool

    /// A countdown that has reached zero, or a count-up past its period length (added time).
    var hasExpired: Bool

    var style: Style = .minutesSeconds

    /// Board text. Uses only glyphs DSEG7 can draw — digits, `:` and `.` — and never `/` (§2.1).
    var formatted: String {
        Self.format(value, showsTenths: showsTenths, style: style)
    }

    static func format(
        _ interval: TimeInterval,
        showsTenths: Bool,
        style: Style = .minutesSeconds
    ) -> String {
        if style == .secondsOnly {
            let clamped = max(0, interval)
            if showsTenths {
                let tenths = (clamped * 10).rounded(.down)
                return String(format: "%d.%01d", Int(tenths) / 10, Int(tenths) % 10)
            }
            return "\(Int(clamped.rounded(.up)))"
        }
        return formatMinutesSeconds(interval, showsTenths: showsTenths)
    }

    private static func formatMinutesSeconds(_ interval: TimeInterval, showsTenths: Bool) -> String {
        let clamped = max(0, interval)

        if showsTenths {
            // Under a minute a real scoreboard drops the minutes field and shows SS.T — that is
            // the format an operator expects in the last seconds of a period.
            if clamped < 60 {
                let tenths = (clamped * 10).rounded(.down)
                return String(format: "%02d.%01d", Int(tenths) / 10, Int(tenths) % 10)
            }
            let total = (clamped * 10).rounded(.down) / 10
            let minutes = Int(total) / 60
            let seconds = Int(total) % 60
            let tenth = Int((total * 10).rounded(.down)) % 10
            return String(format: "%d:%02d.%01d", minutes, seconds, tenth)
        }

        // Round up so a countdown shows 1:00 until it is genuinely below a minute, matching how
        // venue scoreboards behave — 0:00 must mean zero, not "less than half a second left".
        let total = Int(clamped.rounded(.up))
        let hours = total / 3600
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, (total % 3600) / 60, total % 60)
        }
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
