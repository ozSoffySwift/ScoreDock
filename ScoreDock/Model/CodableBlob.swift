import Foundation

/// Encodes and decodes the Codable values SwiftData stores as opaque `Data` (§7.3).
///
/// **Why these are not stored as their own types.** SwiftData treats a `Codable` value as a
/// *composite attribute* and decomposes it into columns. For a plain struct that mostly works; for
/// an enum with associated values such as `AnyRuleSet` it traps at encode time with
/// `unknown property payload for composite description`. Composite attributes would also defeat the
/// point of §7.3 — the blob exists precisely so its internals are *not* schema, so that adding a
/// rule is a decoder change rather than a store migration.
///
/// Decoding never throws. A blob written by a newer build, or corrupted, degrades to nil so a
/// history screen renders without the rules rather than failing to open at all.
enum CodableBlob {
    static func encode<T: Encodable>(_ value: T?) -> Data? {
        guard let value else { return nil }
        return try? JSONEncoder().encode(value)
    }

    static func decode<T: Decodable>(_ data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
