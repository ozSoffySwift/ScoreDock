import Foundation
import SwiftData

/// A side as configured in Setup, before the match exists.
struct SideDraft: Identifiable, Hashable {
    var id = UUID()
    var displayName: String
    var shortName: String
    var emoji: String?
    var colorHex: String
    var linkedTeam: Team?
    var linkedPlayer: Player?

    init(
        displayName: String,
        shortName: String? = nil,
        emoji: String? = nil,
        colorHex: String,
        linkedTeam: Team? = nil,
        linkedPlayer: Player? = nil
    ) {
        self.displayName = displayName
        self.shortName = shortName ?? String(displayName.prefix(4)).uppercased()
        self.emoji = emoji
        self.colorHex = colorHex
        self.linkedTeam = linkedTeam
        self.linkedPlayer = linkedPlayer
    }

    /// The two defaults a blank setup starts from.
    static func defaults() -> [SideDraft] {
        [
            SideDraft(
                displayName: String(localized: "Home", comment: "Default home side name"),
                colorHex: "#1E88E5"
            ),
            SideDraft(
                displayName: String(localized: "Guest", comment: "Default visitor side name"),
                colorHex: "#E53935"
            ),
        ]
    }
}

/// Creates the `Match` record that a `LiveMatchStore` then runs.
@MainActor
enum MatchBuilder {
    /// Takes an `AnyRuleSet` rather than a specific engine's rules, so one builder serves every
    /// engine (§6). The engine is already implied by the payload's tag.
    static func make(
        preset: GamePreset,
        rules: AnyRuleSet,
        title: String?,
        venue: String?,
        themeID: String,
        attributionEnabled: Bool,
        sides: [SideDraft],
        in context: ModelContext
    ) -> Match {
        let match = Match(
            presetSlug: preset.origin.storageKey,
            // Frozen at kickoff: editing the preset afterwards must never rewrite history (§7.1).
            rulesSnapshot: rules,
            themeSnapshot: BuiltInThemes.theme(id: themeID),
            title: title?.isEmpty == true ? nil : title,
            venue: venue?.isEmpty == true ? nil : venue,
            startedAt: .now,
            status: .setup,
            attributionEnabled: attributionEnabled
        )
        context.insert(match)

        for (slot, draft) in sides.enumerated() {
            let side = MatchSide(
                slotIndex: slot,
                displayName: draft.displayName,
                shortName: draft.shortName,
                emoji: draft.emoji,
                // Identity is copied, not referenced, so the finished match still renders correctly
                // once the team is renamed, recoloured or deleted (§7.1).
                image: draft.linkedTeam?.image ?? draft.linkedPlayer?.image,
                mark: draft.linkedTeam?.mark ?? draft.linkedPlayer?.mark ?? (draft.emoji == nil ? .initials : .emoji),
                colorHex: draft.colorHex,
                linkedTeam: draft.linkedTeam,
                linkedPlayer: draft.linkedPlayer
            )
            side.match = match
            context.insert(side)
        }

        try? context.save()
        return match
    }
}
