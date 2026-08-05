import Foundation
import SwiftUI

/// App-wide preferences that are not match state.
///
/// Backed by `UserDefaults` rather than SwiftData: these are device preferences, not user data, and
/// they should not sync or appear in a `.sdgame` export.
@Observable
@MainActor
final class AppSettings {
    /// Shared instance.
    ///
    /// The external display's scene delegate is created by UIKit and has no SwiftUI environment to
    /// read from (§5.2), so board font and theme have to be reachable without injection. Both scenes
    /// use this same object, which is also what keeps them visually identical.
    static let shared = AppSettings()

    enum Key {
        static let themeID = "board.themeID"
        static let boardFont = "board.font"
        static let soundEnabled = "audio.enabled"
        static let buzzerEnabled = "audio.buzzer"
        static let shotClockHornEnabled = "audio.shotClockHorn"
        static let shotClockTickEnabled = "audio.shotClockTick"
        static let breakChimeEnabled = "audio.breakChime"
        static let timerWarningEnabled = "audio.timerWarning"
        static let hapticsEnabled = "haptics.enabled"
        static let burnInProtection = "board.burnInProtection"
        static let shareWatermark = "share.watermark"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.themeID: BuiltInThemes.defaultID,
            Key.boardFont: BoardFont.default.rawValue,
            Key.soundEnabled: true,
            Key.buzzerEnabled: true,
            Key.shotClockHornEnabled: true,
            Key.shotClockTickEnabled: true,
            Key.breakChimeEnabled: true,
            // §11.1: the 60 s / 10 s timer warnings are configurable and off by default.
            Key.timerWarningEnabled: false,
            Key.hapticsEnabled: true,
            Key.burnInProtection: true,
            Key.shareWatermark: true,
        ])
        themeID = defaults.string(forKey: Key.themeID) ?? BuiltInThemes.defaultID
        boardFont = BoardFont(rawValue: defaults.string(forKey: Key.boardFont) ?? "") ?? .default
        soundEnabled = defaults.bool(forKey: Key.soundEnabled)
        buzzerEnabled = defaults.bool(forKey: Key.buzzerEnabled)
        shotClockHornEnabled = defaults.bool(forKey: Key.shotClockHornEnabled)
        shotClockTickEnabled = defaults.bool(forKey: Key.shotClockTickEnabled)
        breakChimeEnabled = defaults.bool(forKey: Key.breakChimeEnabled)
        timerWarningEnabled = defaults.bool(forKey: Key.timerWarningEnabled)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        burnInProtection = defaults.bool(forKey: Key.burnInProtection)
        shareWatermark = defaults.bool(forKey: Key.shareWatermark)
    }

    /// Default board theme. Dark, because it holds contrast under gym house lights and keys cleanly
    /// in OBS (§9.2).
    var themeID: String { didSet { defaults.set(themeID, forKey: Key.themeID) } }

    var boardFont: BoardFont { didSet { defaults.set(boardFont.rawValue, forKey: Key.boardFont) } }

    /// Master mute. Individual sounds are toggled below (§11.1).
    var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: Key.soundEnabled) } }

    var buzzerEnabled: Bool { didSet { defaults.set(buzzerEnabled, forKey: Key.buzzerEnabled) } }
    var shotClockHornEnabled: Bool { didSet { defaults.set(shotClockHornEnabled, forKey: Key.shotClockHornEnabled) } }
    var shotClockTickEnabled: Bool { didSet { defaults.set(shotClockTickEnabled, forKey: Key.shotClockTickEnabled) } }
    var breakChimeEnabled: Bool { didSet { defaults.set(breakChimeEnabled, forKey: Key.breakChimeEnabled) } }

    /// The 60 s and 10 s timer warnings. Off by default — most operators do not want them, and a
    /// beep nobody expected in a quiet hall is worse than no beep at all (§11.1).
    var timerWarningEnabled: Bool { didSet { defaults.set(timerWarningEnabled, forKey: Key.timerWarningEnabled) } }

    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) } }

    /// Shifts the board by ±2 pt on a slow 90-second cycle to protect OLED panels (§12).
    var burnInProtection: Bool { didSet { defaults.set(burnInProtection, forKey: Key.burnInProtection) } }

    /// Small app mark on image and PDF exports (§13.5). On by default, and free to turn off —
    /// a watermark the user cannot remove reads as an upsell and undercuts the free-forever
    /// positioning.
    var shareWatermark: Bool { didSet { defaults.set(shareWatermark, forKey: Key.shareWatermark) } }

    var theme: ThemeSpec { BuiltInThemes.theme(id: themeID) }
}

/// Single point of truth for whether a feature is available (§14.3).
///
/// **In v1.0 every property returns `true`.** There is no paywall, no locked feature and no
/// in-app purchase — StoreKit is deliberately not integrated. This type exists so that if paid
/// features ever ship, gating them is one implementation change rather than an archaeology
/// expedition through scattered `if` checks.
///
/// The rule it has to protect: a feature that shipped free can never later move behind a paywall
/// (§14.2). Anything charged for must be something that did not exist in v1.
enum FeatureAvailability {
    static var allThemes: Bool { true }
    static var allPresets: Bool { true }
    static var identityMarks: Bool { true }
    static var gameLog: Bool { true }
    static var allShareFormats: Bool { true }
    static var batchExport: Bool { true }
    static var removeWatermark: Bool { true }
    static var unlimitedLibrary: Bool { true }
    static var externalDisplay: Bool { true }
}
