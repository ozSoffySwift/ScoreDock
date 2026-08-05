import CoreHaptics
import Foundation
import OSLog
import UIKit

/// Haptic feedback for match actions (§11.2).
///
/// A gym is loud and the operator's eyes are on the game, so a tap that *feels* different when it
/// registers is what lets them score without looking. Gating on Reduce Motion and the app toggle is
/// the caller's job — this type just plays.
@MainActor
final class MatchHaptics {
    static let shared = MatchHaptics()

    private var engine: CHHapticEngine?
    private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]
    private let notificationGenerator = UINotificationFeedbackGenerator()
    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "haptics")

    private init() {}

    private var supportsCoreHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    /// Warms up the generators so the first tap of a match is not the slow one.
    func prepare() {
        for style in [UIImpactFeedbackGenerator.FeedbackStyle.light, .medium, .rigid] {
            let generator = impactGenerators[style] ?? UIImpactFeedbackGenerator(style: style)
            generator.prepare()
            impactGenerators[style] = generator
        }
        notificationGenerator.prepare()
        startEngineIfNeeded()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = impactGenerators[style] ?? UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator
        generator.impactOccurred()
        generator.prepare()
    }

    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        notificationGenerator.notificationOccurred(type)
        notificationGenerator.prepare()
    }

    /// A sustained pattern for the period buzzer — the one piece of feedback that has to be
    /// noticeable through a pocket or across a scorer's table, so it is a continuous rumble rather
    /// than a tap.
    func buzzer() {
        guard supportsCoreHaptics, let engine else {
            // Older hardware, or no haptic engine: three firm taps still communicate "period over".
            notify(.warning)
            return
        }

        do {
            let events = [
                CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.55),
                    ],
                    relativeTime: 0,
                    duration: 1.4
                ),
                // A sharp transient on top of the rumble, so the onset is unmistakable.
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.9),
                    ],
                    relativeTime: 0
                ),
            ]
            let pattern = try CHHapticPattern(events: events, parameters: [])
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            Self.logger.error("Buzzer haptic failed: \(String(describing: error), privacy: .public)")
            notify(.warning)
        }
    }

    private func startEngineIfNeeded() {
        guard supportsCoreHaptics, engine == nil else { return }
        do {
            let created = try CHHapticEngine()
            // The engine is stopped when the app backgrounds and must be restarted, otherwise the
            // buzzer is silently dead for the rest of the match.
            created.resetHandler = { [weak created] in try? created?.start() }
            created.stoppedHandler = { _ in }
            try created.start()
            engine = created
        } catch {
            Self.logger.error("Haptic engine unavailable: \(String(describing: error), privacy: .public)")
        }
    }
}
