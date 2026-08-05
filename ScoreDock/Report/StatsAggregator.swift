import Foundation

/// Records derived from finished matches (§7.2).
///
/// **No denormalised stats tables.** §7.2 is explicit that those are the classic source of drift,
/// and that the denormalised fields already on `MatchSide` — `finalScore`, `outcome`, `resultRank`
/// — make the common queries cheap enough to compute on demand. If profiling ever shows a real
/// problem past ~2,000 matches, add a cache recomputed on completion; do not add it pre-emptively.
struct CompetitorRecord: Identifiable, Sendable, Hashable {
    /// A saved team/player id where one exists, otherwise the ad-hoc name.
    var id: String
    var name: String
    var emoji: String?
    var colorHex: String
    var played = 0
    var won = 0
    var drawn = 0
    var lost = 0
    var pointsFor = 0
    var pointsAgainst = 0
    /// Longest run of consecutive wins, in chronological order.
    var longestWinStreak = 0

    var winRate: Double { played == 0 ? 0 : Double(won) / Double(played) }
    var pointsDifference: Int { pointsFor - pointsAgainst }
    var averageMargin: Double { played == 0 ? 0 : Double(pointsDifference) / Double(played) }
}

struct PlayerRecord: Identifiable, Sendable, Hashable {
    var id: UUID
    var name: String
    var matches = 0
    var points = 0
    var averagePoints: Double { matches == 0 ? 0 : Double(points) / Double(matches) }
}

struct HeadToHead: Sendable, Hashable {
    var left: String
    var right: String
    var leftWins = 0
    var rightWins = 0
    var draws = 0
    var meetings: Int { leftWins + rightWins + draws }
}

enum StatsAggregator {
    /// Only completed matches count. An abandoned game has a log worth keeping but no result worth
    /// recording, and a live one has not happened yet.
    static func completed(_ matches: [Match]) -> [Match] {
        matches.filter { $0.status == .finished }.sorted { $0.startedAt < $1.startedAt }
    }

    static func competitorRecords(from matches: [Match]) -> [CompetitorRecord] {
        var records: [String: CompetitorRecord] = [:]
        var streaks: [String: Int] = [:]

        for match in completed(matches) {
            let sides = match.orderedSides
            for side in sides {
                let key = identity(of: side)
                var record = records[key] ?? CompetitorRecord(
                    id: key,
                    name: side.displayName,
                    emoji: side.emoji,
                    colorHex: side.colorHex
                )

                record.played += 1
                record.pointsFor += side.finalScore
                record.pointsAgainst += sides
                    .filter { $0.slotIndex != side.slotIndex }
                    .map(\.finalScore)
                    .max() ?? 0

                switch side.outcome {
                case .win:
                    record.won += 1
                    streaks[key, default: 0] += 1
                case .draw:
                    record.drawn += 1
                    streaks[key] = 0
                case .loss, .unfinished:
                    record.lost += side.outcome == .loss ? 1 : 0
                    streaks[key] = 0
                }

                record.longestWinStreak = max(record.longestWinStreak, streaks[key] ?? 0)
                records[key] = record
            }
        }

        return records.values.sorted {
            if $0.won != $1.won { return $0.won > $1.won }
            if $0.winRate != $1.winRate { return $0.winRate > $1.winRate }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Per-player totals, from attributed events only (§7.2).
    static func playerRecords(from matches: [Match]) -> [PlayerRecord] {
        var records: [UUID: PlayerRecord] = [:]

        for match in completed(matches) where match.attributionEnabled {
            let undone = MatchReplay.undoneIndices(in: match.orderedEvents)
            var seenThisMatch: Set<UUID> = []

            for event in match.orderedEvents
            where event.kind == .score && !undone.contains(event.index) && event.value > 0 {
                guard let playerID = event.attributedPlayerID else { continue }
                var record = records[playerID] ?? PlayerRecord(
                    id: playerID,
                    name: name(for: playerID, in: match)
                        ?? String(localized: "Player", comment: "Unknown player")
                )
                record.points += event.value
                if seenThisMatch.insert(playerID).inserted { record.matches += 1 }
                records[playerID] = record
            }
        }

        return records.values.sorted { $0.points > $1.points }
    }

    static func headToHead(_ left: String, _ right: String, from matches: [Match]) -> HeadToHead {
        var result = HeadToHead(left: left, right: right)

        for match in completed(matches) {
            let sides = match.orderedSides
            guard sides.count == 2 else { continue }
            let keys = sides.map(identity(of:))
            guard keys.contains(left), keys.contains(right), left != right else { continue }

            guard let leftSide = sides.first(where: { identity(of: $0) == left }) else { continue }
            switch leftSide.outcome {
            case .win: result.leftWins += 1
            case .loss: result.rightWins += 1
            case .draw: result.draws += 1
            case .unfinished: break
            }
        }
        return result
    }

    static func mostPlayedPreset(from matches: [Match]) -> (slug: String, count: Int)? {
        let counts = Dictionary(completed(matches).map { ($0.presetSlug, 1) }, uniquingKeysWith: +)
        guard let best = counts.max(by: { $0.value < $1.value }) else { return nil }
        return (best.key, best.value)
    }

    /// Groups by the saved record where there is one, so a team that was renamed does not split
    /// into two rows — and two ad-hoc sides typed the same way do merge, which is what a user
    /// scoring casual games expects.
    static func identity(of side: MatchSide) -> String {
        if let team = side.linkedTeam { return "team:\(team.id.uuidString)" }
        if let player = side.linkedPlayer { return "player:\(player.id.uuidString)" }
        return "name:\(side.displayName.lowercased())"
    }

    private static func name(for playerID: UUID, in match: Match) -> String? {
        for side in match.orderedSides {
            if let player = side.linkedPlayer, player.id == playerID { return player.displayName }
            for membership in side.linkedTeam?.roster ?? [] where membership.player?.id == playerID {
                return membership.player?.displayName
            }
        }
        return nil
    }
}
