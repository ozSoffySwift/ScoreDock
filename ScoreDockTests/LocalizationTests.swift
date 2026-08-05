import Foundation
import Testing

@testable import ScoreDock

/// §10 — Hebrew and RTL.
///
/// **Why this suite exists.** The string catalog was populated at M0 and then silently stopped
/// growing: `xcodebuild` extracts every `String(localized:)` into the build directory but never
/// writes back to the source `.xcstrings`, and only Xcode's own build does. Four milestones later
/// the app had 622 keys and the catalog still had 83 — so 87% of the interface fell back to English
/// in Hebrew, with nothing failing and nothing to see. Nobody noticed because there was no test.
///
/// This is that test. It reads the catalog out of the source tree rather than the bundle, because
/// the bundle only ships the *translated* half and cannot tell you what is missing.
@Suite("Localization (§10)")
struct LocalizationTests {
    /// Keys still awaiting a Hebrew translation.
    ///
    /// Asserted exactly, the same way `CatalogTests` pins the count of unverified rule values: the
    /// number may only move deliberately, so neither a regression nor a quiet improvement can hide.
    static let untranslatedKeyCount = 0

    private static func catalogURL() -> URL {
        // ScoreDockTests/LocalizationTests.swift → the project root → the catalog.
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ScoreDock/Resources/Localizable.xcstrings")
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable {
                    var state: String?
                    var value: String?
                }
                var stringUnit: Unit?
                /// Plural and device variations nest their units one level deeper.
                var variations: [String: [String: Localization]]?
            }
            var localizations: [String: Localization]?
            var shouldTranslate: Bool?
        }

        var sourceLanguage: String
        var strings: [String: Entry]
    }

    private func catalog() throws -> Catalog {
        let data = try Data(contentsOf: Self.catalogURL())
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// Every value a Hebrew entry carries, including the ones inside plural variations.
    private func hebrewValues(_ entry: Catalog.Entry) -> [String] {
        guard let hebrew = entry.localizations?["he"] else { return [] }
        var values: [String] = []
        if let value = hebrew.stringUnit?.value { values.append(value) }
        for variation in hebrew.variations?.values ?? [:].values {
            for nested in variation.values {
                if let value = nested.stringUnit?.value { values.append(value) }
            }
        }
        return values
    }

    // MARK: The invariant

    @Test("Every user-visible string has a Hebrew translation")
    func hebrewCoverage() throws {
        let catalog = try catalog()

        let untranslated = catalog.strings
            .filter { $0.value.shouldTranslate != false }
            .filter { hebrewValues($0.value).isEmpty }
            .keys
            .sorted()

        #expect(
            untranslated.count == Self.untranslatedKeyCount,
            "\(untranslated.count) keys have no Hebrew. First few: \(untranslated.prefix(5))"
        )
    }

    @Test("No translation is blank")
    func noEmptyTranslations() throws {
        let catalog = try catalog()
        for (key, entry) in catalog.strings {
            for value in hebrewValues(entry) {
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) has a blank Hebrew value")
            }
        }
    }

    /// A format specifier dropped in translation is a crash, not a typo.
    @Test("Translations keep every format specifier the English has")
    func formatSpecifiersSurvive() throws {
        let catalog = try catalog()
        let specifier = /%(?:\d+\$)?(?:lld|ld|d|@|f|\.\df)/

        for (key, entry) in catalog.strings {
            let expected = key.matches(of: specifier).map { String($0.output) }.sorted()
            guard !expected.isEmpty else { continue }

            for value in hebrewValues(entry) {
                let actual = value.matches(of: specifier).map { String($0.output) }.sorted()
                #expect(actual == expected, "\(key) → \(value) changed its format specifiers")
            }
        }
    }

    @Test("English is the source language, and Hebrew is the only other one")
    func languages() throws {
        let catalog = try catalog()
        #expect(catalog.sourceLanguage == "en")

        // `en` entries are written by the extractor for keys whose value differs from the key, so
        // both source and target are expected; anything else is a language nobody is maintaining.
        let languages = Set(catalog.strings.values.flatMap { $0.localizations?.keys ?? [:].keys })
        #expect(languages.subtracting(["en", "he"]).isEmpty, "an unexpected language appeared in the catalog")
    }

    /// A sport's vocabulary has to say the same thing everywhere it appears.
    ///
    /// The bug this guards: the board label `OVERS` was translated as *מחזורים*, which the catalog
    /// already used for both "periods" and "innings" — so one Hebrew word meant three different
    /// things, and a cricket board read *מחזורים* directly beneath a rules row reading *אוברים*.
    /// Invisible from the English, obvious the moment the app runs in Hebrew.
    @Test("A term keeps one Hebrew word everywhere it appears")
    func terminologyIsConsistent() throws {
        let catalog = try catalog()

        // English keys naming one concept → the Hebrew root every one of them must carry.
        let vocabulary: [(word: String, keys: [String])] = [
            ("אובר", ["OVERS", "Overs", "Overs per innings", "Balls per over"]),
            ("שער", ["Wicket", "Wickets"]),
            ("מחזור", ["INNING", "Inning", "Innings", "Innings each", "Half-inning"]),
            ("אאוט", ["OUT", "Out", "Outs", "Outs per half-inning"]),
            ("הקפ", ["Laps", "LAPS %lld", "%@ lap"]),
        ]

        for (word, keys) in vocabulary {
            for key in keys {
                guard let entry = catalog.strings[key], let value = hebrewValues(entry).first else { continue }
                #expect(value.contains(word), "\(key) → \(value) does not use \"\(word)\"")
            }
        }
    }

    // MARK: What actually ships

    /// The catalog being right is not the same as the app being right — the strings still have to
    /// compile into the bundle and resolve at runtime.
    @Test("The Hebrew bundle ships and resolves")
    func hebrewBundleResolves() throws {
        let path = try #require(
            Self.appBundle.path(forResource: "he", ofType: "lproj"),
            "he.lproj is missing from the app bundle"
        )
        let hebrew = try #require(Bundle(path: path))

        // A key that is definitely Hebrew, not a passthrough of the English.
        let translated = hebrew.localizedString(forKey: "Play", value: nil, table: nil)
        #expect(translated != "Play", "the Hebrew bundle returned the English string")
        #expect(translated.unicodeScalars.contains { (0x0590 ... 0x05FF).contains(Int($0.value)) })
    }

    @Test("Every catalog key resolves in the shipped Hebrew bundle")
    func everyKeyResolves() throws {
        let catalog = try catalog()
        let path = try #require(Self.appBundle.path(forResource: "he", ofType: "lproj"))
        let hebrew = try #require(Bundle(path: path))

        var unresolved: [String] = []
        for (key, entry) in catalog.strings where entry.shouldTranslate != false {
            // Plural variations resolve through the stringsdict path and are exercised above.
            guard !hebrewValues(entry).isEmpty, entry.localizations?["he"]?.variations == nil else { continue }
            let resolved = hebrew.localizedString(forKey: key, value: "\u{0}", table: nil)
            if resolved == "\u{0}" { unresolved.append(key) }
        }

        #expect(unresolved.isEmpty, "translated but absent from the built bundle: \(unresolved.prefix(5))")
    }

    /// The **app** bundle, not the test bundle. `Bundle(for:)` on a type declared in the test target
    /// resolves to `ScoreDockTests.xctest`, which ships no localizations at all — anchoring on a
    /// class from the app module is what makes this test look at what actually ships.
    private static var appBundle: Bundle { Bundle(for: AppDelegate.self) }
}
