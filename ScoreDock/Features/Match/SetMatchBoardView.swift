import SwiftUI

/// The set-match board (§6.2).
///
/// **Sets won lead; the current game sits alongside.** That ordering is the spec's, and it is what
/// makes the board readable from a distance — the crowd wants "two sets to one" before it wants
/// "30–15". Finished sets run along the top as a history strip.
///
/// Follows the same §9.2 board rules as the team board: flat, opaque, numerals in the board font,
/// text in the app face, never mirrored in RTL.
struct SetMatchBoardView: View {
    var board: DerivedSetMatchBoard
    var sides: [BoardSideInfo]
    var theme: ThemeSpec
    var font: BoardFont

    var isCompact: Bool = false
    var isInteractive: Bool = true
    var onTap: ((Int) -> Void)?
    var onLongPress: ((Int) -> Void)?

    private static let aspectRatio: CGFloat = 1.9

    var body: some View {
        GeometryReader { geometry in
            let height = max(1, min(geometry.size.height, geometry.size.width / Self.aspectRatio))
            let setsSize = height * (isCompact ? 0.30 : 0.36)
            let pointsSize = height * (isCompact ? 0.20 : 0.24)
            let labelSize = max(9, height * (isCompact ? 0.075 : 0.065))

            VStack(spacing: height * 0.03) {
                header(labelSize: labelSize)
                ForEach(board.sides, id: \.slotIndex) { side in
                    row(side, setsSize: setsSize, pointsSize: pointsSize, labelSize: labelSize)
                }
                if !board.completedSets.isEmpty { setHistory(labelSize: labelSize) }
            }
            .padding(.horizontal, height * 0.05)
            .padding(.vertical, height * 0.04)
            .frame(width: geometry.size.width, height: height)
            .frame(maxHeight: .infinity)
        }
        .background(theme.backgroundColor)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func header(labelSize: CGFloat) -> some View {
        HStack {
            Text(board.stageLabel)
                .font(.system(size: labelSize * 1.1, weight: .heavy))
                .tracking(labelSize * 0.1)
                .foregroundStyle(board.isTiebreak ? theme.accentColor : theme.labelColor)
            Spacer(minLength: 0)
            if board.lastVisitBusted {
                // Darts: the visit was rejected, not lost. Saying so stops the operator re-entering it.
                Text("BUST", comment: "Darts bust marker")
                    .font(.system(size: labelSize, weight: .heavy))
                    .foregroundStyle(theme.accentColor)
            }
            Text(sublabel)
                .font(.system(size: labelSize * 0.9, weight: .semibold))
                .foregroundStyle(theme.labelColor.opacity(0.7))
        }
    }

    private var sublabel: String {
        switch board.notation {
        case .tennis: String(localized: "GAMES", comment: "Board sublabel")
        case .dartsCountdown: String(localized: "LEGS", comment: "Board sublabel")
        case .numeric: String(localized: "POINTS", comment: "Board sublabel")
        }
    }

    private func row(
        _ side: DerivedSetMatchBoard.Side,
        setsSize: CGFloat,
        pointsSize: CGFloat,
        labelSize: CGFloat
    ) -> some View {
        let info = sides.indices.contains(side.slotIndex) ? sides[side.slotIndex] : BoardSideInfo()

        return HStack(spacing: labelSize) {
            // Serve is shown with a filled marker *and* a position, never colour alone (§15).
            Text(side.isServing ? "●" : " ")
                .font(.system(size: labelSize, weight: .black))
                .foregroundStyle(theme.accentColor)
                .frame(width: labelSize * 1.2)

            if let emoji = info.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: labelSize * 1.6))
            }

            Text(info.displayName.uppercased())
                .font(.system(size: labelSize * 1.2, weight: .heavy))
                .foregroundStyle(theme.labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)

            Spacer(minLength: 0)

            // Games or legs within the current set, where the notation has that rung.
            if let intermediate = side.gamesWon ?? side.legsWon {
                LEDNumber(text: "\(intermediate)", theme: theme, font: font, size: pointsSize * 0.8)
                    .foregroundStyle(theme.labelColor)
                    .fixedSize()
            }

            LEDNumber(text: side.pointsText, theme: theme, font: font, size: pointsSize)
                .foregroundStyle(theme.digitColor)
                .fixedSize()

            // The headline: sets won.
            LEDNumber(text: "\(side.setsWon)", theme: theme, font: font, size: setsSize)
                .foregroundStyle(Color(hex: info.colorHex))
                .fixedSize()
        }
        .contentShape(.rect)
        .allowsHitTesting(isInteractive && onTap != nil)
        .onTapGesture { onTap?(side.slotIndex) }
        .onLongPressGesture(minimumDuration: 0.35) { onLongPress?(side.slotIndex) }
        .accessibilityElement()
        .accessibilityLabel(Text("\(info.displayName)", comment: "Accessibility"))
        .accessibilityValue(Text(
            "\(side.setsWon) sets, \(side.pointsText)",
            comment: "Accessibility value"
        ))
    }

    private func setHistory(labelSize: CGFloat) -> some View {
        HStack(spacing: labelSize) {
            Text("SETS", comment: "Set history label")
                .font(.system(size: labelSize * 0.8, weight: .heavy))
                .foregroundStyle(theme.labelColor.opacity(0.6))
            ForEach(Array(board.completedSets.enumerated()), id: \.offset) { _, scores in
                Text(scores.map(String.init).joined(separator: "–"))
                    .font(.system(size: labelSize, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.labelColor)
            }
            Spacer(minLength: 0)
        }
    }
}

#Preview("Tennis") {
    let rules = BuiltInCatalog.bySlug["tennis"]?.rules.setMatchRules ?? SetMatchRules()
    var state = SetMatchEngine.initialState(rules: rules, sideCount: 2)
    state.sides[0].setsWon = 1
    state.sides[0].gamesWon = 4
    state.sides[1].gamesWon = 3
    state.sides[0].points = 3
    state.sides[1].points = 3
    state.completedSets = [[6, 4]]

    return SetMatchBoardView(
        board: SetMatchEngine.derived(state, rules: rules, at: .now),
        sides: [
            BoardSideInfo(displayName: "Alcaraz", colorHex: "#42A5F5"),
            BoardSideInfo(displayName: "Sinner", colorHex: "#EF5350"),
        ],
        theme: BuiltInThemes.theme(id: "grass"),
        font: .sevenSegment
    )
    .frame(height: 220)
}
