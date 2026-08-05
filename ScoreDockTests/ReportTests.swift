import Foundation
import SwiftData
import Testing

@testable import ScoreDock

/// §13.3–13.6 — the statistics, and the five share formats built on top of them.
@Suite("Match report and sharing (§13)")
@MainActor
struct ReportTests {
    static let tip = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func at(_ seconds: TimeInterval) -> Date { Self.tip.addingTimeInterval(seconds) }

    /// Builds a finished match by driving the real store, so the log under test is one the app
    /// would actually have written.
    private func playedMatch(
        script: (LiveMatchStore, (TimeInterval) -> Date) -> Void
    ) throws -> Match {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let preset = try #require(BuiltInCatalog.bySlug["basketball"])
        let rules = try #require(preset.rules.teamRules)

        let match = MatchBuilder.make(
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
            rules: .team(rules),
            title: "Round 3",
            venue: "Community Hall",
            themeID: "dark",
            attributionEnabled: false,
            sides: [
                SideDraft(displayName: "Wolves", emoji: "🐺", colorHex: "#42A5F5"),
                SideDraft(displayName: "Eagles", emoji: "🦅", colorHex: "#EF5350"),
            ],
            in: context
        )
        let store = try #require(LiveMatchStore(match: match, context: context))
        script(store) { at($0) }
        return match
    }

    // MARK: Statistics

    @Test("Per-period breakdown splits scores by the period they happened in")
    func periodBreakdown() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 10), at: at(1))
            store.perform(.score(slot: 1, points: 8), at: at(2))
            store.perform(.advancePeriod, at: at(3))
            store.perform(.score(slot: 0, points: 5), at: at(4))
            store.perform(.score(slot: 1, points: 9), at: at(5))
            store.finish(at: at(6))
        }

        let summary = MatchStatistics.summarize(match)
        #expect(summary.periodLines.count == 2)
        #expect(summary.periodLines[0].scores == [10, 8])
        #expect(summary.periodLines[1].scores == [5, 9])
        #expect(summary.finalScores == [15, 17])
    }

    @Test("Lead changes count only when the lead actually passes over")
    func leadChanges() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 2), at: at(1))   // Wolves lead
            store.perform(.score(slot: 1, points: 3), at: at(2))   // Eagles lead — change 1
            store.perform(.score(slot: 1, points: 2), at: at(3))   // still Eagles
            store.perform(.score(slot: 0, points: 4), at: at(4))   // Wolves lead — change 2
            store.finish(at: at(5))
        }

        #expect(MatchStatistics.summarize(match).leadChanges == 2)
    }

    @Test("Largest lead and longest unanswered run are tracked")
    func leadAndRun() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 3), at: at(1))
            store.perform(.score(slot: 0, points: 3), at: at(2))
            store.perform(.score(slot: 0, points: 3), at: at(3))   // 9–0 run
            store.perform(.score(slot: 1, points: 2), at: at(4))
            store.finish(at: at(5))
        }

        let summary = MatchStatistics.summarize(match)
        #expect(summary.largestLead == .init(slotIndex: 0, margin: 9))
        #expect(summary.longestRun == .init(slotIndex: 0, points: 9))
    }

    /// An undone basket must not leave a phantom lead change or run behind.
    @Test("Undone events are excluded from statistics")
    func undoneEventsExcluded() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 2), at: at(1))
            store.perform(.score(slot: 1, points: 5), at: at(2))
            store.undo(at: at(3))                                   // Eagles' 5 is cancelled
            store.finish(at: at(4))
        }

        let summary = MatchStatistics.summarize(match)
        #expect(summary.finalScores == [2, 0])
        #expect(summary.leadChanges == 0)
    }

    /// Time in lead counts only while the clock is running — half-time is not time spent leading.
    @Test("Time in lead ignores stopped-clock periods")
    func timeInLeadIgnoresStoppages() throws {
        let match = try playedMatch { store, at in
            store.perform(.toggleClock, at: at(0))
            store.perform(.score(slot: 0, points: 2), at: at(10))   // Wolves lead from here
            store.perform(.toggleClock, at: at(40))                 // clock stops at +30s of lead
            store.perform(.score(slot: 1, points: 1), at: at(400))  // long stoppage, no lead time
            store.finish(at: at(500))
        }

        let summary = MatchStatistics.summarize(match)
        #expect(summary.timeInLead[0] == 30, "only the 30 running seconds count")
        #expect(summary.timeInLead[1] == 0)
    }

    // MARK: Text and CSV

    @Test("Text export leads with an emoji score line that reads in a chat")
    func textExport() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 62), at: at(1))
            store.perform(.score(slot: 1, points: 58), at: at(2))
            store.finish(at: at(3))
        }

        let model = MatchExportBuilder.build(match, options: ExportOptions())
        let text = MatchTextExport.render(model)

        #expect(text.hasPrefix("🐺 Wolves 62 – 58 Eagles 🦅"))
        #expect(text.contains("Community Hall"))
        #expect(text.contains("ScoreDock"), "watermark is on by default")
    }

    @Test("Watermark can be removed, and removing it is free")
    func watermarkOptional() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 1), at: at(1))
            store.finish(at: at(2))
        }
        let model = MatchExportBuilder.build(match, options: ExportOptions(includeWatermark: false))
        #expect(!MatchTextExport.render(model).contains("Scored with ScoreDock"))
    }

    @Test("CSV quotes fields that would otherwise break the format")
    func csvEscaping() {
        #expect(MatchCSVExport.escape("plain") == "plain")
        #expect(MatchCSVExport.escape("a,b") == "\"a,b\"")
        #expect(MatchCSVExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(MatchCSVExport.escape("line\nbreak") == "\"line\nbreak\"")
    }

    @Test("CSV has one row per event plus a header, including undone ones")
    func csvRowCount() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 2), at: at(1))
            store.perform(.score(slot: 1, points: 3), at: at(2))
            store.undo(at: at(3))
            store.finish(at: at(4))
        }

        let model = MatchExportBuilder.build(match, options: ExportOptions())
        let rows = MatchCSVExport.render(model).split(separator: "\n")

        #expect(rows.count == match.orderedEvents.count + 1)
        // The undone event is present with a flag, not silently dropped (§13.3).
        #expect(rows.contains { $0.hasSuffix(",true") })
    }

    // MARK: Anonymisation

    /// §13.6: anonymising also strips identity images — a photo defeats the purpose otherwise.
    @Test("Anonymising removes names, emoji, images and venue")
    func anonymisation() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 3), at: at(1))
            store.finish(at: at(2))
        }
        match.orderedSides[0].image = Data([0x01, 0x02, 0x03])

        let model = MatchExportBuilder.build(match, options: ExportOptions(anonymisePlayers: true))

        #expect(!model.sides.contains { $0.name == "Wolves" })
        #expect(model.sides.allSatisfy { $0.emoji == nil })
        #expect(model.sides.allSatisfy { $0.imageData == nil })
        #expect(model.venue == nil)
        #expect(!MatchTextExport.render(model).contains("Community Hall"))
    }

    // MARK: .sdgame

    @Test("A game file round-trips through encode and decode")
    func sdGameRoundTrip() throws {
        let match = try playedMatch { store, at in
            store.perform(.toggleClock, at: at(0))
            store.perform(.score(slot: 0, points: 3), at: at(10))
            store.perform(.score(slot: 1, points: 2), at: at(20))
            store.finish(at: at(30))
        }

        let model = MatchExportBuilder.build(match, options: ExportOptions())
        let data = try SdGameDocument(model).encoded()
        let decoded = try SdGameDocument.decode(data)

        #expect(decoded.version == SdGameDocument.currentVersion)
        #expect(decoded.title == "Round 3")
        #expect(decoded.sides.map(\.finalScore) == [3, 2])
        #expect(decoded.events.count == match.orderedEvents.count)
    }

    /// §17 risk 11 — an imported file is untrusted.
    @Test("Oversized game files are refused before parsing")
    func sdGameSizeCeiling() {
        let oversized = Data(repeating: 0x20, count: SdGameDocument.maxFileBytes + 1)
        #expect(throws: SdGameDocument.ImportError.self) {
            try SdGameDocument.decode(oversized)
        }
    }

    @Test("Malformed and future-version game files are refused")
    func sdGameRejectsBadInput() {
        #expect(throws: SdGameDocument.ImportError.self) {
            try SdGameDocument.decode(Data("{ not json".utf8))
        }

        let future = Data(#"{"version":99,"exportedAt":"2026-07-29T00:00:00Z","appName":"x","matchID":"00000000-0000-0000-0000-000000000000","title":"t","presetSlug":"s","presetName":"s","startedAt":"2026-07-29T00:00:00Z","status":"finished","themeID":"dark","sides":[],"events":[]}"#.utf8)
        #expect(throws: SdGameDocument.ImportError.self) {
            try SdGameDocument.decode(future)
        }
    }

    /// An imported file must never overwrite the recipient's own records.
    @Test("Import creates a read-only archived match and touches nothing else")
    func sdGameImportIsInert() throws {
        let source = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 4), at: at(1))
            store.finish(at: at(2))
        }
        let document = SdGameDocument(MatchExportBuilder.build(source, options: ExportOptions()))

        // A fresh store standing in for the recipient's device, with their own data in it.
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let existingPlayer = Player(name: "Their player")
        let existingTeam = Team(name: "Their team")
        context.insert(existingPlayer)
        context.insert(existingTeam)
        context.insert(UserGamePreset(name: "Their preset"))
        try context.save()

        let imported = document.importAsArchivedMatch(into: context)

        #expect(imported.status == .finished)
        #expect(imported.orderedSides.map(\.finalScore) == [4, 0])
        #expect(imported.orderedEvents.count == document.events.count)

        // Nothing of the recipient's was created, altered or duplicated.
        #expect(try context.fetchCount(FetchDescriptor<Player>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<Team>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<UserGamePreset>()) == 1)
    }

    // MARK: Stats aggregation

    @Test("Competitor records accumulate wins, points and streaks")
    func competitorRecords() throws {
        var matches: [Match] = []
        for (home, away) in [(60, 50), (70, 40), (30, 55)] {
            matches.append(try playedMatch { store, at in
                store.perform(.score(slot: 0, points: home), at: at(1))
                store.perform(.score(slot: 1, points: away), at: at(2))
                store.finish(at: at(3))
            })
        }

        let records = StatsAggregator.competitorRecords(from: matches)
        let wolves = try #require(records.first { $0.name == "Wolves" })

        #expect(wolves.played == 3)
        #expect(wolves.won == 2)
        #expect(wolves.lost == 1)
        #expect(wolves.pointsFor == 160)
        #expect(wolves.pointsAgainst == 145)
        #expect(wolves.longestWinStreak == 2)
    }

    @Test("Only finished matches count towards records")
    func abandonedMatchesExcluded() throws {
        let abandoned = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 10), at: at(1))
            store.abandon(at: at(2))
        }
        #expect(StatsAggregator.completed([abandoned]).isEmpty)
        #expect(StatsAggregator.competitorRecords(from: [abandoned]).isEmpty)
    }

    // MARK: Summary line

    /// Builds a table match by driving the real `ListStore`, same approach as `playedMatch`.
    private func tableMatch(
        slug: String,
        sideCount: Int,
        script: (ListStore, (TimeInterval) -> Date) -> Void
    ) throws -> Match {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let preset = try #require(BuiltInCatalog.bySlug[slug])

        let match = MatchBuilder.make(
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
            sides: (0 ..< sideCount).map { SideDraft(displayName: "Team \($0 + 1)", colorHex: "#42A5F5") },
            in: context
        )
        let store = try #require(ListStore(match: match, context: context))
        script(store) { at($0) }
        return match
    }

    @Test("A two-side match summarises as a score line")
    func summaryScoreLine() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 62), at: at(1))
            store.perform(.score(slot: 1, points: 58), at: at(2))
            store.finish(at: at(3))
        }
        #expect(MatchSummaryLine.text(for: match) == "Wolves 62 – Eagles 58")
    }

    /// The bug this replaces: an eight-team league read `Team 1 0 – Team 2 0 – …`, because the score
    /// line was applied to a table and `displayScores` counts only `.score` events.
    @Test("A standings table summarises by rank on points, not by a score line")
    func summaryStandings() throws {
        let match = try tableMatch(slug: "standings", sideCount: 8) { store, at in
            store.perform(.adjustRecord(slot: 0, field: .won, delta: 1), at: at(1))       // 3 pts
            store.perform(.adjustRecord(slot: 1, field: .drawn, delta: 1), at: at(2))     // 1 pt
        }

        let text = MatchSummaryLine.text(for: match)
        #expect(text == "1. Team 1 3 · 2. Team 2 1 · 3. Team 3 0 · +5 more")
        #expect(!text.contains(" – "), "a table is not a score line")
    }

    @Test("A leaderboard summarises the top places and counts the rest")
    func summaryLeaderboard() throws {
        let match = try tableMatch(slug: "leaderboard", sideCount: 5) { store, at in
            store.perform(.score(slot: 2, points: 30), at: at(1))
            store.perform(.score(slot: 4, points: 20), at: at(2))
            store.perform(.score(slot: 0, points: 10), at: at(3))
        }
        #expect(MatchSummaryLine.text(for: match) == "1. Team 3 30 · 2. Team 5 20 · 3. Team 1 10 · +2 more")
    }

    /// Four entrants in the preset's eight-place bracket: quarters 0 and 1 are playable, 2 and 3 have
    /// no entrants at all, semi 4 is fed by 0 and 1, and the final is match 6.
    @Test("A bracket summarises its progress, then its champion")
    func summaryBracket() throws {
        let match = try tableMatch(slug: "tournament", sideCount: 4) { store, at in
            store.perform(.setBracketWinner(match: 0, slot: 1), at: at(1))
        }
        #expect(MatchSummaryLine.text(for: match) == "4 seeds · 1 decided")

        let context = try #require(match.modelContext)
        let store = try #require(ListStore(match: match, context: context))
        store.perform(.setBracketWinner(match: 1, slot: 2), at: at(2))
        store.perform(.setBracketWinner(match: 4, slot: 1), at: at(3))
        #expect(MatchSummaryLine.text(for: match) == "4 seeds · 3 decided", "the final is still open")

        store.perform(.setBracketWinner(match: 6, slot: 1), at: at(4))
        #expect(MatchSummaryLine.text(for: match) == "Champion: Team 2")
    }

    @Test("A closed table reads the same before and after its snapshot is used")
    func summarySurvivesSnapshot() throws {
        let match = try tableMatch(slug: "scoresheet", sideCount: 4) { store, at in
            store.perform(.score(slot: 0, points: 12), at: at(1))
            store.perform(.advancePeriod, at: at(2))
            store.perform(.score(slot: 0, points: 11), at: at(3))
            store.perform(.score(slot: 1, points: 9), at: at(4))
            store.finish(at: at(5))
        }

        // `finish` writes a snapshot, so this read replays nothing.
        #expect(match.stateBlob != nil)
        let withSnapshot = MatchSummaryLine.text(for: match)

        // Dropping it forces a full replay, which must agree — the score sheet's total is the sum of
        // its rounds either way.
        match.stateBlob = nil
        match.snapshotEventIndex = 0
        #expect(MatchSummaryLine.text(for: match) == withSnapshot)
        #expect(withSnapshot == "1. Team 1 23 · 2. Team 2 9 · 3. Team 3 0 · +1 more")
    }

    // MARK: The share card renders the real board (§13.4)

    /// **The bug this exists for.** `ShareCardView` laid the result out on its own terms — sides
    /// stacked as rows, name left, score right — so the card shared from the Match Report looked
    /// nothing like the board the game was played on, and on the bespoke boards it could not express
    /// the result at all: a cricket card cannot say `184-3 in 12.4` with two names and two numbers.
    ///
    /// The card now renders the same views the board uses, which makes it identical by construction.
    /// This asserts the export carries the board that makes that possible.
    @Test("Every engine's export carries its real board", arguments: ResumeTests.presetsByEngine)
    func exportCarriesTheBoard(preset: (slug: String, engine: EngineKind)) throws {
        let container = try AppModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let catalogPreset = try #require(BuiltInCatalog.bySlug[preset.slug])

        let match = MatchBuilder.make(
            preset: GamePreset(
                origin: .builtIn(slug: catalogPreset.slug),
                name: catalogPreset.name,
                emoji: catalogPreset.emoji,
                engine: catalogPreset.engine,
                category: catalogPreset.category,
                rules: catalogPreset.rules,
                defaultThemeID: catalogPreset.defaultThemeID,
                sortIndex: 0
            ),
            rules: catalogPreset.rules,
            title: nil,
            venue: nil,
            themeID: catalogPreset.defaultThemeID,
            attributionEnabled: false,
            sides: (0 ..< 2).map { SideDraft(displayName: "Side \($0 + 1)", colorHex: "#42A5F5") },
            in: context
        )

        let model = MatchExportBuilder.build(match, options: ExportOptions())
        let board = try #require(model.board, "\(preset.slug) exported no board to render")

        // The board must match the engine that played the match, or the card draws the wrong sport.
        switch (catalogPreset.engine, board) {
        case (.team, .team), (.setMatch, .setMatch), (.list, .list), (.specialised, .specialised):
            break
        default:
            Issue.record("\(preset.slug) exported a \(board) for a \(catalogPreset.engine) match")
        }

        #expect(board.preferredAspect > 0)
    }

    /// A card that cannot read the rules still has to show something.
    @Test("An undecodable match exports no board rather than a wrong one")
    func undecodableMatchHasNoBoard() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 2), at: at(1))
            store.finish(at: at(2))
        }
        match.rulesData = Data("not a rule set".utf8)

        let model = MatchExportBuilder.build(match, options: ExportOptions())
        #expect(model.board == nil, "a board drawn from rules that cannot be read would be a lie")
        // The card falls back to a score line, so the export is still usable.
        #expect(!model.scoreLine.isEmpty)
    }

    /// The card is rendered in the match's frozen theme (§13.4), not the app's current one.
    @Test("The exported board keeps the match's own theme")
    func exportKeepsTheMatchTheme() throws {
        let match = try playedMatch { store, at in
            store.perform(.score(slot: 0, points: 5), at: at(1))
            store.finish(at: at(2))
        }
        let model = MatchExportBuilder.build(match, options: ExportOptions())
        #expect(model.themeID == "dark")
    }
}
