import Foundation
import SwiftData

/// One side of a match: a team, a player, or an ad-hoc name typed at the scorer's table.
///
/// Identity is *copied* from the linked record at kickoff rather than read through the relationship.
/// That is deliberate — it means a finished match still renders correctly after the team is renamed,
/// recoloured, or deleted outright, and it is what lets `Team.matchAppearances` nullify safely.
@Model
final class MatchSide {
    /// Inverse of `Match.sides`; required by CloudKit (§7.5).
    var match: Match?

    /// 0 = home, 1 = visitor, n for leaderboards. Explicit because CloudKit relationships are
    /// unordered sets and array order does not survive sync.
    var slotIndex: Int = 0

    var displayName: String = ""
    var shortName: String = ""

    // Identity copied from the linked team/player at kickoff, or set ad-hoc (§7.1a).
    var emoji: String?
    @Attribute(.externalStorage) var image: Data?
    var markRaw: String = IdentityMark.initials.rawValue
    var colorHex: String = "#1E88E5"

    /// Optional — ad-hoc sides with no saved record behind them are a first-class case.
    var linkedTeam: Team?
    var linkedPlayer: Player?

    // Denormalised at match end for fast stats queries, so the common aggregations in §7.2 never
    // have to replay the event log.
    var finalScore: Int = 0
    var finalSets: [Int] = []
    var resultRank: Int?
    var outcomeRaw: String = SideOutcome.unfinished.rawValue

    init(
        slotIndex: Int = 0,
        displayName: String = "",
        shortName: String = "",
        emoji: String? = nil,
        image: Data? = nil,
        mark: IdentityMark = .initials,
        colorHex: String = "#1E88E5",
        linkedTeam: Team? = nil,
        linkedPlayer: Player? = nil
    ) {
        self.slotIndex = slotIndex
        self.displayName = displayName
        self.shortName = shortName
        self.emoji = emoji
        self.image = image
        self.markRaw = mark.rawValue
        self.colorHex = colorHex
        self.linkedTeam = linkedTeam
        self.linkedPlayer = linkedPlayer
    }
}

extension MatchSide: IdentityBearing {
    var mark: IdentityMark {
        get { IdentityMark(storedRaw: markRaw) }
        set { markRaw = newValue.rawValue }
    }

    var outcome: SideOutcome {
        get { SideOutcome(storedRaw: outcomeRaw) }
        set { outcomeRaw = newValue.rawValue }
    }

    /// A side always has a colour — it was snapshotted at kickoff — so this is never nil.
    var identityColorHex: String? { colorHex }
}

extension MatchSide {
    /// Builds a side from a saved team, snapshotting its identity. See the type note on why this
    /// copies rather than references.
    static func from(team: Team, slotIndex: Int) -> MatchSide {
        MatchSide(
            slotIndex: slotIndex,
            displayName: team.name,
            shortName: team.shortName,
            emoji: team.emoji,
            image: team.image,
            mark: team.mark,
            colorHex: team.primaryColorHex,
            linkedTeam: team
        )
    }

    /// Builds a side from a saved player, for the one-on-one sports in the set-match engine.
    static func from(player: Player, slotIndex: Int) -> MatchSide {
        MatchSide(
            slotIndex: slotIndex,
            displayName: player.displayName,
            shortName: String(player.displayName.prefix(4)),
            emoji: player.emoji,
            image: player.image,
            mark: player.mark,
            colorHex: player.colorHex ?? "#1E88E5",
            linkedPlayer: player
        )
    }
}
