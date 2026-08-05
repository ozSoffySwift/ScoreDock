import SwiftUI

/// The race timer board (§6.3).
///
/// The race clock leads, because that is the number everyone at the finish line is looking at, and
/// the field sits beneath it **in running order** rather than in entry order — a race board that
/// listed racers by bib number would make the operator do the sorting.
///
/// Each row is the lap button for that racer: tap to record a crossing, long-press to finish them.
/// That keeps the operator's eyes on the course, which is the same principle as §4.2's preview.
struct RaceTimerBoardView: View {
    var board: DerivedRaceTimerBoard
    var sides: [BoardSideInfo]
    var theme: ThemeSpec
    var font: BoardFont

    var isCompact: Bool = false
    var isInteractive: Bool = true
    var onLap: ((Int) -> Void)?
    var onFinish: ((Int) -> Void)?

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let clockSize = min(height * (isCompact ? 0.22 : 0.26), geometry.size.width / 5.2)
            let labelSize = max(9, clockSize * 0.2)

            VStack(spacing: labelSize * 0.5) {
                header(clockSize: clockSize, labelSize: labelSize)

                VStack(spacing: labelSize * 0.35) {
                    ForEach(displayRows, id: \.slotIndex) { racer in
                        row(racer, labelSize: labelSize)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, labelSize)
            .padding(.vertical, labelSize * 0.8)
            .frame(width: geometry.size.width, height: height, alignment: .top)
        }
        .background(theme.backgroundColor)
        .environment(\.layoutDirection, .leftToRight)
    }

    /// **If you can tap it, it does not move.**
    ///
    /// Running order is right for a board people are watching, and wrong for one people are
    /// pressing: recording a lap promotes that racer to the top, so the next tap in the same place
    /// lands on somebody else. With a field crossing the line seconds apart that is a mis-tap
    /// waiting to happen — found by running a race, not by reading the code.
    ///
    /// So the interactive surface keeps the fixed entry order and shows the placing as a number,
    /// and the display surface sorts.
    private var displayRows: [DerivedRaceTimerBoard.Racer] {
        guard isInteractive, onLap != nil else { return board.rows }
        return board.rows.sorted { $0.slotIndex < $1.slotIndex }
    }

    private func header(clockSize: CGFloat, labelSize: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: labelSize) {
            Text("RACE", comment: "Race timer label")
                .font(.system(size: labelSize, weight: .heavy))
                .tracking(labelSize * 0.12)
                .foregroundStyle(theme.labelColor.opacity(0.7))

            Spacer(minLength: 0)

            if let laps = board.lapCount {
                Text("\(laps) LAPS", comment: "Race timer label")
                    .font(.system(size: labelSize * 0.9, weight: .semibold))
                    .foregroundStyle(theme.labelColor.opacity(0.7))
            }

            LEDNumber(text: board.raceClock.formatted, theme: theme, font: font, size: clockSize)
                .foregroundStyle(theme.digitColor)
        }
    }

    private func row(_ racer: DerivedRaceTimerBoard.Racer, labelSize: CGFloat) -> some View {
        let info = sides.indices.contains(racer.slotIndex) ? sides[racer.slotIndex] : BoardSideInfo()

        return HStack(spacing: labelSize * 0.6) {
            // A dash rather than a number until the racer has crossed something — the engine
            // deliberately withholds a placing at the start line.
            Text(racer.position.map(String.init) ?? "–")
                .font(.system(size: labelSize * 1.2, weight: .heavy).monospacedDigit())
                .foregroundStyle(racer.position == 1 ? theme.accentColor : theme.labelColor.opacity(0.8))
                .frame(width: labelSize * 1.6, alignment: .trailing)

            if let emoji = info.emoji, !emoji.isEmpty {
                Text(emoji).font(.system(size: labelSize * 1.3))
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(info.displayName.uppercased())
                    .font(.system(size: labelSize, weight: .heavy))
                    .foregroundStyle(theme.labelColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                Text(detailLine(racer))
                    .font(.system(size: labelSize * 0.75, weight: .medium).monospacedDigit())
                    .foregroundStyle(theme.labelColor.opacity(0.65))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }

            Spacer(minLength: 0)

            // "FIN" as well as the frozen time, so a finished racer is not signalled by colour
            // alone (§15).
            if racer.hasFinished {
                Text("FIN", comment: "Race timer — finished")
                    .font(.system(size: labelSize * 0.8, weight: .heavy))
                    .foregroundStyle(theme.accentColor)
            }

            LEDNumber(text: racer.clock.formatted, theme: theme, font: font, size: labelSize * 1.9)
                .foregroundStyle(racer.hasFinished ? theme.labelColor : theme.digitColor)
        }
        .padding(.vertical, labelSize * 0.25)
        .padding(.horizontal, labelSize * 0.4)
        .background(
            racer.position == 1 ? Color(hex: info.colorHex).opacity(0.16) : .clear,
            in: .rect(cornerRadius: labelSize * 0.5)
        )
        .contentShape(.rect)
        .allowsHitTesting(isInteractive && onLap != nil && !racer.hasFinished)
        .onTapGesture { onLap?(racer.slotIndex) }
        .onLongPressGesture(minimumDuration: 0.4) { onFinish?(racer.slotIndex) }
        .accessibilityElement()
        .accessibilityLabel(Text("\(info.displayName)", comment: "Accessibility"))
        .accessibilityValue(Text(
            "\(racer.position.map(String.init) ?? "unplaced"), \(detailLine(racer)), \(racer.clock.formatted)",
            comment: "Accessibility value"
        ))
        .accessibilityHint(Text("Records a lap. Long press to finish.", comment: "Accessibility hint"))
    }

    private func detailLine(_ racer: DerivedRaceTimerBoard.Racer) -> String {
        var parts = [String(localized: "LAPS \(racer.lapsCompleted)", comment: "Race timer detail")]
        if let last = racer.lastLap {
            parts.append(String(
                localized: "LAST \(ClockDisplay.format(last, showsTenths: true))",
                comment: "Race timer detail"
            ))
        }
        if let best = racer.bestLap, racer.lapsCompleted > 1 {
            parts.append(String(
                localized: "BEST \(ClockDisplay.format(best, showsTenths: true))",
                comment: "Race timer detail"
            ))
        }
        return parts.joined(separator: " · ")
    }
}

#Preview("Mid-race") {
    let rules = BuiltInCatalog.bySlug["race-timer"]?.rules.specialisedRules?.raceTimer ?? RaceTimerRules()
    var state = RaceTimerEngine.initialState(rules: rules, sideCount: 4)
    let start = Date.now.addingTimeInterval(-200)
    RaceTimerEngine.apply(.toggleClock, to: &state, rules: rules, at: start)
    RaceTimerEngine.apply(.specialised(.recordLap(slot: 0)), to: &state, rules: rules, at: start.addingTimeInterval(61))
    RaceTimerEngine.apply(.specialised(.recordLap(slot: 1)), to: &state, rules: rules, at: start.addingTimeInterval(64))
    RaceTimerEngine.apply(.specialised(.recordLap(slot: 0)), to: &state, rules: rules, at: start.addingTimeInterval(119))

    return RaceTimerBoardView(
        board: RaceTimerEngine.derived(state, rules: rules, isFinished: false, at: .now),
        sides: [
            BoardSideInfo(displayName: "Ayala", colorHex: "#42A5F5"),
            BoardSideInfo(displayName: "Brandt", colorHex: "#EF5350"),
            BoardSideInfo(displayName: "Cortez", colorHex: "#66BB6A"),
            BoardSideInfo(displayName: "Dias", colorHex: "#FFA726"),
        ],
        theme: BuiltInThemes.theme(id: "amber"),
        font: .sevenSegment
    )
}
