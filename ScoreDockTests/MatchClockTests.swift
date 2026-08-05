import Foundation
import Testing

@testable import ScoreDock

/// §6.4 and risk #9. A scoreboard whose clock drifts, or stalls when the app is backgrounded, has
/// lost the only thing it was for. These tests are the guarantee.
@Suite("Match clock (§6.4)")
struct MatchClockTests {
    /// A fixed reference instant, so every test is reproducible.
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func at(_ seconds: TimeInterval) -> Date {
        Self.t0.addingTimeInterval(seconds)
    }

    @Test("A stopped clock does not advance")
    func stoppedClockHolds() {
        let clock = MatchClock(accumulated: 42)
        #expect(!clock.isRunning)
        #expect(clock.elapsed(at: at(0)) == 42)
        // No matter how much wall time passes.
        #expect(clock.elapsed(at: at(10_000)) == 42)
    }

    @Test("A running clock is a pure function of the instant you ask")
    func runningClockIsDerived() {
        var clock = MatchClock()
        clock.start(at: at(0))

        #expect(clock.elapsed(at: at(0)) == 0)
        #expect(clock.elapsed(at: at(1)) == 1)
        #expect(clock.elapsed(at: at(90)) == 90)
        // Asking twice does not advance it — nothing is being counted.
        #expect(clock.elapsed(at: at(90)) == 90)
    }

    /// The property a `Timer`-based clock cannot have: the app is not running, nothing ticks, and
    /// the clock is still exactly right on return.
    @Test("Backgrounding for ten minutes costs nothing")
    func survivesBackgrounding() {
        var clock = MatchClock()
        clock.start(at: at(0))
        // …app is suspended; no code executes at all…
        #expect(clock.elapsed(at: at(600)) == 600)
    }

    /// A tick-accumulating clock loses a fraction on every start/stop. This one cannot.
    @Test("A hundred start/stop cycles accumulate no drift")
    func noDriftAcrossManyCycles() {
        var clock = MatchClock()
        var cursor: TimeInterval = 0

        // 100 cycles of 3s running, 7s stopped.
        for _ in 0 ..< 100 {
            clock.start(at: at(cursor))
            cursor += 3
            clock.stop(at: at(cursor))
            cursor += 7
        }

        #expect(clock.elapsed(at: at(cursor)) == 300)
        #expect(!clock.isRunning)
    }

    @Test("Stopping banks exactly the elapsed time")
    func stopBanks() {
        var clock = MatchClock()
        clock.start(at: at(0))
        clock.stop(at: at(12.5))
        #expect(clock.accumulated == 12.5)
        #expect(clock.elapsed(at: at(999)) == 12.5)
    }

    @Test("Redundant start and stop calls are no-ops")
    func redundantCallsAreIgnored() {
        var clock = MatchClock()
        clock.start(at: at(0))
        clock.start(at: at(50))       // already running — must not re-anchor
        #expect(clock.elapsed(at: at(100)) == 100)

        clock.stop(at: at(100))
        clock.stop(at: at(200))       // already stopped — must not bank again
        #expect(clock.elapsed(at: at(300)) == 100)
    }

    @Test("Toggle alternates run state")
    func toggle() {
        var clock = MatchClock()
        clock.toggle(at: at(0))
        #expect(clock.isRunning)
        clock.toggle(at: at(10))
        #expect(!clock.isRunning)
        #expect(clock.elapsed(at: at(60)) == 10)
    }

    @Test("Setting elapsed re-anchors a running clock instead of jumping")
    func setElapsedReanchors() {
        var clock = MatchClock()
        clock.start(at: at(0))
        clock.setElapsed(100, at: at(30))

        #expect(clock.isRunning)
        #expect(clock.elapsed(at: at(30)) == 100)
        // Continues from the new value rather than re-adding the original run.
        #expect(clock.elapsed(at: at(35)) == 105)
    }

    @Test("Reset can leave the clock stopped or running")
    func reset() {
        var clock = MatchClock(accumulated: 500)
        clock.reset(at: at(0))
        #expect(clock.elapsed(at: at(10)) == 0)
        #expect(!clock.isRunning)

        clock.reset(to: 20, running: true, at: at(0))
        #expect(clock.elapsed(at: at(5)) == 25)
    }

    /// If the device clock moves backwards mid-match, freezing is the safe failure — rewinding the
    /// game clock would be worse.
    @Test("A backwards system time change freezes rather than rewinds")
    func backwardsTimeJumpDoesNotRewind() {
        var clock = MatchClock()
        clock.start(at: at(100))
        #expect(clock.elapsed(at: at(50)) == 0)
        #expect(clock.elapsed(at: at(100)) == 0)
        #expect(clock.elapsed(at: at(130)) == 30)
    }

    @Test("Negative accumulated values are clamped away")
    func negativeAccumulatedClamped() {
        #expect(MatchClock(accumulated: -50).elapsed(at: at(0)) == 0)
    }

    // MARK: Buzzer scheduling

    @Test("Expiry is an absolute instant, for scheduling the buzzer")
    func expiryInstant() {
        var clock = MatchClock()
        #expect(clock.expiry(after: 600, at: at(0)) == nil, "a stopped clock never expires")

        clock.start(at: at(0))
        #expect(clock.expiry(after: 600, at: at(0)) == at(600))
        #expect(clock.expiry(after: 600, at: at(500)) == at(600))
        #expect(clock.expiry(after: 600, at: at(700)) == nil, "already past")
    }

    // MARK: Formatting

    @Test("Clock formatting matches venue conventions")
    func formatting() {
        // Whole seconds round up, so 0:00 genuinely means zero.
        #expect(ClockDisplay.format(600, showsTenths: false) == "10:00")
        #expect(ClockDisplay.format(59.4, showsTenths: false) == "01:00")
        #expect(ClockDisplay.format(0, showsTenths: false) == "00:00")
        #expect(ClockDisplay.format(3661, showsTenths: false) == "1:01:01")

        // Under a minute with tenths, a real board drops the minutes field.
        #expect(ClockDisplay.format(9.47, showsTenths: true) == "09.4")
        #expect(ClockDisplay.format(59.99, showsTenths: true) == "59.9")
        #expect(ClockDisplay.format(75.3, showsTenths: true) == "1:15.3")

        // Never negative.
        #expect(ClockDisplay.format(-5, showsTenths: false) == "00:00")
    }

    /// A shot clock never shows a minutes field on a real venue board.
    @Test("Shot clocks format as bare seconds")
    func secondsOnlyFormatting() {
        #expect(ClockDisplay.format(24, showsTenths: false, style: .secondsOnly) == "24")
        #expect(ClockDisplay.format(14, showsTenths: false, style: .secondsOnly) == "14")
        #expect(ClockDisplay.format(0, showsTenths: false, style: .secondsOnly) == "0")
        // Tenths in the last five seconds, which is when they matter.
        #expect(ClockDisplay.format(4.67, showsTenths: true, style: .secondsOnly) == "4.6")
        #expect(ClockDisplay.format(0.4, showsTenths: true, style: .secondsOnly) == "0.4")
    }

    @Test("Formatting uses only glyphs DSEG7 can draw")
    func formattingStaysWithinBoardFont() {
        // DSEG7 has digits, ':' and '.', but no '/' (§2.1).
        let samples = [0.0, 9.4, 59.9, 75.3, 600, 3661]
        for showsTenths in [true, false] {
            for sample in samples {
                let text = ClockDisplay.format(sample, showsTenths: showsTenths)
                let allowed = Set("0123456789:.")
                #expect(text.allSatisfy { allowed.contains($0) }, "unrenderable glyph in \(text)")
            }
        }
    }
}
