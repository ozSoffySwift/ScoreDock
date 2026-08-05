import SwiftUI

/// A tappable element on the board (§4.2).
enum BoardElement: Hashable, Sendable {
    case score(slot: Int)
    case clock
    case period
    case possession
    case shotClock
    case fouls(slot: Int)
    case timeouts(slot: Int)
}

/// Identity for one side, snapshotted from `MatchSide`.
struct BoardSideInfo: Hashable, Sendable {
    var displayName: String
    var shortName: String
    var colorHex: String
    var emoji: String?

    init(displayName: String = "", shortName: String = "", colorHex: String = "#1E88E5", emoji: String? = nil) {
        self.displayName = displayName
        self.shortName = shortName
        self.colorHex = colorHex
        self.emoji = emoji
    }
}

/// The scoreboard itself — used full-screen as the board (§4.3) *and* scaled down as the control
/// panel's interactive preview (§4.2). One view, so what the operator taps is literally the thing
/// the crowd sees.
///
/// Board rules from §9.2, which differ from the rest of the app on purpose:
/// - **No Liquid Glass, no translucency, no vibrancy.** Legibility at 20 metres beats aesthetics.
/// - **Numeric elements use the board font; text elements never do.** DSEG7 has no Hebrew and
///   renders letters as segment approximations.
/// - **The board does not mirror in RTL.** Home stays left, in every language — a scoreboard is a
///   venue convention, not a reading surface (§10.1).
/// - Type scales from measured space rather than guessed point sizes.
struct ScoreboardView: View {
    var board: DerivedBoard
    var sides: [BoardSideInfo]
    var theme: ThemeSpec
    var font: BoardFont

    /// Shrinks secondary rows for the control panel preview.
    var isCompact: Bool = false
    /// Board taps stay live in landscape so a phone flat on the scorer's table is fully operable
    /// (§4.3). A lock toggle sets this false.
    var isInteractive: Bool = true

    var onTap: ((BoardElement) -> Void)?
    var onLongPress: ((BoardElement) -> Void)?

    /// A scoreboard is a wide, short instrument. Sizing purely from available height blows the
    /// digits up to 350 pt in a portrait container and overflows the screen, so the layout is
    /// letterboxed to a board-shaped area and centred in whatever space it is given. That also
    /// means the full-screen board still looks right if a forced rotation is refused.
    private static let boardAspectRatio: CGFloat = 1.9

    var body: some View {
        GeometryReader { geometry in
            let height = max(1, min(geometry.size.height, geometry.size.width / Self.boardAspectRatio))
            let scoreSize = height * (isCompact ? 0.34 : 0.40)
            let clockSize = height * (isCompact ? 0.20 : 0.24)
            let labelSize = max(9, height * (isCompact ? 0.075 : 0.065))

            VStack(spacing: height * 0.03) {
                header(labelSize: labelSize)
                scoreRow(scoreSize: scoreSize, clockSize: clockSize, labelSize: labelSize)
                if showsFooter {
                    footer(labelSize: labelSize, height: height)
                }
            }
            .padding(.horizontal, height * 0.05)
            .padding(.vertical, height * 0.04)
            .frame(width: geometry.size.width, height: height)
            .frame(maxHeight: .infinity)
        }
        .background(theme.backgroundColor)
        // Digits are always left-to-right, in every language (§10.1).
        .environment(\.layoutDirection, .leftToRight)
    }

    private var showsFooter: Bool {
        board.shotClock != nil
            || board.possessionSlot != nil
            || board.sides.contains { $0.fouls != nil || $0.timeoutsRemaining != nil }
    }

    // MARK: Header — side names and period

    private func header(labelSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 8) {
            sideName(0, size: labelSize)
            Spacer(minLength: 0)
            periodBadge(size: labelSize)
            Spacer(minLength: 0)
            sideName(1, size: labelSize)
        }
    }

    private func sideName(_ slot: Int, size: CGFloat) -> some View {
        let info = sides.indices.contains(slot) ? sides[slot] : BoardSideInfo()
        return HStack(spacing: 4) {
            if let emoji = info.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: size))
            }
            Text(info.displayName.uppercased())
                // The app's text face, never the board font.
                .font(.system(size: size, weight: .heavy))
                .tracking(size * 0.08)
                .foregroundStyle(theme.labelColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity, alignment: slot == 0 ? .leading : .trailing)
        .accessibilityHidden(true)
    }

    private func periodBadge(size: CGFloat) -> some View {
        Text(board.isBreak ? String(localized: "BREAK", comment: "Board break label") : board.periodLabel)
            .font(.system(size: size * 1.1, weight: .heavy))
            .tracking(size * 0.1)
            .foregroundStyle(board.isBreak ? theme.accentColor : theme.labelColor)
            .lineLimit(1)
            .contentShape(.rect)
            .element(.period, isInteractive: isInteractive, onTap: onTap, onLongPress: onLongPress)
            .accessibilityLabel(Text("Period \(board.periodLabel)", comment: "Accessibility"))
    }

    // MARK: Scores and clock

    private func scoreRow(scoreSize: CGFloat, clockSize: CGFloat, labelSize: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 0) {
            scoreCell(slot: 0, size: scoreSize)
            VStack(spacing: 2) {
                clockCell(size: clockSize)
                if let shotClock = board.shotClock, !isCompact {
                    shotClockCell(shotClock, size: clockSize * 0.55)
                }
            }
            .frame(maxWidth: .infinity)
            scoreCell(slot: 1, size: scoreSize)
        }
        .frame(maxHeight: .infinity)
    }

    private func scoreCell(slot: Int, size: CGFloat) -> some View {
        let value = board.sides.first { $0.slotIndex == slot }?.score ?? 0
        let tint = sides.indices.contains(slot) ? Color(hex: sides[slot].colorHex) : theme.digitColor
        return VStack(spacing: 0) {
            LEDNumber(text: "\(value)", theme: theme, font: font, size: size)
                // Per-side colour comes from the team record, tinting the digits themselves.
                .foregroundStyle(tint)
            if board.possessionSlot == slot {
                possessionIndicator(size: size * 0.16)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .element(.score(slot: slot), isInteractive: isInteractive, onTap: onTap, onLongPress: onLongPress)
        .accessibilityElement()
        .accessibilityLabel(Text("\(sideName(slot)) score", comment: "Accessibility"))
        .accessibilityValue(Text("\(value)"))
        .accessibilityHint(Text("Double tap to add a point", comment: "Accessibility"))
    }

    private func clockCell(size: CGFloat) -> some View {
        LEDNumber(
            text: board.primaryClock.formatted,
            theme: theme,
            font: font,
            size: size
        )
        .foregroundStyle(board.primaryClock.hasExpired ? theme.accentColor : theme.digitColor)
        // A stopped clock is visibly stopped, and not by colour alone.
        .opacity(board.primaryClock.isRunning ? 1 : 0.75)
        .contentShape(.rect)
        .element(.clock, isInteractive: isInteractive, onTap: onTap, onLongPress: onLongPress)
        .accessibilityElement()
        .accessibilityLabel(Text("Match clock", comment: "Accessibility"))
        .accessibilityValue(Text(board.primaryClock.formatted))
        .accessibilityHint(Text("Double tap to start or stop", comment: "Accessibility"))
    }

    private func shotClockCell(_ shotClock: ClockDisplay, size: CGFloat) -> some View {
        LEDNumber(
            text: shotClock.formatted,
            theme: theme,
            font: font,
            size: size
        )
        .foregroundStyle(shotClock.hasExpired ? theme.accentColor : theme.digitColor)
        .opacity(shotClock.isRunning ? 1 : 0.75)
        .contentShape(.rect)
        .element(.shotClock, isInteractive: isInteractive, onTap: onTap, onLongPress: onLongPress)
        .accessibilityElement()
        .accessibilityLabel(Text("Shot clock", comment: "Accessibility"))
        .accessibilityValue(Text(shotClock.formatted))
    }

    private func possessionIndicator(size: CGFloat) -> some View {
        // Possession carries an arrow *and* a label, so colour is never the only signal (§15).
        HStack(spacing: 3) {
            Image(systemName: "arrowtriangle.left.fill")
            Text("POSS", comment: "Possession label")
                .font(.system(size: size * 0.8, weight: .heavy))
        }
        .font(.system(size: size, weight: .bold))
        .foregroundStyle(theme.accentColor)
    }

    // MARK: Footer — fouls and timeouts

    private func footer(labelSize: CGFloat, height: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 12) {
            sideFooter(slot: 0, labelSize: labelSize)
            Spacer(minLength: 0)
            if let shotClock = board.shotClock, isCompact {
                LEDNumber(text: shotClock.formatted, theme: theme, font: font, size: labelSize * 2)
                    .foregroundStyle(shotClock.hasExpired ? theme.accentColor : theme.digitColor)
                    .contentShape(.rect)
                    .element(.shotClock, isInteractive: isInteractive, onTap: onTap, onLongPress: onLongPress)
            }
            Spacer(minLength: 0)
            sideFooter(slot: 1, labelSize: labelSize)
        }
        .frame(height: height * (isCompact ? 0.14 : 0.12))
    }

    private func sideFooter(slot: Int, labelSize: CGFloat) -> some View {
        let side = board.sides.first { $0.slotIndex == slot }
        return HStack(spacing: 10) {
            if let fouls = side?.fouls {
                HStack(spacing: 3) {
                    if side?.isInBonus == true {
                        // An icon as well as a colour change (§15).
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: labelSize * 0.85))
                            .foregroundStyle(theme.accentColor)
                    }
                    Text("F", comment: "Foul abbreviation")
                        .font(.system(size: labelSize * 0.9, weight: .heavy))
                        .foregroundStyle(theme.labelColor)
                    LEDNumber(text: "\(fouls)", theme: theme, font: font, size: labelSize * 1.3)
                        .foregroundStyle(side?.isInBonus == true ? theme.accentColor : theme.digitColor)
                        .fixedSize()
                }
                .contentShape(.rect)
                .element(.fouls(slot: slot), isInteractive: isInteractive, onTap: onTap, onLongPress: onLongPress)
                .accessibilityElement()
                .accessibilityLabel(Text("\(sideName(slot)) fouls", comment: "Accessibility"))
                .accessibilityValue(Text("\(fouls)"))
            }

            if let remaining = side?.timeoutsRemaining {
                timeoutDots(remaining: remaining, size: labelSize * 0.55)
                    .contentShape(.rect)
                    .element(.timeouts(slot: slot), isInteractive: isInteractive, onTap: onTap, onLongPress: onLongPress)
                    .accessibilityElement()
                    .accessibilityLabel(Text("\(sideName(slot)) timeouts remaining", comment: "Accessibility"))
                    .accessibilityValue(Text("\(remaining)"))
            }
        }
        .frame(maxWidth: .infinity, alignment: slot == 0 ? .leading : .trailing)
    }

    /// Timeouts render as dot trackers (§6.1).
    private func timeoutDots(remaining: Int, size: CGFloat) -> some View {
        let total = max(remaining, totalTimeouts)
        return HStack(spacing: size * 0.5) {
            ForEach(0 ..< max(0, total), id: \.self) { index in
                Circle()
                    .fill(index < remaining ? theme.digitColor : theme.digitGhostColor)
                    .frame(width: size, height: size)
            }
        }
    }

    private var totalTimeouts: Int {
        board.sides.compactMap(\.timeoutsRemaining).max() ?? 0
    }

    private func sideName(_ slot: Int) -> String {
        sides.indices.contains(slot) ? sides[slot].displayName : ""
    }
}

// MARK: - Element interaction

private extension View {
    /// Wires the §4.2 tap / long-press pair onto one board element.
    ///
    /// Kept as a modifier so every element gets identical behaviour, and so a locked board (§12)
    /// disables all of them in one place.
    func element(
        _ element: BoardElement,
        isInteractive: Bool,
        onTap: ((BoardElement) -> Void)?,
        onLongPress: ((BoardElement) -> Void)?
    ) -> some View {
        allowsHitTesting(isInteractive && (onTap != nil || onLongPress != nil))
            .onTapGesture { onTap?(element) }
            .onLongPressGesture(minimumDuration: 0.35) { onLongPress?(element) }
    }
}

#Preview("Board") {
    let rules = BuiltInCatalog.bySlug["basketball"]?.rules.teamRules ?? TeamRules()
    var state = TeamEngine.initialState(rules: rules, sideCount: 2)
    state.sides[0].score = 102
    state.sides[1].score = 98
    state.sides[0].fouls = 5
    state.sides[1].fouls = 2
    state.sides[1].timeoutsUsed = 2
    state.possessionSlot = 0
    state.period = 3

    return ScoreboardView(
        board: TeamEngine.derived(state, rules: rules, at: .now),
        sides: [
            BoardSideInfo(displayName: "Wolves", shortName: "WOL", colorHex: "#42A5F5", emoji: "🐺"),
            BoardSideInfo(displayName: "Eagles", shortName: "EAG", colorHex: "#EF5350", emoji: "🦅"),
        ],
        theme: BuiltInThemes.theme(id: "dark"),
        font: .sevenSegment
    )
    .frame(height: 240)
}
