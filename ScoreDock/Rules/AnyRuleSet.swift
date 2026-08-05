import Foundation

/// Engine-tagged rule payload, stored as an encoded attribute on `UserGamePreset` and `Match` (§7.3).
///
/// Four engines have wildly different parameter sets. Modelling them as columns would mean ~60
/// optional properties on every preset type, most of them nil, and a schema migration every time a
/// rule is added. As a tagged blob, adding a rule is a versioned decoder change instead.
///
/// **The trade-off, stated explicitly:** you cannot write a `#Predicate` against anything in here.
/// Every field that must be queryable — `engineRaw`, `categoryRaw`, `presetSlug`, `isFavorite`,
/// `lastUsedAt` — is therefore a real column on the owning model. That split is deliberate.
enum AnyRuleSet: Codable, Hashable, Sendable {
    case team(TeamRules)
    case setMatch(SetMatchRules)
    case list(ListRules)
    case specialised(SpecialisedRules)

    var engine: EngineKind {
        switch self {
        case .team: .team
        case .setMatch: .setMatch
        case .list: .list
        case .specialised: .specialised
        }
    }

    var teamRules: TeamRules? { if case let .team(r) = self { r } else { nil } }
    var setMatchRules: SetMatchRules? { if case let .setMatch(r) = self { r } else { nil } }
    var listRules: ListRules? { if case let .list(r) = self { r } else { nil } }
    var specialisedRules: SpecialisedRules? { if case let .specialised(r) = self { r } else { nil } }
}

// MARK: - Versioned coding

extension AnyRuleSet {
    /// Bump only for a change that older builds cannot decode. Adding a *field* does not require a
    /// bump — every rule struct decodes missing keys to its documented default, so an old blob
    /// decodes cleanly into a newer struct.
    static let currentVersion = 1

    private enum CodingKeys: String, CodingKey {
        case version, engine, payload
    }

    enum DecodingProblem: LocalizedError {
        case unsupportedVersion(found: Int, supported: Int)

        var errorDescription: String? {
            switch self {
            case let .unsupportedVersion(found, supported):
                "These rules were saved by a newer version of the app (format \(found), this build reads \(supported))."
            }
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Absent on the very first format, hence `decodeIfPresent`.
        let version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        guard version <= Self.currentVersion else {
            throw DecodingProblem.unsupportedVersion(found: version, supported: Self.currentVersion)
        }

        // An unrecognised engine falls back rather than throwing, for the same reason enums are
        // stored as raw strings (§7.5) — a device on an older build should degrade, not fail.
        let engine = EngineKind(storedRaw: try container.decodeIfPresent(String.self, forKey: .engine))

        switch engine {
        case .team:
            self = .team(try container.decode(TeamRules.self, forKey: .payload))
        case .setMatch:
            self = .setMatch(try container.decode(SetMatchRules.self, forKey: .payload))
        case .list:
            self = .list(try container.decode(ListRules.self, forKey: .payload))
        case .specialised:
            self = .specialised(try container.decode(SpecialisedRules.self, forKey: .payload))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(engine.rawValue, forKey: .engine)

        switch self {
        case let .team(rules): try container.encode(rules, forKey: .payload)
        case let .setMatch(rules): try container.encode(rules, forKey: .payload)
        case let .list(rules): try container.encode(rules, forKey: .payload)
        case let .specialised(rules): try container.encode(rules, forKey: .payload)
        }
    }
}
