import Foundation
import SwiftUI

/// Drives sound and haptics from match state (§11).
///
/// **Sounds are scheduled against wall-clock time, not fired from a UI tick.** §6.4 is explicit
/// about this: the period-end buzzer is armed for the absolute instant the clock will reach zero,
/// so it lands on time even when the UI is throttled — by Low Power Mode, by thermal throttling
/// (§12), or simply because the board dropped to 1 Hz. A buzzer driven from a render pass is a
/// buzzer that is late exactly when the gym is loudest.
///
/// `rearm` is idempotent: it cancels everything and re-schedules from current state, so callers can
/// invoke it on any state change without tracking what changed.
@Observable
@MainActor
final class MatchFeedback {
    /// Quick-mute from the board toolbar (§11.1). Separate from the Settings master switch so an
    /// operator can silence a match without changing their preferences.
    var isQuickMuted = false

    private var scheduled: [Task<Void, Never>] = []
    private var settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        MatchAudio.shared.prepare()
        MatchHaptics.shared.prepare()
    }

    // MARK: Scheduling

    func rearm(for store: LiveMatchStore, at now: Date = .now) {
        rearm(with: Self.cues(
            state: store.state,
            rules: store.rules,
            preferences: SoundPreferences(settings),
            at: now
        ))
    }

    /// The bespoke boards with an expiring clock (§6.3).
    ///
    /// Football and the chess clock got no scheduled sound at all until this existed: a quarter ran
    /// out in silence, and a flag fell in silence. §11.1 wants the buzzer *scheduled against
    /// absolute time* precisely so it fires when the UI is throttled — which is when a clock is most
    /// likely to expire unwatched. The other three bespoke boards have no expiring clock and
    /// legitimately schedule nothing.
    func rearm(for store: SpecialisedStore, at now: Date = .now) {
        rearm(with: Self.cues(
            state: store.state,
            rules: store.rules,
            preferences: SoundPreferences(settings),
            at: now
        ))
    }

    private func rearm(with cues: [ScheduledCue]) {
        cancel()
        guard soundAllowed else { return }
        for cue in cues { schedule(cue) }
    }

    private func schedule(_ cue: ScheduledCue) {
        let delay = cue.fireAt.timeIntervalSinceNow
        guard delay > 0 else { return }

        scheduled.append(Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.fire(cue.sound)
        })
    }

    private func fire(_ sound: MatchSound) {
        guard soundAllowed else { return }
        MatchAudio.shared.play(sound)
        if sound == .buzzer, hapticsAllowed {
            MatchHaptics.shared.buzzer()
        }
    }

    func cancel() {
        for task in scheduled { task.cancel() }
        scheduled.removeAll()
    }

    // MARK: Immediate feedback

    /// Haptic response to an operator action (§11.2 table). Deliberately silent — the operator's own
    /// taps should not make noise in a venue; only match events do.
    func actionOccurred(_ action: EngineAction) {
        guard hapticsAllowed else { return }

        switch action {
        case let .score(_, points, _):
            // A correction feels different from a score, so a mis-tap is noticeable without looking.
            MatchHaptics.shared.impact(points >= 0 ? .light : .rigid)
        case .toggleClock, .toggleShotClock, .setClockElapsed:
            MatchHaptics.shared.impact(.medium)
        case .advancePeriod, .finishMatch:
            MatchHaptics.shared.notify(.success)
        case .previousPeriod:
            MatchHaptics.shared.impact(.rigid)
        case .startBreak, .endBreak:
            MatchHaptics.shared.impact(.medium)
        case .foul, .timeout, .setPossession, .resetShotClock, .setPeriodLabel, .adjustRecord:
            MatchHaptics.shared.impact(.light)
        case .setBracketWinner:
            // Advancing someone through a bracket is a decision, not a tick — it deserves to feel
            // like one.
            MatchHaptics.shared.notify(.success)
        case let .specialised(action):
            specialisedActionOccurred(action)
        }
    }

    /// §11.2 for the bespoke boards (§6.3).
    ///
    /// The weighting follows how often an action happens and how much it matters: a delivery or a
    /// pitch is tapped hundreds of times an innings and stays light, while a wicket or a finish is a
    /// moment and gets a notification. The chess-clock press is the exception among frequent
    /// actions — a player presses it while looking at the board, so it has to be felt.
    private func specialisedActionOccurred(_ action: SpecialisedAction) {
        switch action {
        case .pressClock:
            MatchHaptics.shared.impact(.medium)
        case .recordLap, .delivery, .pitch, .setBases, .setDownAndDistance, .setBallOn:
            MatchHaptics.shared.impact(.light)
        case .wicket:
            MatchHaptics.shared.notify(.warning)
        case .finishRacer, .endInnings, .advanceHalfInning:
            MatchHaptics.shared.notify(.success)
        }
    }

    func invalidAction() {
        guard hapticsAllowed else { return }
        MatchHaptics.shared.notify(.error)
    }

    // MARK: Gates

    private var soundAllowed: Bool { settings.soundEnabled && !isQuickMuted }

    /// Reduce Motion is checked by the caller through `applyAccessibility(reduceMotion:)`; the
    /// system's own haptics setting is honoured by `UIFeedbackGenerator` automatically.
    private var hapticsAllowed: Bool { settings.hapticsEnabled && !reduceMotion }

    private var reduceMotion = false

    /// §15: Reduce Motion suppresses non-essential feedback. Sound is unaffected — a referee who
    /// has reduced motion still needs to hear the buzzer.
    func applyAccessibility(reduceMotion: Bool) {
        self.reduceMotion = reduceMotion
    }
}

// MARK: - Schedule computation

/// One sound armed for an absolute instant.
struct ScheduledCue: Hashable, Sendable {
    var sound: MatchSound
    var fireAt: Date
}

/// Which sounds are switched on. A value copy of the relevant `AppSettings` fields, so the
/// scheduling logic below stays pure and testable.
struct SoundPreferences: Hashable, Sendable {
    var buzzer = true
    var shotClockHorn = true
    var shotClockTick = true
    var breakChime = true
    var timerWarning = false

    init() {}

    @MainActor
    init(_ settings: AppSettings) {
        buzzer = settings.buzzerEnabled
        shotClockHorn = settings.shotClockHornEnabled
        shotClockTick = settings.shotClockTickEnabled
        breakChime = settings.breakChimeEnabled
        timerWarning = settings.timerWarningEnabled
    }
}

extension MatchFeedback {
    /// Every sound that should fire, and exactly when — computed, not observed.
    ///
    /// Pure and time-injected, so the §6.4 requirement that the buzzer land on the wall-clock
    /// instant the clock reaches zero is something tests can assert rather than something you
    /// verify by sitting through a period.
    /// Scheduled sounds for a bespoke board.
    nonisolated static func cues(
        state: SpecialisedState,
        rules: SpecialisedRules,
        preferences: SoundPreferences,
        at now: Date
    ) -> [ScheduledCue] {
        guard !state.isFinished else { return [] }
        var cues: [ScheduledCue] = []

        func add(_ sound: MatchSound, _ target: Date?, enabled: Bool) {
            guard enabled, let target, target > now else { return }
            cues.append(ScheduledCue(sound: sound, fireAt: target))
        }

        switch state.board {
        case .americanFootball:
            guard let board = state.americanFootball else { return [] }
            let footballRules = rules.americanFootball ?? AmericanFootballRules()

            add(.buzzer, board.clock.expiry(after: footballRules.quarterLength, at: now), enabled: preferences.buzzer)
            for lead in [60.0, 10.0] where footballRules.quarterLength > lead {
                add(
                    .warning,
                    board.clock.expiry(after: footballRules.quarterLength - lead, at: now),
                    enabled: preferences.timerWarning
                )
            }
            // The play clock is a shot clock by another name, and gets the same horn.
            add(
                .horn,
                board.playClock.expiry(after: board.playClockDuration, at: now),
                enabled: preferences.shotClockHorn
            )

        case .chessClock:
            guard let board = state.chessClock else { return [] }
            let clockRules = rules.chessClock ?? ChessClockRules()
            // Only the running side can flag, and its limit includes whatever increment it has
            // banked so far.
            for side in board.sides where side.spent.isRunning {
                add(
                    .buzzer,
                    side.spent.expiry(after: clockRules.baseTime + side.bonus, at: now),
                    enabled: preferences.buzzer
                )
            }

        // A race clock counts up with nothing to expire, and neither cricket nor baseball has a
        // clock at all.
        case .raceTimer, .cricket, .baseball:
            break
        }

        return cues
    }

    nonisolated static func cues(
        state: TeamState,
        rules: TeamRules,
        preferences: SoundPreferences,
        at now: Date
    ) -> [ScheduledCue] {
        guard !state.isFinished else { return [] }
        var cues: [ScheduledCue] = []

        func add(_ sound: MatchSound, _ target: Date?, enabled: Bool) {
            guard enabled, let target, target > now else { return }
            cues.append(ScheduledCue(sound: sound, fireAt: target))
        }

        // A break owns the clock while it runs, so regulation cues are never armed alongside it.
        if let breakClock = state.breakClock {
            add(.chime, breakClock.expiry(after: state.breakDuration, at: now), enabled: preferences.breakChime)
            return cues
        }

        // Period end. A count-up clock has no buzzer — running past the period length is added
        // time, not an expiry (§6.1).
        if !rules.countsUp, rules.periodLength > 0 {
            add(.buzzer, state.clock.expiry(after: rules.periodLength, at: now), enabled: preferences.buzzer)
            for lead in [60.0, 10.0] where rules.periodLength > lead {
                add(
                    .warning,
                    state.clock.expiry(after: rules.periodLength - lead, at: now),
                    enabled: preferences.timerWarning
                )
            }
        }

        if rules.shotClockEnabled {
            add(
                .horn,
                state.shotClock.expiry(after: state.shotClockDuration, at: now),
                enabled: preferences.shotClockHorn
            )
            if state.shotClockDuration > 5 {
                add(
                    .tick,
                    state.shotClock.expiry(after: state.shotClockDuration - 5, at: now),
                    enabled: preferences.shotClockTick
                )
            }
        }

        return cues
    }
}

// MARK: - Surface selection

/// Which surface the device shows, per the §5.3 behaviour matrix.
enum MatchSurface {
    /// Rotate-to-board is suppressed while a TV is showing the board.
    ///
    /// This is the rule the whole matrix exists for: replacing the operator's controls with a second
    /// copy of a board the crowd can already see is the worst possible outcome.
    static func deviceShowsBoard(isLandscape: Bool, isCasting: Bool) -> Bool {
        isLandscape && !isCasting
    }
}
