import Foundation

/// Suggests a way to finish a darts leg (§6.2).
///
/// Solved rather than tabulated. A hardcoded 2–170 table is 169 rows that have to be typed
/// correctly once and re-checked whenever a rule changes; a search over the board's actual segments
/// is shorter, cannot contain a transcription error, and adapts for free when `doubleOut` is off.
enum DartsCheckout {
    /// Highest score reachable in three darts finishing on a double: T20, T20, Bull.
    static let maximumCheckout = 170

    private struct Segment {
        var value: Int
        var label: String
        var isDouble: Bool
    }

    /// Non-final darts, in the order a player would actually try them: big trebles first, then the
    /// bull, then singles descending.
    private static let scoringSegments: [Segment] = {
        var segments = (1 ... 20).reversed().map {
            Segment(value: $0 * 3, label: "T\($0)", isDouble: false)
        }
        segments.append(Segment(value: 50, label: "BULL", isDouble: true))
        segments.append(Segment(value: 25, label: "25", isDouble: false))
        segments.append(contentsOf: (1 ... 20).reversed().map {
            Segment(value: $0, label: "\($0)", isDouble: false)
        })
        segments.append(contentsOf: (1 ... 20).reversed().map {
            Segment(value: $0 * 2, label: "D\($0)", isDouble: true)
        })
        return segments
    }()

    /// Finishing doubles, ordered the way players prefer to leave them — D20 sits on the 20/40
    /// path, D16 halves cleanly to D8 and D4.
    private static let finishingDoubles: [Segment] = {
        let preferred = [20, 16, 8, 4, 12, 10, 18, 14, 6, 2, 19, 17, 15, 13, 11, 9, 7, 5, 3, 1]
        var segments = preferred.map { Segment(value: $0 * 2, label: "D\($0)", isDouble: true) }
        // The bull counts as a double for checkout purposes.
        segments.insert(Segment(value: 50, label: "BULL", isDouble: true), at: 2)
        return segments
    }()

    /// A suggested finish, e.g. `"T20 T20 BULL"`, or nil when there is no checkout from here.
    static func suggestion(for remaining: Int, doubleOut: Bool) -> String? {
        guard remaining > 1, remaining <= maximumCheckout else { return nil }

        let finishers = doubleOut ? finishingDoubles : scoringSegments

        // One dart.
        if let finish = finishers.first(where: { $0.value == remaining }) {
            return finish.label
        }

        // Two darts.
        for first in scoringSegments where first.value < remaining {
            if let finish = finishers.first(where: { $0.value == remaining - first.value }) {
                return "\(first.label) \(finish.label)"
            }
        }

        // Three darts.
        for first in scoringSegments where first.value < remaining {
            for second in scoringSegments where second.value < remaining - first.value {
                let left = remaining - first.value - second.value
                if let finish = finishers.first(where: { $0.value == left }) {
                    return "\(first.label) \(second.label) \(finish.label)"
                }
            }
        }

        return nil
    }
}
