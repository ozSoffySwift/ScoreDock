import SwiftUI

/// The baseball board (§6.3).
///
/// **The line score is the board.** Every other sport here has a score; baseball has a *table* —
/// runs by inning, then R / H / E — and that grid is what a ballpark scoreboard shows. The count,
/// the outs and the diamond sit beneath it, because they change every pitch while the table only
/// changes when something happens.
struct BaseballBoardView: View {
    var board: DerivedBaseballBoard
    var sides: [BoardSideInfo]
    var theme: ThemeSpec
    var font: BoardFont

    var isCompact: Bool = false
    var isInteractive: Bool = true

    /// Innings to show at once. A full nine plus R/H/E does not fit a phone's width legibly, so the
    /// grid scrolls and the totals stay pinned.
    private static let visibleInnings = 9

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let labelSize = max(8, min(height * 0.075, geometry.size.width * 0.030))

            VStack(alignment: .leading, spacing: labelSize * 0.5) {
                lineScore(labelSize: labelSize)
                Divider().overlay(theme.labelColor.opacity(0.25))
                situation(labelSize: labelSize, height: height)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, labelSize)
            .padding(.vertical, labelSize * 0.8)
            .frame(width: geometry.size.width, height: height, alignment: .topLeading)
        }
        .background(theme.backgroundColor)
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: Line score

    private func lineScore(labelSize: CGFloat) -> some View {
        let cell = labelSize * 1.5
        let innings = min(board.inningsPlayed, Self.visibleInnings)

        return VStack(alignment: .leading, spacing: labelSize * 0.25) {
            HStack(spacing: 0) {
                Text("").frame(width: labelSize * 4.5, alignment: .leading)
                ForEach(1 ... max(1, innings), id: \.self) { inning in
                    Text("\(inning)")
                        .font(.system(size: labelSize * 0.8, weight: .heavy).monospacedDigit())
                        .foregroundStyle(theme.labelColor.opacity(0.6))
                        .frame(width: cell)
                }
                totalHeader("R", labelSize: labelSize, cell: cell)
                if board.showsHitsAndErrors {
                    totalHeader("H", labelSize: labelSize, cell: cell)
                    totalHeader("E", labelSize: labelSize, cell: cell)
                }
            }

            ForEach(board.sides, id: \.slotIndex) { side in
                row(side, labelSize: labelSize, cell: cell, innings: innings)
            }
        }
    }

    private func totalHeader(_ text: String, labelSize: CGFloat, cell: CGFloat) -> some View {
        Text(text)
            .font(.system(size: labelSize * 0.85, weight: .heavy))
            .foregroundStyle(theme.labelColor)
            .frame(width: cell * 1.2)
    }

    private func row(
        _ side: DerivedBaseballBoard.Side,
        labelSize: CGFloat,
        cell: CGFloat,
        innings: Int
    ) -> some View {
        let info = sides.indices.contains(side.slotIndex) ? sides[side.slotIndex] : BoardSideInfo()

        return HStack(spacing: 0) {
            HStack(spacing: labelSize * 0.2) {
                // A marker as well as a highlight, so "at bat" is not colour alone (§15).
                Text(side.isBatting ? "▶" : " ")
                    .font(.system(size: labelSize * 0.7, weight: .black))
                    .foregroundStyle(theme.accentColor)
                Text(info.shortName.uppercased())
                    .font(.system(size: labelSize * 0.95, weight: .heavy))
                    .foregroundStyle(Color(hex: info.colorHex))
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }
            .frame(width: labelSize * 4.5, alignment: .leading)

            ForEach(0 ..< max(1, innings), id: \.self) { index in
                Text(cellText(side, index))
                    .font(.system(size: labelSize * 0.95, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.labelColor.opacity(0.85))
                    .frame(width: cell)
            }

            total("\(side.runs)", labelSize: labelSize, cell: cell, emphasised: true)
            if board.showsHitsAndErrors {
                total("\(side.hits)", labelSize: labelSize, cell: cell, emphasised: false)
                total("\(side.errors)", labelSize: labelSize, cell: cell, emphasised: false)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(Text("\(info.displayName)", comment: "Accessibility"))
        .accessibilityValue(Text(
            "\(side.runs) runs, \(side.hits) hits, \(side.errors) errors",
            comment: "Accessibility value"
        ))
    }

    /// A blank cell is an inning this side has not batted, which is not the same as a scoreless one.
    private func cellText(_ side: DerivedBaseballBoard.Side, _ index: Int) -> String {
        guard side.lineScore.indices.contains(index), let runs = side.lineScore[index] else { return "–" }
        return "\(runs)"
    }

    private func total(_ text: String, labelSize: CGFloat, cell: CGFloat, emphasised: Bool) -> some View {
        Text(text)
            .font(.system(size: labelSize * (emphasised ? 1.25 : 1), weight: .heavy).monospacedDigit())
            .foregroundStyle(emphasised ? theme.digitColor : theme.labelColor)
            .frame(width: cell * 1.2)
    }

    // MARK: Situation

    private func situation(labelSize: CGFloat, height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: labelSize * 1.4) {
            VStack(spacing: 0) {
                Text(board.inningLabel)
                    .font(.system(size: labelSize * 1.5, weight: .heavy).monospacedDigit())
                    .foregroundStyle(theme.digitColor)
                Text("INNING", comment: "Baseball board label")
                    .font(.system(size: labelSize * 0.65, weight: .heavy))
                    .foregroundStyle(theme.labelColor.opacity(0.6))
            }

            VStack(spacing: 0) {
                Text(board.countText)
                    .font(.system(size: labelSize * 1.5, weight: .heavy).monospacedDigit())
                    .foregroundStyle(theme.digitColor)
                Text("COUNT", comment: "Baseball board label")
                    .font(.system(size: labelSize * 0.65, weight: .heavy))
                    .foregroundStyle(theme.labelColor.opacity(0.6))
            }

            VStack(spacing: labelSize * 0.15) {
                HStack(spacing: labelSize * 0.25) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        Circle()
                            .fill(index < board.outs ? theme.accentColor : theme.labelColor.opacity(0.2))
                            .frame(width: labelSize * 0.7, height: labelSize * 0.7)
                    }
                }
                Text("OUT", comment: "Baseball board label")
                    .font(.system(size: labelSize * 0.65, weight: .heavy))
                    .foregroundStyle(theme.labelColor.opacity(0.6))
            }

            Spacer(minLength: 0)

            diamond(size: labelSize * 3.4)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(
            "\(board.inningLabel), count \(board.countText), \(board.outs) out",
            comment: "Accessibility"
        ))
    }

    /// The bases, drawn where they are — a runner on second is at the far corner, not second in a
    /// row of three lights.
    private func diamond(size: CGFloat) -> some View {
        let base = size * 0.28

        return ZStack {
            baseMarker(board.bases.second, size: base)
                .offset(x: 0, y: -size * 0.32)
            baseMarker(board.bases.first, size: base)
                .offset(x: size * 0.32, y: 0)
            baseMarker(board.bases.third, size: base)
                .offset(x: -size * 0.32, y: 0)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func baseMarker(_ occupied: Bool, size: CGFloat) -> some View {
        Rectangle()
            .fill(occupied ? theme.accentColor : Color.clear)
            .frame(width: size, height: size)
            .overlay {
                Rectangle().strokeBorder(theme.labelColor.opacity(0.45), lineWidth: max(1, size * 0.1))
            }
            .rotationEffect(.degrees(45))
    }
}

#Preview("Bottom of the seventh") {
    let rules = BuiltInCatalog.bySlug["baseball"]?.rules.specialisedRules?.baseball ?? BaseballRules()
    var state = BaseballEngine.initialState(rules: rules, sideCount: 2)
    state.sides[1].runsByInning = [0, 2, 0, 0, 1, 0, 0]
    state.sides[0].runsByInning = [1, 0, 0, 3, 0, 0]
    state.sides[1].hits = 7
    state.sides[0].hits = 9
    state.sides[0].errors = 1
    state.inning = 7
    state.isTop = false
    state.balls = 2
    state.strikes = 1
    state.outs = 1
    state.bases = BaseOccupancy(first: true, second: false, third: true)

    return BaseballBoardView(
        board: BaseballEngine.derived(state, rules: rules, isFinished: false, at: .now),
        sides: [
            BoardSideInfo(displayName: "Bay City", shortName: "BAY", colorHex: "#42A5F5"),
            BoardSideInfo(displayName: "Portland", shortName: "POR", colorHex: "#EF5350"),
        ],
        theme: BuiltInThemes.theme(id: "dark"),
        font: .sevenSegment
    )
    .frame(height: 230)
}
