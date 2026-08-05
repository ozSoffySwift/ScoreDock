import Foundation

/// Everything §13.3 says is computed at match end.
///
/// Derived from the event log rather than stored as it goes, so it stays correct through undo — an
/// undone basket must not leave a phantom lead change behind. Pure and `Sendable`, so it can be
/// computed for a share export off the main actor.
struct MatchSummary: Sendable, Hashable {
    struct LeadRecord: Sendable, Hashable {
        var slotIndex: Int
        var margin: Int
    }

    struct RunRecord: Sendable, Hashable {
        var slotIndex: Int
        var points: Int
    }

    struct PeriodLine: Sendable, Hashable, Identifiable {
        var period: Int
        var scores: [Int]
        var id: Int { period }
    }

    var sideCount: Int
    var finalScores: [Int]
    /// One row per period played, in order — the §13.4 per-period breakdown.
    var periodLines: [PeriodLine]
    /// Times the lead passed from one side to another. A tie is not a lead change; taking the lead
    /// back from a tie is.
    var leadChanges: Int
    var largestLead: LeadRecord?
    /// The longest streak of unanswered points.
    var longestRun: RunRecord?
    /// Time each side spent ahead, counted **only while the clock was running** — stoppages are not
    /// time spent leading.
    var timeInLead: [TimeInterval]
    var tiedTime: TimeInterval
    /// Points credited to each player, where attribution was on (§4.1).
    var playerTotals: [UUID: Int]
    var scoringPlays: Int
    var totalEvents: Int

    var isEmpty: Bool { totalEvents == 0 }
}

enum MatchStatistics {
    /// Replays the log to produce the summary.
    ///
    /// Undone events are skipped, using the same resolution as state replay (§6.6) — statistics and
    /// the board must never disagree about what happened.
    static func summarize(_ match: Match) -> MatchSummary {
        let sides = match.orderedSides
        let sideCount = max(sides.count, 2)
        let events = match.orderedEvents
        let undone = MatchReplay.undoneIndices(in: events)
        let live = events.filter { !undone.contains($0.index) && $0.kind != .undo }

        var scores = Array(repeating: 0, count: sideCount)
        var periodTotals: [Int: [Int]] = [:]
        var playerTotals: [UUID: Int] = [:]

        var leadChanges = 0
        var largestLead: MatchSummary.LeadRecord?
        var longestRun: MatchSummary.RunRecord?
        var currentRunSlot: Int?
        var currentRunPoints = 0
        var previousLeader: Int?

        var timeInLead = Array(repeating: TimeInterval(0), count: sideCount)
        var tiedTime: TimeInterval = 0
        var clockRunning = false
        var lastTimestamp: Date?
        var scoringPlays = 0

        func creditInterval(upTo timestamp: Date) {
            // Only count while the clock was running: a side is not "leading for 15 minutes"
            // because half-time happened.
            guard clockRunning, let last = lastTimestamp else { return }
            let span = max(0, timestamp.timeIntervalSince(last))
            guard span > 0 else { return }
            if let leader = leader(of: scores) {
                timeInLead[leader] += span
            } else {
                tiedTime += span
            }
        }

        for event in live {
            creditInterval(upTo: event.timestamp)
            lastTimestamp = event.timestamp

            switch event.kind {
            case .score:
                guard let slot = event.slotIndex, scores.indices.contains(slot) else { break }
                scores[slot] = max(0, scores[slot] + event.value)

                periodTotals[event.period, default: Array(repeating: 0, count: sideCount)][slot] += event.value
                if event.value > 0 { scoringPlays += 1 }

                if let playerID = event.attributedPlayerID, event.value > 0 {
                    playerTotals[playerID, default: 0] += event.value
                }

                // Unanswered-points run.
                if event.value > 0 {
                    if currentRunSlot == slot {
                        currentRunPoints += event.value
                    } else {
                        currentRunSlot = slot
                        currentRunPoints = event.value
                    }
                    if currentRunPoints > (longestRun?.points ?? 0) {
                        longestRun = .init(slotIndex: slot, points: currentRunPoints)
                    }
                }

                // Lead change and largest lead.
                let nowLeading = leader(of: scores)
                if let nowLeading, let previousLeader, nowLeading != previousLeader {
                    leadChanges += 1
                }
                if let nowLeading {
                    let margin = scores[nowLeading] - (scores.enumerated()
                        .filter { $0.offset != nowLeading }
                        .map(\.element)
                        .max() ?? 0)
                    if margin > (largestLead?.margin ?? 0) {
                        largestLead = .init(slotIndex: nowLeading, margin: margin)
                    }
                    previousLeader = nowLeading
                }

            case .clockToggle:
                clockRunning.toggle()

            case .matchFinish:
                clockRunning = false

            case .breakStart:
                clockRunning = false

            default:
                break
            }
        }

        if let end = match.endedAt { creditInterval(upTo: end) }

        let periodLines = periodTotals.keys.sorted().map {
            MatchSummary.PeriodLine(period: $0, scores: periodTotals[$0] ?? Array(repeating: 0, count: sideCount))
        }

        return MatchSummary(
            sideCount: sideCount,
            finalScores: scores,
            periodLines: periodLines,
            leadChanges: leadChanges,
            largestLead: largestLead,
            longestRun: longestRun,
            timeInLead: timeInLead,
            tiedTime: tiedTime,
            playerTotals: playerTotals,
            scoringPlays: scoringPlays,
            totalEvents: live.count
        )
    }

    /// The single leading slot, or nil when the top score is shared.
    private static func leader(of scores: [Int]) -> Int? {
        guard let best = scores.max() else { return nil }
        let leaders = scores.indices.filter { scores[$0] == best }
        return leaders.count == 1 ? leaders[0] : nil
    }
}
