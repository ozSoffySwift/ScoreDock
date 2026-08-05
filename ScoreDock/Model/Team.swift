import Foundation
import SwiftData

/// A saved team. Ships with no real-world team names, crests or league branding — users supply
/// their own (§16), which keeps the app clear of trademark exposure.
@Model
final class Team {
    /// See the note on `Player.id`: stable identity for merge-on-sync, deliberately not unique.
    var id: UUID = UUID()

    var name: String = ""

    /// Four characters or fewer, for narrow boards. Needs testing with Hebrew glyphs, which run
    /// wider than Latin at the same point size — where it does not fit, an identity mark is the
    /// language-neutral substitute (§10.2, §7.1a).
    var shortName: String = ""

    var emoji: String?
    @Attribute(.externalStorage) var image: Data?
    var markRaw: String = IdentityMark.initials.rawValue

    var primaryColorHex: String = "#1E88E5"
    var secondaryColorHex: String = "#FFFFFF"
    var createdAt: Date = Date.now
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.team)
    var roster: [TeamMembership]? = []

    /// Nullify, not cascade — see the matching note on `Player.matchAppearances`. Deleting a team
    /// must not erase the season it played.
    @Relationship(deleteRule: .nullify, inverse: \MatchSide.linkedTeam)
    var matchAppearances: [MatchSide]? = []

    init(
        id: UUID = UUID(),
        name: String = "",
        shortName: String = "",
        emoji: String? = nil,
        image: Data? = nil,
        mark: IdentityMark = .initials,
        primaryColorHex: String = "#1E88E5",
        secondaryColorHex: String = "#FFFFFF",
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.emoji = emoji
        self.image = image
        self.markRaw = mark.rawValue
        self.primaryColorHex = primaryColorHex
        self.secondaryColorHex = secondaryColorHex
        self.createdAt = createdAt
    }

    /// Players currently on the roster, in jersey order where jerseys are numeric.
    ///
    /// Sorted explicitly: CloudKit relationships are unordered sets, so array order as it comes back
    /// from the store carries no meaning (§7.5).
    var activePlayers: [Player] {
        (roster ?? [])
            .filter { $0.isActive }
            .sorted { lhs, rhs in
                switch (Int(lhs.jersey ?? ""), Int(rhs.jersey ?? "")) {
                case let (l?, r?): return l < r
                case (nil, _?): return false
                case (_?, nil): return true
                default: return (lhs.player?.displayName ?? "") < (rhs.player?.displayName ?? "")
                }
            }
            .compactMap(\.player)
    }
}

extension Team: IdentityBearing {
    var mark: IdentityMark {
        get { IdentityMark(storedRaw: markRaw) }
        set { markRaw = newValue.rawValue }
    }

    var displayName: String { name }

    /// `IdentityBearing` speaks in terms of a single optional colour; a team's identity colour is
    /// its primary.
    var identityColorHex: String? { primaryColorHex }
}
