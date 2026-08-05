import SwiftUI

/// The cricket board (§6.3).
///
/// **The score leads, and the overs sit beside it** — `184-3` in `12.4` is the sentence a cricket
/// board says, and everything else (rates, target, partnership) is a footnote to it. Completed
/// innings run along the top the way a scoreboard carries the first-innings total through the chase.
struct CricketBoardView: View {
    var board: DerivedCricketBoard
    var sides: [BoardSideInfo]
    var theme: ThemeSpec
    var font: BoardFont

    var isCompact: Bool = false
    var isInteractive: Bool = true

    private static let aspectRatio: CGFloat = 1.9

    var body: some View {
        GeometryReader { geometry in
            let height = max(1, min(geometry.size.height, geometry.size.width / Self.aspectRatio))
            let scoreSize = height * (isCompact ? 0.30 : 0.34)
            let oversSize = height * (isCompact ? 0.18 : 0.20)
            let labelSize = max(9, height * 0.065)

            VStack(alignment: .leading, spacing: height * 0.03) {
                header(labelSize: labelSize)
                scoreLine(scoreSize: scoreSize, oversSize: oversSize, labelSize: labelSize)
                footnotes(labelSize: labelSize)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, height * 0.05)
            .padding(.vertical, height * 0.04)
            .frame(width: geometry.size.width, height: height, alignment: .topLeading)
            .frame(maxHeight: .infinity)
        }
        .background(theme.backgroundColor)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func header(labelSize: CGFloat) -> some View {
        HStack(spacing: labelSize * 0.6) {
            let batting = sides.indices.contains(board.battingSlot) ? sides[board.battingSlot] : BoardSideInfo()

            if let emoji = batting.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: labelSize * 1.3))
            }
            Text(batting.displayName.uppercased())
                .font(.system(size: labelSize * 1.2, weight: .heavy))
                .foregroundStyle(Color(hex: batting.colorHex))
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            Spacer(minLength: 0)

            // The first-innings total, carried through the chase.
            ForEach(Array(board.completedInnings.enumerated()), id: \.offset) { _, line in
                let side = sides.indices.contains(line.battingSlot) ? sides[line.battingSlot] : BoardSideInfo()
                Text("\(side.shortName.uppercased()) \(line.isAllOut ? "\(line.runs)" : "\(line.runs)-\(line.wickets)")")
                    .font(.system(size: labelSize * 0.85, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.labelColor.opacity(0.75))
            }

            Text("INN \(board.inningsNumber)", comment: "Cricket board label")
                .font(.system(size: labelSize * 0.85, weight: .heavy))
                .foregroundStyle(theme.labelColor.opacity(0.6))
        }
    }

    private func scoreLine(scoreSize: CGFloat, oversSize: CGFloat, labelSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: labelSize) {
            LEDNumber(text: board.scoreText, theme: theme, font: font, size: scoreSize)
                .foregroundStyle(theme.digitColor)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 0) {
                Text("OVERS", comment: "Cricket board label")
                    .font(.system(size: labelSize * 0.7, weight: .heavy))
                    .tracking(labelSize * 0.06)
                    .foregroundStyle(theme.labelColor.opacity(0.7))
                LEDNumber(text: board.oversText, theme: theme, font: font, size: oversSize)
                    .foregroundStyle(theme.digitColor)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Score", comment: "Accessibility"))
        .accessibilityValue(Text(
            "\(board.runs) for \(board.wickets), \(board.oversText) overs",
            comment: "Accessibility value"
        ))
    }

    private func footnotes(labelSize: CGFloat) -> some View {
        HStack(spacing: labelSize) {
            note(String(localized: "RR", comment: "Cricket run rate"), rate(board.runRate), labelSize: labelSize)

            if let required = board.requiredRate {
                note(String(localized: "REQ", comment: "Cricket required rate"), rate(required), labelSize: labelSize)
            }

            note(String(localized: "P'SHIP", comment: "Cricket partnership"), "\(board.partnership)", labelSize: labelSize)
            note(String(localized: "EXT", comment: "Cricket extras"), "\(board.extras)", labelSize: labelSize)

            Spacer(minLength: 0)

            if let needed = board.runsNeeded, let balls = board.ballsRemaining, needed > 0 {
                Text("NEED \(needed) OFF \(balls)", comment: "Cricket chase")
                    .font(.system(size: labelSize * 0.95, weight: .heavy).monospacedDigit())
                    .foregroundStyle(theme.accentColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private func note(_ label: String, _ value: String, labelSize: CGFloat) -> some View {
        HStack(spacing: labelSize * 0.2) {
            Text(label)
                .font(.system(size: labelSize * 0.7, weight: .heavy))
                .foregroundStyle(theme.labelColor.opacity(0.6))
            Text(value)
                .font(.system(size: labelSize * 0.95, weight: .semibold).monospacedDigit())
                .foregroundStyle(theme.labelColor)
        }
    }

    private func rate(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}

#Preview("Chasing") {
    let rules = BuiltInCatalog.bySlug["cricket"]?.rules.specialisedRules?.cricket ?? CricketRules()
    var state = CricketEngine.initialState(rules: rules, sideCount: 2)
    for _ in 0 ..< 120 {
        CricketEngine.apply(.specialised(.delivery(runs: 1, extra: nil)), to: &state, rules: rules, at: .now)
    }
    for _ in 0 ..< 40 {
        CricketEngine.apply(.specialised(.delivery(runs: 2, extra: nil)), to: &state, rules: rules, at: .now)
    }
    CricketEngine.apply(.specialised(.wicket(kind: .caught)), to: &state, rules: rules, at: .now)

    return CricketBoardView(
        board: CricketEngine.derived(state, rules: rules, sideCount: 2, isFinished: false, at: .now),
        sides: [
            BoardSideInfo(displayName: "Sixers", shortName: "SIX", colorHex: "#EC407A"),
            BoardSideInfo(displayName: "Strikers", shortName: "STR", colorHex: "#42A5F5"),
        ],
        theme: BuiltInThemes.theme(id: "grass"),
        font: .sevenSegment
    )
    .frame(height: 220)
}
