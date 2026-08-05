import Foundation
import SwiftData

/// A saved person. Persistence of players is one of the two things a stateless website cannot
/// offer (§1.1), so this is core rather than incidental.
@Model
final class Player {
    /// Stable identity for cross-device de-duplication. Not `@Attribute(.unique)` — unique
    /// constraints are unsupported under CloudKit (§7.5), so merging is application logic keyed
    /// on this value, preferring the earlier `createdAt` when genuine duplicates appear.
    var id: UUID = UUID()

    var name: String = ""
    var nickname: String?

    // Identity marks — emoji and image are both always available, on every record, free (§7.1a).
    var emoji: String?
    @Attribute(.externalStorage) var image: Data?
    var markRaw: String = IdentityMark.initials.rawValue

    var colorHex: String?
    var defaultJersey: String?
    var notes: String?
    var createdAt: Date = Date.now

    /// Archived rather than deleted, so historical matches keep a live link to the person.
    var isArchived: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \TeamMembership.player)
    var memberships: [TeamMembership]? = []

    /// History outlives the roster. Deleting a player must never delete the matches they played in,
    /// so this nullifies — `MatchSide` denormalises name, mark and colour at kickoff precisely so a
    /// finished match still renders correctly once the linked record is gone.
    ///
    /// Declared explicitly because CloudKit rejects any relationship without an inverse (§7.5) and
    /// `MatchSide.linkedPlayer` is one. The spec's model listing omits this side of the pair.
    @Relationship(deleteRule: .nullify, inverse: \MatchSide.linkedPlayer)
    var matchAppearances: [MatchSide]? = []

    init(
        id: UUID = UUID(),
        name: String = "",
        nickname: String? = nil,
        emoji: String? = nil,
        image: Data? = nil,
        mark: IdentityMark = .initials,
        colorHex: String? = nil,
        defaultJersey: String? = nil,
        notes: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.nickname = nickname
        self.emoji = emoji
        self.image = image
        self.markRaw = mark.rawValue
        self.colorHex = colorHex
        self.defaultJersey = defaultJersey
        self.notes = notes
        self.createdAt = createdAt
    }
}

extension Player: IdentityBearing {
    var mark: IdentityMark {
        get { IdentityMark(storedRaw: markRaw) }
        set { markRaw = newValue.rawValue }
    }

    /// Nickname wins on the board: it is shorter, and it is what the crowd shouts.
    var displayName: String {
        if let nickname, !nickname.isEmpty { return nickname }
        return name
    }

    var identityColorHex: String? { colorHex }
}
