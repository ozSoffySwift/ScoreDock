import Foundation

/// One shared identity system across players, teams and ad-hoc match sides (§7.1a) — not three
/// separate features. Anything that can appear on a board, in a list, or in a share export
/// conforms, and gets the same resolution rules for free.
protocol IdentityBearing {
    var displayName: String { get }
    var emoji: String? { get }
    var image: Data? { get }
    var mark: IdentityMark { get }
    /// Named distinctly from any stored `colorHex` so conformers can map their own colour field
    /// onto it — `Team` uses its primary, `MatchSide` a non-optional snapshot.
    var identityColorHex: String? { get }
}

/// What actually renders, after preference and availability are reconciled.
///
/// There is deliberately no `.none` case: initials are always derivable, so no code path can
/// produce a blank slot on the board (§7.1a).
enum ResolvedMark: Equatable, Sendable {
    case image(Data)
    case emoji(String)
    case initials(String)
}

extension IdentityBearing {
    /// Render precedence from §7.1a: preferred mark if that mark actually exists → image → emoji
    /// → coloured initials.
    ///
    /// The preference is consulted first so a user who adds both a photo and an emoji chooses which
    /// one represents them, rather than the app guessing.
    var resolvedMark: ResolvedMark {
        switch mark {
        case .image:
            if let image, !image.isEmpty { return .image(image) }
        case .emoji:
            if let emoji, !emoji.isEmpty { return .emoji(emoji) }
        case .initials:
            return .initials(initials)
        }

        // Preferred mark is unavailable — fall through the general order.
        if let image, !image.isEmpty { return .image(image) }
        if let emoji, !emoji.isEmpty { return .emoji(emoji) }
        return .initials(initials)
    }

    /// Up to two initials derived from the display name.
    ///
    /// Grapheme-cluster based, so it is correct for Hebrew (where casing is a no-op) and for names
    /// that lead with an emoji. Never returns an empty string: an unnamed record falls back to "?"
    /// so the terminal case of `resolvedMark` genuinely terminates.
    var initials: String {
        let words = displayName
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .filter { $0.contains(where: { $0.isLetter || $0.isNumber || $0.isEmoji }) }

        let letters = words.prefix(2).compactMap { $0.first }
        guard !letters.isEmpty else { return "?" }

        // Hebrew and other uncased scripts pass through `uppercased()` unchanged, which is what we want.
        return String(letters).uppercased()
    }
}

extension Character {
    /// True for characters that present as emoji by default.
    ///
    /// The `unicodeScalars.count > 1` arm catches sequences like keycaps and ZWJ families whose
    /// leading scalar is an ASCII digit or a non-presentation scalar.
    var isEmoji: Bool {
        guard let first = unicodeScalars.first else { return false }
        return first.properties.isEmojiPresentation
            || (unicodeScalars.count > 1 && unicodeScalars.contains { $0.properties.isEmoji })
    }
}

// MARK: - Emoji validation

enum EmojiInput {
    /// Validates a single-grapheme emoji as required by §7.1a, so the field cannot quietly become
    /// a second name field. Returns nil for anything that is not exactly one emoji cluster.
    static func validated(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 1, let only = trimmed.first, only.isEmoji else { return nil }
        return trimmed
    }
}
