import Foundation

/// A plain sRGB colour with the WCAG maths attached.
///
/// Deliberately free of SwiftUI: §9.2 requires a verified 7:1 minimum contrast on every built-in
/// theme, and "verified" means a test asserts it. Keeping the maths in a pure value type is what
/// lets that test run headlessly instead of standing up a render pass.
struct RGBColor: Hashable, Sendable {
    /// Channel values in 0...1.
    var red: Double
    var green: Double
    var blue: Double

    init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Parses `#RRGGBB` or `RRGGBB`. Returns nil for anything else rather than silently producing
    /// black, so a typo in a theme fails loudly in the tests instead of shipping a broken board.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let packed = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: Double((packed >> 16) & 0xFF) / 255,
            green: Double((packed >> 8) & 0xFF) / 255,
            blue: Double(packed & 0xFF) / 255
        )
    }

    var hexString: String {
        String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }

    /// WCAG 2.1 relative luminance.
    var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, 1...21. Symmetric — order of the operands does not matter.
    func contrastRatio(against other: RGBColor) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
