import SwiftUI

/// The chess clock board (§6.3).
///
/// Two faces, split across the screen, each one its own button — because that is what a chess clock
/// *is*. You press your own side to end your move, so the touch target for a player is the half in
/// front of them.
///
/// The far half is rotated 180°, which is the one piece of layout that makes this usable in the way
/// the physical object is: two people sitting opposite each other, both reading their own clock the
/// right way up. This is also why the board deliberately ignores the app's RTL mirroring (§9.2) —
/// the halves are physical positions, not a reading order.
struct ChessClockBoardView: View {
    var board: DerivedChessClockBoard
    var sides: [BoardSideInfo]
    var theme: ThemeSpec
    var font: BoardFont

    var isCompact: Bool = false
    var isInteractive: Bool = true
    var onPress: ((Int) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width > geometry.size.height
            let halfHeight = isWide ? geometry.size.height : geometry.size.height / 2

            // Side by side when there is width to spare (a landscape board, or an external
            // display); stacked when there is not.
            let layout = isWide
                ? AnyLayout(HStackLayout(spacing: 2))
                : AnyLayout(VStackLayout(spacing: 2))

            // Stacked, the far player's face goes on top and is inverted, so two people sitting
            // opposite each other each read their own clock the right way up. Side by side they are
            // both looking at it from the same edge, so it stays in slot order and upright.
            let ordered = isWide ? board.sides : board.sides.reversed()

            layout {
                ForEach(ordered, id: \.slotIndex) { side in
                    face(side, height: halfHeight, width: isWide ? geometry.size.width / 2 : geometry.size.width)
                        .rotationEffect(.degrees(!isWide && side.slotIndex == 1 ? 180 : 0))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(theme.backgroundColor)
        .environment(\.layoutDirection, .leftToRight)
    }

    private func face(_ side: DerivedChessClockBoard.Side, height: CGFloat, width: CGFloat) -> some View {
        let info = sides.indices.contains(side.slotIndex) ? sides[side.slotIndex] : BoardSideInfo()

        // `MM:SS` is five glyphs, and a seven-segment glyph is about 0.62 em wide — so a face needs
        // roughly 3.2 × the point size to hold one. Sizing from height alone is what let two clocks
        // run into each other as `05:0005:00`.
        let clockSize = min(height * (isCompact ? 0.42 : 0.46), width / 3.8)
        let labelSize = max(9, clockSize * 0.17)
        let isDimmed = board.hasStarted && !side.isActive && !side.hasFlagged

        return ZStack {
            // The active side is filled, not just tinted: from across a table the thing you need to
            // see is *whose clock is running*, and a change of area reads faster than a change of
            // hue — and does not depend on colour alone (§15).
            (side.isActive ? Color(hex: info.colorHex).opacity(0.22) : Color.clear)

            VStack(spacing: labelSize * 0.4) {
                HStack(spacing: labelSize * 0.5) {
                    if let emoji = info.emoji, !emoji.isEmpty {
                        Text(emoji).font(.system(size: labelSize * 1.4))
                    }
                    Text(info.displayName.uppercased())
                        .font(.system(size: labelSize, weight: .heavy))
                        .tracking(labelSize * 0.08)
                        .foregroundStyle(theme.labelColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.4)

                    if side.isActive {
                        // A shape as well as the fill, so "on the clock" survives greyscale.
                        Image(systemName: "triangle.fill")
                            .font(.system(size: labelSize * 0.7))
                            .foregroundStyle(theme.accentColor)
                            .accessibilityHidden(true)
                    }
                }

                // No `.fixedSize()`: `LEDNumber` already scales down rather than truncate, and
                // pinning it would defeat that on a narrow face.
                LEDNumber(text: side.clock.formatted, theme: theme, font: font, size: clockSize)
                    .foregroundStyle(side.hasFlagged ? theme.accentColor : theme.digitColor)

                Text(statusLine(side))
                    .font(.system(size: labelSize * 0.85, weight: .semibold))
                    .foregroundStyle(theme.labelColor.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .opacity(isDimmed ? 0.45 : 1)
            .padding(labelSize)
        }
        .frame(width: width, height: height)
        .contentShape(.rect)
        .allowsHitTesting(isInteractive && onPress != nil)
        .onTapGesture { onPress?(side.slotIndex) }
        .accessibilityElement()
        .accessibilityLabel(Text("\(info.displayName)", comment: "Accessibility"))
        .accessibilityValue(Text(
            "\(side.clock.formatted), \(statusLine(side))",
            comment: "Accessibility value"
        ))
        .accessibilityAddTraits(isInteractive && onPress != nil ? .isButton : [])
        .accessibilityHint(Text("Ends this player's move", comment: "Accessibility hint"))
    }

    private func statusLine(_ side: DerivedChessClockBoard.Side) -> String {
        if side.hasFlagged {
            return String(localized: "FLAG", comment: "Chess clock — out of time")
        }
        if !board.hasStarted {
            return String(localized: "TAP TO START · \(board.incrementLabel)", comment: "Chess clock hint")
        }
        // A static uppercase label with the number after it, matching SETS / GAMES / LEGS on the
        // other boards. This is also the one form that needs no pluralisation: `^[…](inflect:)`
        // resolves only against a localisation catalog entry, and these in-source keys have none,
        // so it rendered as the literal "[1 move](inflect: true)".
        return String(
            localized: "MOVES \(side.moves) · \(board.incrementLabel)",
            comment: "Chess clock status — moves played, then the time control"
        )
    }
}

#Preview("Blitz, mid-game") {
    let rules = BuiltInCatalog.bySlug["chess-clock"]?.rules.specialisedRules?.chessClock ?? ChessClockRules()
    var state = ChessClockEngine.initialState(rules: rules, sideCount: 2)
    ChessClockEngine.apply(.specialised(.pressClock(slot: 0)), to: &state, rules: rules, at: .now)

    return ChessClockBoardView(
        board: ChessClockEngine.derived(state, rules: rules, isFinished: false, at: .now),
        sides: [
            BoardSideInfo(displayName: "White", colorHex: "#ECEFF1"),
            BoardSideInfo(displayName: "Black", colorHex: "#78909C"),
        ],
        theme: BuiltInThemes.theme(id: "black"),
        font: .sevenSegment
    )
}
