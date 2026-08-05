import Foundation
import SwiftData

/// Join model between `Player` and `Team`, so one player can be on many teams — a real case for
/// club players, and for a coach who runs several age groups.
///
/// Both sides are optional relationships with their inverses declared on the parent, per §7.5.
@Model
final class TeamMembership {
    var player: Player?
    var team: Team?

    /// Free text rather than an integer: squad numbers are not always numeric, and some sports use
    /// letters or none at all.
    var jersey: String?
    var position: String?
    var joinedAt: Date = Date.now

    /// Left the squad but kept for historical accuracy, matching the archive-don't-delete rule
    /// used on `Player` and `Team`.
    var isActive: Bool = true

    init(
        player: Player? = nil,
        team: Team? = nil,
        jersey: String? = nil,
        position: String? = nil,
        joinedAt: Date = .now,
        isActive: Bool = true
    ) {
        self.player = player
        self.team = team
        self.jersey = jersey
        self.position = position
        self.joinedAt = joinedAt
        self.isActive = isActive
    }
}
