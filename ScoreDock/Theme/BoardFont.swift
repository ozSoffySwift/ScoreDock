import SwiftUI
import UIKit

/// The six board fonts (§9.1).
///
/// **Numeric elements only.** DSEG7 has no Hebrew coverage at all, and although it does carry A–Z
/// and a–z, those glyphs are seven-segment approximations — an `S` is indistinguishable from a `5`,
/// an `O` from a `0`. Team names, period labels and any other text always render in the app's text
/// face. Apply this per-element, never to a whole view hierarchy (§2.1, §9.2).
///
/// It also has no `/` glyph, which matters for the cricket board's `runs/wickets` and any other
/// slash-separated notation — those need a composed layout rather than a single string.
enum BoardFont: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Bundled, and the default: the LED seven-segment face is what makes a scoreboard read as a
    /// scoreboard rather than as an app.
    case sevenSegment = "DSEG7Classic-Bold"
    /// A slanted scoreboard is a real look, worth prototyping (§2.1 step 1).
    case sevenSegmentItalic = "DSEG7Classic-Italic"
    case roboto = "Roboto-Bold"
    case majorMono = "MajorMonoDisplay-Regular"
    case tech = "Michroma-Regular"
    case mono = "Menlo-Bold"
    case azeret = "AzeretMono-Bold"

    var id: String { rawValue }

    static let `default`: BoardFont = .sevenSegment

    var displayName: String {
        switch self {
        case .sevenSegment: "Seven Segment"
        case .sevenSegmentItalic: "Seven Segment Italic"
        case .roboto: "Roboto"
        case .majorMono: "Major Mono"
        case .tech: "Tech"
        case .mono: "Mono"
        case .azeret: "Azeret"
        }
    }

    /// True for the faces that ship inside the app right now.
    ///
    /// Only DSEG7 is bundled at M0. The other five need an individual licence and Hebrew-coverage
    /// check before bundling, and where a licence is awkward the intent is to substitute a system
    /// font of the same character (§2.1). Until then `font(size:)` falls back cleanly, so an
    /// unbundled choice degrades to a monospaced system face instead of silently rendering nothing.
    var isBundled: Bool {
        switch self {
        case .sevenSegment, .sevenSegmentItalic: true
        case .roboto, .majorMono, .tech, .mono, .azeret: false
        }
    }

    /// Whether the face draws unlit "ghost" segments behind the lit ones — the effect that produces
    /// the authentic LED-panel look, drawn using `ThemeSpec.digitGhost`.
    var drawsGhostSegments: Bool {
        self == .sevenSegment || self == .sevenSegmentItalic
    }

    /// The string used to paint every segment on, behind the real value. DSEG7's `8` lights all
    /// seven segments; the `!` is DSEG7's full-height colon-and-dot cell.
    func ghostString(for value: String) -> String {
        String(value.map { $0 == ":" ? ":" : ($0 == "." ? "." : "8") })
    }

    /// Resolves to the registered face, or a monospaced system fallback if it is missing.
    ///
    /// A font that fails to load is normally invisible until someone notices the board looks wrong;
    /// routing every access through here makes the failure a legible degradation instead.
    func font(size: CGFloat) -> Font {
        BoardFontRegistry.isAvailable(self)
            ? .custom(rawValue, fixedSize: size)
            : .system(size: size, weight: .bold, design: .monospaced)
    }

    /// UIKit equivalent, for `ImageRenderer` share cards and the external display scene.
    func uiFont(size: CGFloat) -> UIFont {
        UIFont(name: rawValue, size: size)
            ?? .monospacedDigitSystemFont(ofSize: size, weight: .bold)
    }
}

/// Verifies registered fonts once, by PostScript name.
///
/// §2.1 step 4 is explicit that the *PostScript* name is what gets registered, not the filename,
/// and that it should be verified at runtime rather than trusted. The most common cause of a font
/// that silently fails to load is a missing Target Membership tick, and that produces exactly the
/// same symptom as a wrong name — so this checks rather than assumes.
enum BoardFontRegistry {
    private static let available: Set<String> = {
        var names: Set<String> = []
        for family in UIFont.familyNames {
            for postScriptName in UIFont.fontNames(forFamilyName: family) {
                names.insert(postScriptName)
            }
        }
        return names
    }()

    static func isAvailable(_ font: BoardFont) -> Bool {
        available.contains(font.rawValue)
    }

    /// Bundled fonts that failed to register. Non-empty means a build configuration problem —
    /// surfaced in Settings → About in debug builds rather than left to be discovered on a wall
    /// display at a match.
    static var missingBundledFonts: [BoardFont] {
        BoardFont.allCases.filter { $0.isBundled && !isAvailable($0) }
    }
}
