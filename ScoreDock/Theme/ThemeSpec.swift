import Foundation

/// The colours a board renders with.
///
/// A board is a display instrument, not an app screen, and follows different rules from the rest of
/// the app (§9.2): no Liquid Glass, no translucency, no vibrancy. Legibility at 20 metres beats
/// aesthetics. Everything here is flat and opaque on purpose.
///
/// Stored as a Codable value: the 12 built-ins are bundled values rather than rows, and a match
/// freezes a copy of its theme at kickoff so the Match Report always renders in the theme the game
/// was actually played in (§13.4).
struct ThemeSpec: Codable, Hashable, Sendable, Identifiable {
    var id: String
    var name: String

    /// Board background. Opaque, always.
    var background: String

    /// The lit segments — score, timer, shot clock, period number, foul count. Must clear 7:1
    /// against `background`.
    var digit: String

    /// The *unlit* segments behind the digits.
    ///
    /// DSEG7 Classic gets its authentic LED-panel look from a faint all-segments-lit backing string
    /// drawn behind the real value (§2.1). This is that colour. It has to be visible enough to read
    /// as an unlit segment and faint enough not to compete with the digits — the tests bound it on
    /// both sides, because on a pure-white background it can otherwise disappear or turn muddy.
    var digitGhost: String

    /// Text elements — team names, period labels. Never DSEG7: that face has no Hebrew, and its
    /// Latin letters are seven-segment approximations (S renders as 5), so text always uses the
    /// app's text face (§9.2).
    var label: String

    /// Possession arrow, bonus indicator, warning states. Also held to 7:1, because these carry
    /// meaning and colour is never their only signal (§15).
    var accent: String

    /// Drives status-bar and complementary chrome choices on the board scene.
    var isDark: Bool

    init(
        id: String,
        name: String,
        background: String,
        digit: String,
        digitGhost: String,
        label: String,
        accent: String,
        isDark: Bool
    ) {
        self.id = id
        self.name = name
        self.background = background
        self.digit = digit
        self.digitGhost = digitGhost
        self.label = label
        self.accent = accent
        self.isDark = isDark
    }
}

extension ThemeSpec {
    /// Parsed colours. Force-unwrapping is safe for built-ins because `ThemeContrastTests` proves
    /// every one of them parses; a malformed user theme falls back to mid-grey rather than crashing.
    func color(_ keyPath: KeyPath<ThemeSpec, String>) -> RGBColor {
        RGBColor(hex: self[keyPath: keyPath]) ?? RGBColor(red: 0.5, green: 0.5, blue: 0.5)
    }

    /// Contrast of the lit digits against the board background — the number §9.2 holds to 7:1.
    var digitContrast: Double {
        color(\.digit).contrastRatio(against: color(\.background))
    }

    var labelContrast: Double {
        color(\.label).contrastRatio(against: color(\.background))
    }

    var accentContrast: Double {
        color(\.accent).contrastRatio(against: color(\.background))
    }

    var ghostContrast: Double {
        color(\.digitGhost).contrastRatio(against: color(\.background))
    }
}
