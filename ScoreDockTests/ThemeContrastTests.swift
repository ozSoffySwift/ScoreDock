import Foundation
import Testing

@testable import ScoreDock

/// §9.2 and §15 require a 7:1 minimum contrast on every built-in theme, "verified, not assumed".
/// This is the verification.
@Suite("Theme contrast (§9.2)")
struct ThemeContrastTests {
    /// WCAG AAA for large text is 4.5:1; the board holds itself to 7:1 because it is read across a
    /// hall, often through a camera, and often under bad light.
    static let minimumContrast = 7.0

    @Test("All twelve themes ship")
    func themeCount() {
        #expect(BuiltInThemes.all.count == 12)
        #expect(Set(BuiltInThemes.all.map(\.id)).count == 12, "duplicate theme id")
    }

    @Test("Every colour parses", arguments: BuiltInThemes.all)
    func coloursParse(theme: ThemeSpec) {
        for hex in [theme.background, theme.digit, theme.digitGhost, theme.label, theme.accent] {
            #expect(RGBColor(hex: hex) != nil, "\(theme.id): unparseable colour \(hex)")
        }
    }

    @Test("Digits clear 7:1 against the background", arguments: BuiltInThemes.all)
    func digitContrast(theme: ThemeSpec) {
        #expect(
            theme.digitContrast >= Self.minimumContrast,
            "\(theme.id) digit contrast \(theme.digitContrast.rounded(toPlaces: 2)) < 7"
        )
    }

    @Test("Labels clear 7:1 against the background", arguments: BuiltInThemes.all)
    func labelContrast(theme: ThemeSpec) {
        #expect(
            theme.labelContrast >= Self.minimumContrast,
            "\(theme.id) label contrast \(theme.labelContrast.rounded(toPlaces: 2)) < 7"
        )
    }

    /// The accent carries meaning — possession, bonus, warnings — so it is held to the same bar.
    @Test("Accent clears 7:1 against the background", arguments: BuiltInThemes.all)
    func accentContrast(theme: ThemeSpec) {
        #expect(
            theme.accentContrast >= Self.minimumContrast,
            "\(theme.id) accent contrast \(theme.accentContrast.rounded(toPlaces: 2)) < 7"
        )
    }

    /// The unlit-segment ghost is bounded on *both* sides, which is the §2.1 quirk in test form:
    /// too faint and it disappears (the pure-white theme's failure mode), too strong and it competes
    /// with the lit digits and turns the board muddy.
    @Test("Ghost segments are visible but never compete", arguments: BuiltInThemes.all)
    func ghostContrast(theme: ThemeSpec) {
        let ghost = theme.ghostContrast
        #expect(ghost >= 1.15, "\(theme.id) ghost \(ghost.rounded(toPlaces: 2)) is invisible")
        #expect(ghost <= 3.0, "\(theme.id) ghost \(ghost.rounded(toPlaces: 2)) competes with the digits")
        // And it must always sit well below the lit digits, whatever the absolute numbers.
        #expect(ghost < theme.digitContrast / 2, "\(theme.id) ghost is too close to the lit digits")
    }

    @Test("Dark is the default")
    func defaultTheme() {
        #expect(BuiltInThemes.defaultID == "dark")
        #expect(BuiltInThemes.theme(id: nil).id == "dark")
        #expect(BuiltInThemes.theme(id: "does-not-exist").id == "dark")
    }

    // MARK: WCAG maths

    @Test("Contrast maths matches the WCAG reference values")
    func contrastReferenceValues() throws {
        let white = try #require(RGBColor(hex: "#FFFFFF"))
        let black = try #require(RGBColor(hex: "#000000"))

        #expect(white.contrastRatio(against: black).isApproximately(21.0))
        #expect(white.contrastRatio(against: white).isApproximately(1.0))
        // Symmetric.
        #expect(black.contrastRatio(against: white).isApproximately(21.0))
    }

    @Test("Hex parsing rejects malformed input")
    func hexParsing() {
        #expect(RGBColor(hex: "#FFF") == nil)
        #expect(RGBColor(hex: "ZZZZZZ") == nil)
        #expect(RGBColor(hex: "") == nil)
        #expect(RGBColor(hex: "1E88E5")?.hexString == "#1E88E5")
        #expect(RGBColor(hex: "#1e88e5")?.hexString == "#1E88E5")
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }

    func isApproximately(_ other: Double, tolerance: Double = 0.01) -> Bool {
        abs(self - other) < tolerance
    }
}
