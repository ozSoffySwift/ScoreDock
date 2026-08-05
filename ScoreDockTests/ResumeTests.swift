import Foundation
import SwiftData
import Testing

@testable import ScoreDock

/// §12 and §5.2 — a running match must reopen *and* reach a television, whichever engine runs it.
///
/// **The bug this suite exists for.** Resume was written at M1 against `LiveMatchStore`, the only
/// store there was, and kept building one for every match through three more engines. A live
/// tennis, league or chess match therefore hit the "cannot decode" path — which *retired the match*
/// and told the operator its rules could not be read. Pressing Resume destroyed exactly the thing
/// §12 exists to protect, and it went unnoticed for three milestones because nothing ever resumed a
/// non-team match.
@Suite("Any running match (§5.2, §12)")
@MainActor
struct ResumeTests {
    static let tip = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.tip.addingTimeInterval(seconds) }

    private func makeMatch(slug: String, sideCount: Int = 2, in context: ModelContext) throws -> Match {
        let preset = try #require(BuiltInCatalog.bySlug[slug])
        return MatchBuilder.make(
            preset: GamePreset(
                origin: .builtIn(slug: preset.slug),
                name: preset.name,
                emoji: preset.emoji,
                engine: preset.engine,
                category: preset.category,
                rules: preset.rules,
                defaultThemeID: preset.defaultThemeID,
                sortIndex: 0
            ),
            rules: preset.rules,
            title: nil,
            venue: nil,
            themeID: preset.defaultThemeID,
            attributionEnabled: false,
            sides: (0 ..< sideCount).map {
                SideDraft(displayName: "Side \($0 + 1)", colorHex: "#42A5F5")
            },
            in: context
        )
    }

    /// One preset per engine, so a new engine that forgets to wire itself in fails here.
    /// `nonisolated` because `@Test(arguments:)` reads it from outside the suite's actor.
    nonisolated static let presetsByEngine: [(slug: String, engine: EngineKind)] = [
        ("basketball", .team),
        ("tennis", .setMatch),
        ("standings", .list),
        ("chess-clock", .specialised),
        ("race-timer", .specialised),
        ("american-football", .specialised),
        ("cricket", .specialised),
        ("baseball", .specialised),
    ]

    @Test("Every engine's live match reopens", arguments: presetsByEngine)
    func everyEngineResumes(preset: (slug: String, engine: EngineKind)) throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let match = try makeMatch(slug: preset.slug, in: context)
        match.status = .live

        let resumed = AnyMatchStore(match: match, context: context)

        #expect(resumed != nil, "\(preset.slug) could not be reopened")
        #expect(match.status == .live, "\(preset.slug) was retired by being reopened")
    }

    /// The heart of it: a resumed match has to come back with the score still on it.
    @Test("A resumed match keeps the state its log describes")
    func resumeReplaysTheLog() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let match = try makeMatch(slug: "tennis", in: context)

        let first = try #require(SetMatchStore(match: match, context: context))
        first.perform(.score(slot: 0, points: 1), at: at(1))
        first.perform(.score(slot: 0, points: 1), at: at(2))
        first.perform(.score(slot: 1, points: 1), at: at(3))
        let before = first.board()

        guard case let .setMatch(reopened)? = AnyMatchStore(match: match, context: context) else {
            Issue.record("expected a set-match store")
            return
        }
        #expect(reopened.board() == before)
        #expect(match.status == .live)
    }

    @Test("A specialised match reopens onto the right board")
    func specialisedResumesOntoItsOwnBoard() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let match = try makeMatch(slug: "cricket", in: context)

        let first = try #require(SpecialisedStore(match: match, context: context))
        first.perform(.specialised(.delivery(runs: 4, extra: nil)), at: at(1))
        first.perform(.specialised(.wicket(kind: .bowled)), at: at(2))

        guard case let .specialised(reopened)? = AnyMatchStore(match: match, context: context) else {
            Issue.record("expected a specialised store")
            return
        }
        guard case let .cricket(board) = reopened.board() else {
            Issue.record("expected a cricket board")
            return
        }
        #expect(board.scoreText == "4-1")
        #expect(board.oversText == "0.2")
    }

    // MARK: The external display (§5.2)

    /// The same mistake as resume, in the app's headline feature. `ActiveMatch` held a
    /// `LiveMatchStore?`, so the board reached a TV for a basketball match and silently did not for
    /// anything else — while every one of those panels still offered a Display button and a set of
    /// instructions that ended in a blank screen.
    @Test("Every engine's match can be published to the external display", arguments: presetsByEngine)
    func everyEnginePublishesToTheDisplay(preset: (slug: String, engine: EngineKind)) throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let match = try makeMatch(slug: preset.slug, in: context)
        let store = try #require(AnyMatchStore(match: match, context: context))

        let active = ActiveMatch.shared
        active.begin(store)
        defer { active.end() }

        #expect(active.store?.id == store.id, "\(preset.slug) never reached the external scene")
    }

    /// Offering a mode the board cannot fill puts a permanent dash on a television.
    @Test("A board only offers the modes it can fill", arguments: presetsByEngine)
    func boardModesMatchTheBoard(preset: (slug: String, engine: EngineKind)) throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let match = try makeMatch(slug: preset.slug, in: context)
        let store = try #require(AnyMatchStore(match: match, context: context))

        let modes = BoardMode.available(for: store)
        #expect(modes.contains(.full), "\(preset.slug) cannot show a full board")
        #expect(Set(modes).count == modes.count, "\(preset.slug) lists a mode twice")

        switch preset.slug {
        case "chess-clock", "cricket", "baseball", "tennis", "standings":
            #expect(modes == [.full], "\(preset.slug) has no clock to isolate")
        case "american-football":
            #expect(modes.contains(.shotClockOnly), "the play clock is a shot clock by another name")
            #expect(modes.contains(.timerOnly))
        case "race-timer":
            #expect(modes == [.full, .timerOnly])
        default:
            break
        }
    }

    /// Carrying a mode across two different sports would open the second one on a dash.
    @Test("Starting a new match drops a mode the new board cannot fill")
    func modeResetsBetweenMatches() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let active = ActiveMatch.shared
        defer { active.end() }

        let football = try #require(
            AnyMatchStore(match: try makeMatch(slug: "american-football", in: context), context: context)
        )
        active.begin(football)
        active.boardMode = .shotClockOnly
        #expect(active.boardMode == .shotClockOnly)

        let chess = try #require(
            AnyMatchStore(match: try makeMatch(slug: "chess-clock", in: context), context: context)
        )
        active.begin(chess)
        #expect(active.boardMode == .full, "a chess clock has no shot clock to show")
    }

    // MARK: Failure

    /// The failure path still has to work — but only for a match that genuinely cannot be replayed.
    @Test("A match whose rules cannot be decoded still refuses")
    func undecodableRulesRefuse() throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let match = try makeMatch(slug: "basketball", in: context)

        // Whatever a newer build might have written, this one cannot read it.
        match.rulesData = Data("not a rule set".utf8)

        #expect(AnyMatchStore(match: match, context: context) == nil)
    }
}

extension AnyMatchStore: @retroactive Equatable {
    public static func == (lhs: AnyMatchStore, rhs: AnyMatchStore) -> Bool { lhs.id == rhs.id }
}
