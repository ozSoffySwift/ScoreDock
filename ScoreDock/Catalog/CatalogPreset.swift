import Foundation
import OSLog

/// How much to trust a rule value (§8.5).
///
/// A wrong foul limit is the kind of error that makes a referee delete the app, so the catalog
/// records *where each number came from* rather than presenting them all as equally certain.
enum SourceStatus: String, Codable, Sendable {
    /// A headline parameter confirmed from the reference site's own preset tables (§8.1–8.4).
    case referenceSite
    /// Taken from the named governing body's published rules.
    case sourced
    /// A plausible default that must be checked against the governing body before submission.
    /// `CatalogAuditTests` reports the running count; these are not shipping blockers for M0, but
    /// they are shipping blockers for the App Store.
    case needsReview
}

/// Provenance for one rule value.
struct RuleSource: Codable, Hashable, Sendable {
    var cite: String
    var status: SourceStatus
}

/// A built-in preset, decoded from the bundled catalog (§7.4).
///
/// A value type, never a stored row. That is what makes "two devices first-launch before sync
/// settles and each insert their own 37" impossible rather than something to defend against, and it
/// makes shipping new presets a normal app update rather than a data migration.
struct CatalogPreset: Identifiable, Hashable, Sendable {
    var slug: String
    var localizedNames: [String: String]
    var emoji: String
    var engine: EngineKind
    var category: PresetCategory
    var sortIndex: Int
    var defaultThemeID: String
    var rules: AnyRuleSet
    var sources: [String: RuleSource]

    var id: String { slug }

    /// Name in the user's preferred language, falling back through their language list to English.
    ///
    /// Preset names live in the catalog rather than in the String Catalog because they are bundled
    /// *data*, and Xcode only extracts strings from `String(localized:)` calls in source — they
    /// would have to be hand-maintained in the catalog either way. Keeping them here means adding a
    /// preset touches one file.
    var name: String {
        for identifier in Locale.preferredLanguages {
            if let code = Locale(identifier: identifier).language.languageCode?.identifier,
               let localized = localizedNames[code] {
                return localized
            }
        }
        return localizedNames["en"] ?? localizedNames.values.first ?? slug
    }

    /// Rule values still awaiting verification against a governing body (§8.5).
    var unverifiedRuleKeys: [String] {
        sources.filter { $0.value.status == .needsReview }.keys.sorted()
    }
}

// MARK: - Decoding

extension CatalogPreset: Decodable {
    private enum CodingKeys: String, CodingKey {
        case slug, name, emoji, engine, category, sortIndex, defaultThemeID, rules, sources
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        slug = try c.decode(String.self, forKey: .slug)
        localizedNames = try c.decode([String: String].self, forKey: .name)
        emoji = try c.decode(String.self, forKey: .emoji)
        engine = EngineKind(storedRaw: try c.decodeIfPresent(String.self, forKey: .engine))
        category = PresetCategory(storedRaw: try c.decodeIfPresent(String.self, forKey: .category))
        sortIndex = try c.decodeIfPresent(Int.self, forKey: .sortIndex) ?? 0
        defaultThemeID = try c.decodeIfPresent(String.self, forKey: .defaultThemeID) ?? BuiltInThemes.defaultID
        sources = try c.decodeIfPresent([String: RuleSource].self, forKey: .sources) ?? [:]

        // The catalog stores a bare rule payload and names its engine at the top level, rather than
        // repeating the `AnyRuleSet` envelope 37 times. The engine tag is what selects the shape.
        rules = switch engine {
        case .team: .team(try c.decode(TeamRules.self, forKey: .rules))
        case .setMatch: .setMatch(try c.decode(SetMatchRules.self, forKey: .rules))
        case .list: .list(try c.decode(ListRules.self, forKey: .rules))
        case .specialised: .specialised(try c.decode(SpecialisedRules.self, forKey: .rules))
        }
    }
}

/// The bundled catalog file.
struct CatalogFile: Decodable, Sendable {
    var formatVersion: Int
    var presets: [CatalogPreset]
}

/// Loads and caches the bundled catalog.
enum BuiltInCatalog {
    private static let logger = Logger(subsystem: "com.ozsoffy.scoredock", category: "catalog")

    static let resourceName = "catalog"

    /// Decoded once at first use.
    ///
    /// A failure here means a corrupted or mis-copied bundle resource, which is a build-integrity
    /// problem rather than anything a user can cause. It trips in debug so it is caught during
    /// development, and degrades to an empty catalog in release — an empty picker with a clear
    /// message beats a crash on someone's phone at the start of a match. `CatalogTests` is the real
    /// guard: it asserts all 37 decode.
    static let presets: [CatalogPreset] = {
        do {
            return try load()
        } catch {
            logger.fault("Built-in catalog failed to decode: \(String(describing: error), privacy: .public)")
            assertionFailure("Built-in catalog failed to decode: \(error)")
            return []
        }
    }()

    static func load(bundle: Bundle = .main) throws -> [CatalogPreset] {
        guard let url = bundle.url(forResource: resourceName, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CatalogFile.self, from: data).presets
    }

    static let bySlug: [String: CatalogPreset] = Dictionary(
        presets.map { ($0.slug, $0) },
        uniquingKeysWith: { first, _ in first }
    )
}
