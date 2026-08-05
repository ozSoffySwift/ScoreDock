import Foundation
import SwiftUI

/// What the external display renders (§6.1).
///
/// The reference site solves this with a "separate screen URL". The native equivalent is a second
/// *mode* on the same store — no network, no second device to configure. An iPad above the basket
/// showing nothing but a giant shot clock is the case this exists for.
enum BoardMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case full
    case shotClockOnly
    case timerOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full: String(localized: "Full board", comment: "Board mode")
        case .shotClockOnly: String(localized: "Shot clock only", comment: "Board mode")
        case .timerOnly: String(localized: "Timer only", comment: "Board mode")
        }
    }

    var symbolName: String {
        switch self {
        case .full: "rectangle.split.3x1"
        case .shotClockOnly: "timer"
        case .timerOnly: "clock"
        }
    }

    /// The modes a given match can actually fill.
    ///
    /// Offering "shot clock only" for a chess clock or a league table would put a permanent dash on
    /// a television. The iPad-above-the-basket case (§6.1) is a *basketball* case; the other boards
    /// either have one clock or none, and say so by not offering the choice.
    static func available(for store: AnyMatchStore) -> [BoardMode] {
        switch store {
        case let .team(store):
            var modes: [BoardMode] = [.full, .timerOnly]
            if store.rules.shotClockEnabled { modes.insert(.shotClockOnly, at: 1) }
            return modes

        case let .specialised(store):
            switch store.rules.board {
            // A play clock is a shot clock by another name, and a quarter clock is a timer.
            case .americanFootball: return [.full, .shotClockOnly, .timerOnly]
            // Two clocks that only mean anything side by side, so there is nothing to isolate.
            case .chessClock: return [.full]
            case .raceTimer: return [.full, .timerOnly]
            // No clock at all.
            case .cricket, .baseball: return [.full]
            }

        // A set-match board and a table have no clock to show on its own.
        case .setMatch, .list:
            return [.full]
        }
    }
}

/// App-level holder for the running match (§5.2).
///
/// **Why a shared instance rather than SwiftUI environment.** The external display's scene delegate
/// is instantiated by UIKit, outside any SwiftUI view hierarchy, so it cannot read `@Environment`.
/// §5.2 calls for "a single `@Observable` store held by the app and injected into both scenes"; this
/// is that holder. One source of truth, two renderers — never two copies of the state.
///
/// It holds an `AnyMatchStore` rather than a `LiveMatchStore`: this was team-only until M8, which
/// meant the board reached a TV for a basketball match and silently did not for a tennis, league or
/// chess one — while those panels still offered Display and a set of instructions.
@Observable
@MainActor
final class ActiveMatch {
    static let shared = ActiveMatch()

    private(set) var store: AnyMatchStore?

    /// What the *external* display shows. The device always shows the full board or the panel.
    var boardMode: BoardMode = .full

    private init() {}

    func begin(_ store: AnyMatchStore) {
        self.store = store
        // A board mode the new match has no clock for would show a permanent dash, so the mode
        // resets with the match rather than persisting across two different sports.
        if !BoardMode.available(for: store).contains(boardMode) { boardMode = .full }
    }

    func end() {
        store = nil
        boardMode = .full
    }
}

/// Tracks whether a second screen is attached (§5.2, §5.3).
///
/// By default an attached external display mirrors the device. The moment the app puts content into
/// the external scene the system **exits mirroring** and the TV shows only the board — which is
/// exactly the behaviour we want, and why this is a separate scene rather than a mirrored view.
@Observable
@MainActor
final class ExternalDisplay {
    static let shared = ExternalDisplay()

    private(set) var isConnected = false

    private init() {}

    func sceneConnected() {
        isConnected = true
    }

    func sceneDisconnected() {
        isConnected = false
    }
}
