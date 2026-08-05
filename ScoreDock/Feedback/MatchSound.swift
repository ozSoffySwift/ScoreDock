import Foundation

/// The five match sounds (§11.1).
///
/// A gym is loud and the operator is not looking at the screen, so audio here is load-bearing
/// rather than polish. Each sound is deliberately distinct in pitch and length: the period buzzer
/// and the shot-clock horn must never be mistaken for one another across a hall.
///
/// The assets are synthesised rather than sourced, so nothing in the bundle is licence-encumbered.
enum MatchSound: String, CaseIterable, Codable, Sendable {
    /// Period end, or the timer reaching zero. Long and harsh.
    case buzzer
    /// Shot clock expiry. Shorter and lower than the buzzer.
    case horn
    /// Shot clock warning at 5 seconds. A dry click.
    case tick
    /// Break end. Pleasant on purpose — it means "come back", not "stop".
    case chime
    /// Timer warning at 60 s / 10 s. Off by default (§11.1).
    case warning

    var fileName: String { "\(rawValue).wav" }

    var displayName: String {
        switch self {
        case .buzzer: String(localized: "Period buzzer", comment: "Sound name")
        case .horn: String(localized: "Shot clock horn", comment: "Sound name")
        case .tick: String(localized: "Shot clock warning", comment: "Sound name")
        case .chime: String(localized: "Break end chime", comment: "Sound name")
        case .warning: String(localized: "Timer warning", comment: "Sound name")
        }
    }
}
