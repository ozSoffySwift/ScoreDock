import AVFoundation
import Foundation
import OSLog

/// Plays the match sounds (§11.1).
///
/// **The session category is the whole point.** `.playback` means the buzzer sounds even with the
/// ring/silent switch set to silent — which is correct for a scoreboard, and is not the default
/// behaviour an app gets for free. `.mixWithOthers` means the venue's music keeps playing rather
/// than being ducked or stopped by a scoreboard app.
///
/// Sounds route to whatever the device is connected to, which usefully includes a Bluetooth speaker
/// at the scorer's table.
@MainActor
final class MatchAudio {
    static let shared = MatchAudio()

    private var players: [MatchSound: AVAudioPlayer] = [:]
    private var isConfigured = false
    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "audio")

    private init() {}

    /// Configures the session and preloads every sound.
    ///
    /// Preloading matters: a buzzer that decodes on first use fires late, and late is the one thing
    /// a period-end buzzer cannot be.
    func prepare() {
        guard !isConfigured else { return }
        isConfigured = true

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            Self.logger.error("Audio session unavailable: \(String(describing: error), privacy: .public)")
        }

        for sound in MatchSound.allCases {
            guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
                Self.logger.error("Missing sound asset: \(sound.fileName, privacy: .public)")
                continue
            }
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[sound] = player
            } catch {
                Self.logger.error("Could not load \(sound.fileName, privacy: .public)")
            }
        }
    }

    func play(_ sound: MatchSound) {
        prepare()
        guard let player = players[sound] else { return }
        // Restart rather than overlap — a buzzer retriggered mid-ring should sound once, not twice.
        player.currentTime = 0
        player.play()
    }

    func stopAll() {
        for player in players.values where player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
    }

    /// Assets that failed to load. Non-empty means a bundling problem, surfaced in Settings → About
    /// in debug builds rather than discovered when a buzzer stays silent at a match.
    var missingSounds: [MatchSound] {
        MatchSound.allCases.filter { players[$0] == nil }
    }
}
