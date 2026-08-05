import SwiftUI

/// The rendered scorecard (§13.5).
///
/// Designed in two aspects — 4:5 for chat, 16:9 for stories — because one crop does not serve both,
/// and a scorecard that arrives letterboxed looks careless.
///
/// Rendered in the match's **own** theme, frozen at kickoff, so a shared card looks like the board
/// the game was actually played on (§13.4).
enum ShareCardAspect: String, CaseIterable, Identifiable, Sendable {
    /// 1080 × 1350 — group chats and feeds.
    case portrait
    /// 1920 × 1080 — stories, and anything that will sit beside video.
    case landscape

    var id: String { rawValue }

    var size: CGSize {
        switch self {
        case .portrait: CGSize(width: 1080, height: 1350)
        case .landscape: CGSize(width: 1920, height: 1080)
        }
    }

    var displayName: String {
        switch self {
        case .portrait: String(localized: "Square-ish (4:5)", comment: "Share card aspect")
        case .landscape: String(localized: "Wide (16:9)", comment: "Share card aspect")
        }
    }
}

struct ShareCardView: View {
    var model: MatchExportModel
    var aspect: ShareCardAspect
    var font: BoardFont

    private var theme: ThemeSpec { BuiltInThemes.theme(id: model.themeID) }
    private var size: CGSize { aspect.size }
    private var unit: CGFloat { size.height / 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: unit * 3) {
            header
            Spacer(minLength: 0)
            board
            Spacer(minLength: 0)
            if !model.summary.periodLines.isEmpty { periodStrip }
            footer
        }
        .padding(unit * 6)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .background(theme.backgroundColor)
        // Numerals never mirror (§10.1).
        .environment(\.layoutDirection, .leftToRight)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: unit * 0.8) {
            Text(model.title)
                .font(.system(size: unit * 5, weight: .heavy))
                .foregroundStyle(theme.labelColor)
            HStack(spacing: unit * 1.5) {
                Text(model.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let venue = model.venue, !venue.isEmpty {
                    Text("·")
                    Text(venue)
                }
                if model.status == .live || model.status == .setup {
                    Text("·")
                    // Sharing works mid-match too, with a marker (§13.5).
                    Text("LIVE", comment: "Share card live marker")
                        .foregroundStyle(theme.accentColor)
                }
            }
            .font(.system(size: unit * 2.6, weight: .semibold))
            .foregroundStyle(theme.labelColor.opacity(0.75))
        }
    }

    /// **The real board, not a re-drawing of it (§13.4).**
    ///
    /// This used to lay the result out on its own terms — sides stacked as rows, name left, score
    /// right — so a shared card looked nothing like the board the game was played on, and on the
    /// bespoke boards it could not say what happened at all: a cricket card cannot express
    /// `184-3 in 12.4` as two names and two numbers.
    ///
    /// Rendering the same views the board uses means the card is identical by construction, and a
    /// board that changes cannot drift away from the card that shares it.
    @ViewBuilder
    private var board: some View {
        if let exported = model.board {
            let width = size.width - unit * 12
            let height = min(width / exported.preferredAspect, size.height * 0.52)

            boardView(exported)
                .frame(width: width, height: height)
                .clipShape(.rect(cornerRadius: unit * 1.5))
        } else {
            // The rules could not be decoded, so there is no board to draw. A plain score line is
            // the honest fallback — better than an empty rectangle.
            scoreLineFallback
        }
    }

    @ViewBuilder
    private func boardView(_ exported: ExportedBoard) -> some View {
        let sides = model.sides.map {
            BoardSideInfo(
                displayName: $0.name,
                shortName: $0.shortName,
                colorHex: $0.colorHex,
                emoji: $0.emoji
            )
        }

        switch exported {
        case let .team(board, _):
            ScoreboardView(board: board, sides: sides, theme: theme, font: font, isInteractive: false)
        case let .setMatch(board):
            SetMatchBoardView(board: board, sides: sides, theme: theme, font: font, isInteractive: false)
        case let .list(board):
            ListBoardView(board: board, sides: sides, theme: theme, font: font, isInteractive: false)
        case let .specialised(board):
            switch board {
            case let .chessClock(board):
                ChessClockBoardView(board: board, sides: sides, theme: theme, font: font, isInteractive: false)
            case let .raceTimer(board):
                RaceTimerBoardView(board: board, sides: sides, theme: theme, font: font, isInteractive: false)
            case let .americanFootball(board):
                FootballBoardView(board: board, sides: sides, theme: theme, font: font, isInteractive: false)
            case let .cricket(board):
                CricketBoardView(board: board, sides: sides, theme: theme, font: font, isInteractive: false)
            case let .baseball(board):
                BaseballBoardView(board: board, sides: sides, theme: theme, font: font, isInteractive: false)
            case let .unavailable(board):
                UnavailableBoardView(board: board, theme: theme)
            }
        }
    }

    private var scoreLineFallback: some View {
        VStack(spacing: unit * 2) {
            ForEach(model.sides, id: \.slotIndex) { side in
                HStack(spacing: unit * 2) {
                    Text(side.name.uppercased())
                        .font(.system(size: unit * 5.5, weight: .heavy))
                        .foregroundStyle(Color(hex: side.colorHex))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Spacer(minLength: unit * 2)
                    LEDNumber(text: "\(side.finalScore)", theme: theme, font: font, size: unit * 13)
                        .fixedSize()
                }
            }
        }
    }

    private var periodStrip: some View {
        HStack(spacing: unit * 3) {
            ForEach(model.summary.periodLines) { line in
                VStack(spacing: unit * 0.4) {
                    Text("P\(line.period)")
                        .font(.system(size: unit * 2, weight: .bold))
                        .foregroundStyle(theme.labelColor.opacity(0.6))
                    Text(line.scores.map(String.init).joined(separator: "–"))
                        .font(.system(size: unit * 2.8, weight: .semibold).monospacedDigit())
                        .foregroundStyle(theme.labelColor)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var footer: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: unit * 0.6) {
                ForEach(MatchTextExport.statLines(model.summary, sides: model.sides), id: \.self) { line in
                    Text(line)
                        .font(.system(size: unit * 2.2, weight: .medium))
                        .foregroundStyle(theme.labelColor.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            if model.options.includeWatermark {
                // Small, tasteful, and free to remove in Settings (§13.5).
                HStack(spacing: unit * 0.8) {
                    Image(systemName: "sportscourt.fill")
                    Text("ScoreDock", comment: "Watermark")
                }
                .font(.system(size: unit * 2.2, weight: .semibold))
                .foregroundStyle(theme.labelColor.opacity(0.5))
            }
        }
    }
}
