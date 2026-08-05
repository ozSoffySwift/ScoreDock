import SwiftUI

/// The list and table boards (§6.5).
///
/// Four genuinely different layouts over one engine. Unlike the team and set-match boards these are
/// *dense* — a standings table or a score sheet is read close up as often as across a hall — so the
/// type scale is smaller and the board font is used only where a number is the point.
struct ListBoardView: View {
    var board: DerivedListBoard
    var sides: [BoardSideInfo]
    var theme: ThemeSpec
    var font: BoardFont

    var isCompact: Bool = false
    var isInteractive: Bool = true
    var onTapRow: ((Int) -> Void)?
    var onTapMatch: ((Int, Int) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch board.style {
            case .leaderboard: leaderboard
            case .standings: standings
            case .bracket: bracket
            case .scoreSheet: scoreSheet
            }
        }
        .padding(isCompact ? 10 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.backgroundColor)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func name(_ slot: Int) -> String {
        sides.indices.contains(slot) ? sides[slot].displayName : "—"
    }

    private func colour(_ slot: Int) -> Color {
        Color(hex: sides.indices.contains(slot) ? sides[slot].colorHex : "#1E88E5")
    }

    // MARK: Leaderboard

    private var leaderboard: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            ForEach(board.rows) { row in
                HStack(spacing: 12) {
                    rankBadge(row)
                    if let emoji = sides[safe: row.slotIndex]?.emoji, !emoji.isEmpty {
                        Text(emoji).font(.system(size: isCompact ? 18 : 26))
                    }
                    Text(name(row.slotIndex).uppercased())
                        .font(.system(size: isCompact ? 14 : 20, weight: .heavy))
                        .foregroundStyle(theme.labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Spacer(minLength: 8)
                    LEDNumber(text: "\(row.total)", theme: theme, font: font, size: isCompact ? 26 : 40)
                        .foregroundStyle(colour(row.slotIndex))
                        .fixedSize()
                }
                .contentShape(.rect)
                .allowsHitTesting(isInteractive && onTapRow != nil)
                .onTapGesture { onTapRow?(row.slotIndex) }
                .accessibilityElement()
                .accessibilityLabel(Text("\(name(row.slotIndex)), rank \(row.rank)", comment: "Accessibility"))
                .accessibilityValue(Text("\(row.total)"))
            }
        }
        // §6.5 asks for live re-sort with animation; §15 says Reduce Motion removes it.
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: board.rows.map(\.slotIndex))
    }

    private func rankBadge(_ row: DerivedListBoard.Row) -> some View {
        HStack(spacing: 2) {
            // A shared rank is marked, not just shared — §6.5 wants ties handled explicitly, and an
            // unmarked equal position is what starts the argument.
            if row.isTiedRank {
                Text("=")
                    .font(.system(size: isCompact ? 11 : 15, weight: .black))
                    .foregroundStyle(theme.accentColor)
            }
            Text("\(row.rank)")
                .font(.system(size: isCompact ? 14 : 20, weight: .black).monospacedDigit())
                .foregroundStyle(theme.labelColor.opacity(0.7))
        }
        .frame(width: isCompact ? 34 : 46, alignment: .leading)
    }

    // MARK: Standings

    private var standings: some View {
        let cellFont = Font.system(size: isCompact ? 11 : 15, weight: .semibold).monospacedDigit()

        return Grid(alignment: .trailing, horizontalSpacing: isCompact ? 8 : 14, verticalSpacing: isCompact ? 3 : 6) {
            GridRow {
                Text("#").gridColumnAlignment(.leading)
                Text("").gridColumnAlignment(.leading)
                ForEach(board.columns, id: \.self) { column in
                    Text(column.shortLabel)
                }
            }
            .font(.system(size: isCompact ? 10 : 13, weight: .heavy))
            .foregroundStyle(theme.labelColor.opacity(0.6))

            ForEach(board.rows) { row in
                GridRow {
                    Text("\(row.rank)")
                        .font(cellFont)
                        .foregroundStyle(theme.labelColor.opacity(0.7))
                    Text(name(row.slotIndex))
                        .font(.system(size: isCompact ? 12 : 16, weight: .bold))
                        .foregroundStyle(colour(row.slotIndex))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    ForEach(board.columns, id: \.self) { column in
                        Text("\(row.value(for: column))")
                            .font(cellFont)
                            // Points are the answer the table exists to give.
                            .foregroundStyle(column == .points ? theme.digitColor : theme.labelColor)
                    }
                }
                .contentShape(.rect)
                .allowsHitTesting(isInteractive && onTapRow != nil)
                .onTapGesture { onTapRow?(row.slotIndex) }
            }
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.35), value: board.rows.map(\.slotIndex))
    }

    // MARK: Bracket

    private var bracket: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: isCompact ? 12 : 24) {
                ForEach(0 ..< board.bracketRoundCount, id: \.self) { round in
                    VStack(spacing: isCompact ? 8 : 16) {
                        Text(roundLabel(round))
                            .font(.system(size: isCompact ? 9 : 12, weight: .heavy))
                            .foregroundStyle(theme.labelColor.opacity(0.6))
                        ForEach(board.bracketMatches.filter { $0.round == round }) { match in
                            bracketMatch(match)
                        }
                    }
                }

                if let champion = board.champion {
                    VStack(spacing: 6) {
                        Text("WINNER", comment: "Bracket champion label")
                            .font(.system(size: isCompact ? 9 : 12, weight: .heavy))
                            .foregroundStyle(theme.accentColor)
                        Text(name(champion))
                            .font(.system(size: isCompact ? 14 : 20, weight: .heavy))
                            .foregroundStyle(colour(champion))
                    }
                }
            }
        }
    }

    private func roundLabel(_ round: Int) -> String {
        let remaining = board.bracketRoundCount - round
        switch remaining {
        case 1: return String(localized: "FINAL", comment: "Bracket round")
        case 2: return String(localized: "SEMI", comment: "Bracket round")
        case 3: return String(localized: "QUARTER", comment: "Bracket round")
        default: return String(localized: "ROUND \(round + 1)", comment: "Bracket round")
        }
    }

    private func bracketMatch(_ match: DerivedListBoard.BracketMatch) -> some View {
        VStack(spacing: 1) {
            bracketSlot(match.upperSlot, isWinner: match.winnerSlot == match.upperSlot, match: match)
            bracketSlot(match.lowerSlot, isWinner: match.winnerSlot == match.lowerSlot, match: match)
        }
        .frame(width: isCompact ? 96 : 132)
        .overlay {
            if match.isBye {
                // Saying "bye" beats showing a mysteriously empty half-match.
                Text("BYE", comment: "Bracket bye")
                    .font(.system(size: isCompact ? 8 : 10, weight: .heavy))
                    .foregroundStyle(theme.labelColor.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(2)
            }
        }
    }

    private func bracketSlot(
        _ slot: Int?,
        isWinner: Bool,
        match: DerivedListBoard.BracketMatch
    ) -> some View {
        Text(slot.map { name($0) } ?? "—")
            .font(.system(size: isCompact ? 10 : 13, weight: isWinner ? .heavy : .regular))
            .foregroundStyle(slot.map { isWinner ? colour($0) : theme.labelColor.opacity(0.7) } ?? theme.labelColor.opacity(0.3))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, isCompact ? 4 : 7)
            .background(isWinner ? theme.digitGhostColor : .clear)
            .contentShape(.rect)
            .allowsHitTesting(isInteractive && onTapMatch != nil && slot != nil && !match.isBye)
            .onTapGesture {
                if let slot { onTapMatch?(match.index, slot) }
            }
    }

    // MARK: Score sheet

    private var scoreSheet: some View {
        let cellFont = Font.system(size: isCompact ? 11 : 14, weight: .semibold).monospacedDigit()

        return ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .trailing, horizontalSpacing: isCompact ? 8 : 12, verticalSpacing: isCompact ? 3 : 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(0 ..< board.roundCount, id: \.self) { round in
                        Text("R\(round + 1)")
                            .foregroundStyle(
                                round == board.currentRound
                                    ? theme.accentColor
                                    : theme.labelColor.opacity(0.6)
                            )
                    }
                    Text("Σ", comment: "Score sheet total column")
                }
                .font(.system(size: isCompact ? 10 : 13, weight: .heavy))

                ForEach(board.rows) { row in
                    GridRow {
                        Text(name(row.slotIndex))
                            .font(.system(size: isCompact ? 12 : 15, weight: .bold))
                            .foregroundStyle(colour(row.slotIndex))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        ForEach(0 ..< board.roundCount, id: \.self) { round in
                            Text("\(row.rounds[safe: round] ?? 0)")
                                .font(cellFont)
                                .foregroundStyle(theme.labelColor)
                        }
                        Text("\(row.total)")
                            .font(.system(size: isCompact ? 13 : 17, weight: .black).monospacedDigit())
                            .foregroundStyle(theme.digitColor)
                    }
                    .contentShape(.rect)
                    .allowsHitTesting(isInteractive && onTapRow != nil)
                    .onTapGesture { onTapRow?(row.slotIndex) }
                }

                // Per-column subtotals (§6.5).
                GridRow {
                    Text("ALL", comment: "Score sheet subtotal row")
                        .font(.system(size: isCompact ? 10 : 12, weight: .heavy))
                        .foregroundStyle(theme.labelColor.opacity(0.6))
                    ForEach(0 ..< board.roundCount, id: \.self) { round in
                        Text("\(board.rows.reduce(0) { $0 + ($1.rounds[safe: round] ?? 0) })")
                            .font(cellFont)
                            .foregroundStyle(theme.labelColor.opacity(0.6))
                    }
                    Text("\(board.rows.reduce(0) { $0 + $1.total })")
                        .font(cellFont)
                        .foregroundStyle(theme.labelColor.opacity(0.6))
                }
            }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview("Standings") {
    let rules = BuiltInCatalog.bySlug["standings"]?.rules.listRules ?? ListRules()
    var state = ListEngine.initialState(rules: rules, sideCount: 4)
    state.entries[0] = .init(won: 5, drawn: 1, lost: 0, goalsFor: 14, goalsAgainst: 3)
    state.entries[1] = .init(won: 3, drawn: 2, lost: 1, goalsFor: 9, goalsAgainst: 6)
    state.entries[2] = .init(won: 1, drawn: 2, lost: 3, goalsFor: 5, goalsAgainst: 9)
    state.entries[3] = .init(won: 0, drawn: 1, lost: 5, goalsFor: 2, goalsAgainst: 12)

    return ListBoardView(
        board: ListEngine.derived(state, rules: rules, at: .now),
        sides: [
            BoardSideInfo(displayName: "Wolves", colorHex: "#42A5F5"),
            BoardSideInfo(displayName: "Eagles", colorHex: "#EF5350"),
            BoardSideInfo(displayName: "Foxes", colorHex: "#66BB6A"),
            BoardSideInfo(displayName: "Owls", colorHex: "#FFA726"),
        ],
        theme: BuiltInThemes.theme(id: "light"),
        font: .sevenSegment
    )
    .frame(height: 260)
}
