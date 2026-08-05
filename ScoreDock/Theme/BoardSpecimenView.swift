import SwiftUI

/// A miniature scoreboard used to preview a theme and font.
///
/// This is the first real board surface in the app and it already follows the board rules from
/// §9.2, so the full board in M1 inherits them rather than retrofitting:
///
/// - **No Liquid Glass, no translucency, no vibrancy.** The app chrome uses iOS 26's design
///   language; the board is flat, high-contrast and boring on purpose. Legibility at 20 metres
///   beats aesthetics.
/// - **Numeric elements use the board font; text elements do not.** DSEG7 has no Hebrew and its
///   Latin glyphs are seven-segment approximations, so side names always use the app's text face.
/// - **Digits never mirror.** The numeric core is pinned to left-to-right even in Hebrew, because
///   a scoreboard is a venue convention rather than a reading surface (§10.1).
/// - **Fixed-width digits**, so numbers do not jitter as they change.
struct BoardSpecimenView: View {
    var theme: ThemeSpec
    var font: BoardFont
    var homeScore: String = "102"
    var awayScore: String = "98"
    var clock: String = "07:23"
    var homeName: String = "HOME"
    var awayName: String = "GUEST"
    var showsLabels: Bool = true

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 0) {
                side(score: homeScore, name: homeName)
                LEDNumber(text: clock, theme: theme, font: font, size: 30)
                    .frame(maxWidth: .infinity)
                side(score: awayScore, name: awayName)
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(theme.backgroundColor)
        // The board is a display instrument: opaque, flat, and never glass.
        .clipShape(.rect(cornerRadius: 14))
        // A scoreboard does not flip sides based on phone language — home stays left (§10.1).
        .environment(\.layoutDirection, .leftToRight)
    }

    private func side(score: String, name: String) -> some View {
        VStack(spacing: 4) {
            LEDNumber(text: score, theme: theme, font: font, size: 44)
            if showsLabels {
                Text(name)
                    // Deliberately the app's text face, never the board font.
                    .font(.caption2.weight(.semibold))
                    .tracking(1.2)
                    .foregroundStyle(theme.labelColor)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// One numeric element, with the unlit-segment backing that gives DSEG7 its LED-panel look (§2.1).
struct LEDNumber: View {
    var text: String
    var theme: ThemeSpec
    var font: BoardFont
    var size: CGFloat

    var body: some View {
        ZStack {
            // The ghost layer paints every segment on, faintly, behind the real value. Only the
            // seven-segment faces have unlit segments to simulate.
            if font.drawsGhostSegments {
                Text(font.ghostString(for: text))
                    .foregroundStyle(theme.digitGhostColor)
                    .accessibilityHidden(true)
            }
            Text(text)
                .foregroundStyle(theme.digitColor)
        }
        .font(font.font(size: size))
        // DSEG7 is monospaced by construction; the other five faces need this applied explicitly
        // so digits keep a fixed-width slot and never jitter (§9.2).
        .monospacedDigit()
        .lineLimit(1)
        // A board must never truncate a score. Scaling far down is always the better failure than
        // rendering "88…" where a number should be, so this floor is deliberately generous.
        .minimumScaleFactor(0.2)
    }
}

/// A compact single-element swatch for theme pickers.
///
/// `88:88` lights every segment, which makes it the honest test of a palette: it shows the digit
/// colour and the unlit ghost colour together, against that theme's background.
struct ThemeSwatch: View {
    var theme: ThemeSpec
    var font: BoardFont
    var size: CGFloat = 26

    var body: some View {
        LEDNumber(text: "88:88", theme: theme, font: font, size: size)
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .background(theme.backgroundColor)
            .clipShape(.rect(cornerRadius: 10))
            .environment(\.layoutDirection, .leftToRight)
    }
}

#Preview("Themes") {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(BuiltInThemes.all) { theme in
                BoardSpecimenView(theme: theme, font: .sevenSegment)
            }
        }
        .padding()
    }
}
