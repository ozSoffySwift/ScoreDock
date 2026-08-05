import SwiftUI
import UIKit

extension Color {
    /// Builds a colour from `#RRGGBB`, falling back to mid-grey on a malformed string.
    ///
    /// Always opaque: the board never uses translucency (§9.2).
    init(hex: String, fallback: Color = .gray) {
        guard let rgb = RGBColor(hex: hex) else {
            self = fallback
            return
        }
        self.init(rgb)
    }

    init(_ rgb: RGBColor) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: 1)
    }

    /// `#RRGGBB` for storage on a `Team` or `MatchSide`.
    ///
    /// Channels are clamped because a colour chosen in a wide-gamut space can resolve outside
    /// 0...1 in sRGB, which would otherwise overflow the byte conversion.
    var resolvedHex: String {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else {
            return "#1E88E5"
        }
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(red), channel(green), channel(blue))
    }
}

extension ThemeSpec {
    var backgroundColor: Color { Color(color(\.background)) }
    var digitColor: Color { Color(color(\.digit)) }
    var digitGhostColor: Color { Color(color(\.digitGhost)) }
    var labelColor: Color { Color(color(\.label)) }
    var accentColor: Color { Color(color(\.accent)) }

    /// Which status-bar style keeps the board readable when it is full-screen.
    var preferredColorScheme: ColorScheme { isDark ? .dark : .light }
}
