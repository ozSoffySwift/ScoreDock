import Foundation
import Testing

@testable import ScoreDock

/// §7.1a — one shared identity system, and a guarantee that no code path produces a blank mark.
@Suite("Identity marks (§7.1a)")
struct IdentityTests {
    private func player(
        name: String = "Dana Levi",
        emoji: String? = nil,
        image: Data? = nil,
        mark: IdentityMark = .initials
    ) -> Player {
        Player(name: name, emoji: emoji, image: image, mark: mark)
    }

    @Test("The preferred mark wins when it exists")
    func preferredMarkWins() {
        let image = Data([0x01, 0x02])

        #expect(player(emoji: "🐺", image: image, mark: .emoji).resolvedMark == .emoji("🐺"))
        #expect(player(emoji: "🐺", image: image, mark: .image).resolvedMark == .image(image))
        #expect(player(emoji: "🐺", image: image, mark: .initials).resolvedMark == .initials("DL"))
    }

    /// The preference is a preference, not a promise — a record can prefer `.image` and have none.
    @Test("An unavailable preferred mark falls through image → emoji → initials")
    func fallsThroughWhenPreferredIsMissing() {
        #expect(player(emoji: "🐺", mark: .image).resolvedMark == .emoji("🐺"))
        #expect(player(mark: .image).resolvedMark == .initials("DL"))
        #expect(player(mark: .emoji).resolvedMark == .initials("DL"))

        let image = Data([0xFF])
        #expect(player(image: image, mark: .emoji).resolvedMark == .image(image))
    }

    /// Empty data is treated as absent, so a zero-byte image cannot produce a blank slot.
    @Test("Empty image data is treated as no image")
    func emptyImageIsIgnored() {
        #expect(player(emoji: "🦅", image: Data(), mark: .image).resolvedMark == .emoji("🦅"))
        #expect(player(image: Data(), mark: .image).resolvedMark == .initials("DL"))
    }

    @Test("Initials are always derivable, in any script")
    func initials() {
        #expect(player(name: "Dana Levi").initials == "DL")
        #expect(player(name: "Dana").initials == "D")
        #expect(player(name: "  Dana   Levi  ").initials == "DL")
        #expect(player(name: "Jean-Luc Picard").initials == "JL")
        // Hebrew is uncased; uppercasing is a documented no-op rather than a corruption.
        #expect(player(name: "דנה לוי").initials == "דל")
        // The terminal case genuinely terminates.
        #expect(player(name: "").initials == "?")
        #expect(player(name: "   ").initials == "?")
    }

    @Test("Nickname wins over full name on the board")
    func nicknameWins() {
        let withNickname = Player(name: "Daniel Levi", nickname: "Dani")
        #expect(withNickname.displayName == "Dani")
        #expect(withNickname.initials == "D")

        let withEmptyNickname = Player(name: "Daniel Levi", nickname: "")
        #expect(withEmptyNickname.displayName == "Daniel Levi")
    }

    @Test("Teams and match sides resolve by the same rules")
    func sharedAcrossTypes() {
        let team = Team(name: "Wolves", shortName: "WOL", emoji: "🐺", mark: .emoji)
        #expect(team.resolvedMark == .emoji("🐺"))
        #expect(team.identityColorHex == "#1E88E5")

        let side = MatchSide.from(team: team, slotIndex: 0)
        #expect(side.resolvedMark == .emoji("🐺"))
        #expect(side.displayName == "Wolves")
        #expect(side.shortName == "WOL")

        let bare = MatchSide(slotIndex: 1, displayName: "Visitors")
        #expect(bare.resolvedMark == .initials("V"))
    }

    // MARK: Emoji validation

    /// §7.1a requires validating a single grapheme cluster so the field cannot quietly become a
    /// second name field.
    @Test("Emoji input accepts exactly one emoji cluster")
    func emojiValidation() {
        #expect(EmojiInput.validated("🐺") == "🐺")
        #expect(EmojiInput.validated("  🦅  ") == "🦅")
        // ZWJ sequences and skin-tone modifiers are one cluster.
        #expect(EmojiInput.validated("👨‍👩‍👧") == "👨‍👩‍👧")
        #expect(EmojiInput.validated("🏃🏽‍♀️") == "🏃🏽‍♀️")
        #expect(EmojiInput.validated("🥍") == "🥍")

        // Rejected: text, multiples, empty.
        #expect(EmojiInput.validated("Wolves") == nil)
        #expect(EmojiInput.validated("W") == nil)
        #expect(EmojiInput.validated("🐺🦅") == nil)
        #expect(EmojiInput.validated("") == nil)
        #expect(EmojiInput.validated("   ") == nil)
        #expect(EmojiInput.validated("1") == nil)
    }
}
