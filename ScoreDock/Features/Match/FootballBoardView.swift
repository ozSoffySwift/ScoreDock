import SwiftUI

/// The American football board (§6.3).
///
/// Two scores lead, with the game clock between them — the same three-panel arrangement as the team
/// scoreboard, because that is what a football scoreboard is. The strip beneath carries the things
/// only this sport has: down and distance, the ball spot, and the play clock.
struct FootballBoardView: View {
    var board: DerivedFootballBoard
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
            let scoreSize = height * (isCompact ? 0.30 : 0.34)
            let clockSize = height * (isCompact ? 0.20 : 0.22)
            let labelSize = max(9, height * 0.065)

            VStack(spacing: height * 0.03) {
                HStack(alignment: .center, spacing: labelSize) {
                    scorePanel(slot: 0, scoreSize: scoreSize, labelSize: labelSize)
                    clockPanel(clockSize: clockSize, labelSize: labelSize)
                    scorePanel(slot: 1, scoreSize: scoreSize, labelSize: labelSize)
                }

                situationStrip(labelSize: labelSize, clockSize: clockSize)
            }
            .padding(.horizontal, height * 0.05)
            .padding(.vertical, height * 0.04)
            .frame(width: geometry.size.width, height: height)
            .frame(maxHeight: .infinity)
        }
        .background(theme.backgroundColor)
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: Panels

    private func scorePanel(slot: Int, scoreSize: CGFloat, labelSize: CGFloat) -> some View {
        let side = board.sides.first { $0.slotIndex == slot }
        let info = sides.indices.contains(slot) ? sides[slot] : BoardSideInfo()

        return VStack(spacing: labelSize * 0.25) {
            HStack(spacing: labelSize * 0.3) {
                // Possession is a shape, not a colour (§15) — and on the side that has the ball.
                if side?.hasPossession == true {
                    Image(systemName: "football.fill")
                        .font(.system(size: labelSize * 0.9))
                        .foregroundStyle(theme.accentColor)
                        .accessibilityHidden(true)
                }
                if let emoji = info.emoji, !emoji.isEmpty {
                    Text(emoji).font(.system(size: labelSize * 1.4))
                }
                Text(info.shortName.uppercased())
                    .font(.system(size: labelSize, weight: .heavy))
                    .foregroundStyle(theme.labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
            }

            LEDNumber(text: "\(side?.score ?? 0)", theme: theme, font: font, size: scoreSize)
                .foregroundStyle(Color(hex: info.colorHex))

            // Timeouts left as pips, which is how a real board shows them.
            HStack(spacing: labelSize * 0.2) {
                ForEach(0 ..< max(0, side?.timeoutsRemaining ?? 0), id: \.self) { _ in
                    Circle()
                        .fill(theme.labelColor.opacity(0.8))
                        .frame(width: labelSize * 0.35, height: labelSize * 0.35)
                }
            }
            .frame(height: labelSize * 0.4)
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .allowsHitTesting(isInteractive && onTap != nil)
        .onTapGesture { onTap?(slot) }
        .onLongPressGesture(minimumDuration: 0.35) { onLongPress?(slot) }
        .accessibilityElement()
        .accessibilityLabel(Text("\(info.displayName)", comment: "Accessibility"))
        .accessibilityValue(Text(
            "\(side?.score ?? 0), \(side?.timeoutsRemaining ?? 0) timeouts left",
            comment: "Accessibility value"
        ))
    }

    private func clockPanel(clockSize: CGFloat, labelSize: CGFloat) -> some View {
        VStack(spacing: labelSize * 0.2) {
            Text(board.quarterLabel)
                .font(.system(size: labelSize * 1.1, weight: .heavy))
                .tracking(labelSize * 0.1)
                .foregroundStyle(theme.labelColor)

            LEDNumber(text: board.gameClock.formatted, theme: theme, font: font, size: clockSize)
                .foregroundStyle(board.gameClock.hasExpired ? theme.accentColor : theme.digitColor)
        }
        .frame(maxWidth: .infinity)
    }

    private func situationStrip(labelSize: CGFloat, clockSize: CGFloat) -> some View {
        HStack(spacing: labelSize) {
            labelled(String(localized: "DOWN", comment: "Football board label"), board.downAndDistance, labelSize: labelSize)

            Spacer(minLength: 0)

            labelled(
                String(localized: "BALL ON", comment: "Football board label"),
                "\(board.ballOnNumber)",
                labelSize: labelSize
            )

            Spacer(minLength: 0)

            VStack(spacing: 0) {
                Text("PLAY CLOCK", comment: "Football board label")
                    .font(.system(size: labelSize * 0.7, weight: .heavy))
                    .tracking(labelSize * 0.06)
                    .foregroundStyle(theme.labelColor.opacity(0.7))
                LEDNumber(text: board.playClock.formatted, theme: theme, font: font, size: clockSize * 0.8)
                    .foregroundStyle(board.playClock.hasExpired ? theme.accentColor : theme.digitColor)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func labelled(_ label: String, _ value: String, labelSize: CGFloat) -> some View {
        VStack(spacing: 0) {
            Text(label)
                .font(.system(size: labelSize * 0.7, weight: .heavy))
                .tracking(labelSize * 0.06)
                .foregroundStyle(theme.labelColor.opacity(0.7))
            Text(value)
                .font(.system(size: labelSize * 1.35, weight: .heavy).monospacedDigit())
                .foregroundStyle(theme.labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
    }
}

#Preview("Third and seven") {
    let rules = BuiltInCatalog.bySlug["american-football"]?.rules.specialisedRules?.americanFootball
        ?? AmericanFootballRules()
    var state = AmericanFootballEngine.initialState(rules: rules, sideCount: 2)
    state.sides[0].score = 21
    state.sides[1].score = 17
    state.sides[0].timeoutsUsed = 1
    state.quarter = 3
    state.possessionSlot = 0
    state.down = 3
    state.yardsToGo = 7
    state.ballOn = 62

    return FootballBoardView(
        board: AmericanFootballEngine.derived(state, rules: rules, isFinished: false, at: .now),
        sides: [
            BoardSideInfo(displayName: "Hawks", shortName: "HAWK", colorHex: "#42A5F5"),
            BoardSideInfo(displayName: "Bears", shortName: "BEAR", colorHex: "#EF5350"),
        ],
        theme: BuiltInThemes.theme(id: "forest"),
        font: .sevenSegment
    )
    .frame(height: 220)
}
