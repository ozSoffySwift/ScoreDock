import PDFKit
import SwiftUI
import UIKit

/// Renders the visual share formats (§13.5).
@MainActor
enum MatchRenderer {
    /// PNG of the share card.
    ///
    /// `ShareCardView` is laid out at final pixel dimensions (1080 × 1350 or 1920 × 1080), so the
    /// renderer scale stays at 1 — designing small and multiplying by 3 gives the same result while
    /// making every font size in the card a puzzle to read.
    static func image(_ model: MatchExportModel, aspect: ShareCardAspect, font: BoardFont) -> Data? {
        let renderer = ImageRenderer(content: ShareCardView(model: model, aspect: aspect, font: font))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(aspect.size)
        return renderer.uiImage?.pngData()
    }

    // MARK: PDF

    private static let pageSize = CGSize(width: 595.2, height: 841.8)  // A4
    private static let margin: CGFloat = 40

    /// The full formatted report, paginated (§13.5).
    ///
    /// Pagination is not optional: a cricket innings logs per ball and will run to several pages,
    /// and a report that silently truncates is worse than no report.
    static func pdf(_ model: MatchExportModel, font: BoardFont) -> Data? {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: model.title,
            kCGPDFContextCreator as String: "ScoreDock",
        ]

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let card = image(model, aspect: .landscape, font: font).flatMap(UIImage.init(data:))

        return renderer.pdfData { context in
            context.beginPage()
            var cursor = margin

            if let card {
                let width = pageSize.width - margin * 2
                let height = width * (card.size.height / card.size.width)
                card.draw(in: CGRect(x: margin, y: cursor, width: width, height: height))
                cursor += height + 24
            }

            cursor = draw(heading: model.title, at: cursor)
            cursor = draw(body: subtitle(model), at: cursor)

            if !model.summary.periodLines.isEmpty {
                cursor += 12
                cursor = draw(heading: String(localized: "By period", comment: "PDF section"), at: cursor, size: 13)
                for line in model.summary.periodLines {
                    cursor = draw(
                        body: "P\(line.period)   \(line.scores.map(String.init).joined(separator: " – "))",
                        at: cursor
                    )
                }
            }

            let stats = MatchTextExport.statLines(model.summary, sides: model.sides)
            if !stats.isEmpty {
                cursor += 12
                cursor = draw(heading: String(localized: "Summary", comment: "PDF section"), at: cursor, size: 13)
                for line in stats { cursor = draw(body: line, at: cursor) }
            }

            if let notes = model.notes, !notes.isEmpty {
                cursor += 12
                cursor = draw(heading: String(localized: "Notes", comment: "PDF section"), at: cursor, size: 13)
                cursor = draw(body: notes, at: cursor, width: pageSize.width - margin * 2)
            }

            guard model.options.includeTimeline else { return }

            let entries = model.timeline.filter { !$0.isUndone }
            guard !entries.isEmpty else { return }

            context.beginPage()
            cursor = margin
            cursor = draw(heading: String(localized: "Play by play", comment: "PDF section"), at: cursor, size: 13)

            for entry in entries {
                if cursor > pageSize.height - margin - 20 {
                    context.beginPage()
                    cursor = margin
                }
                cursor = draw(body: MatchTextExport.describe(entry), at: cursor, size: 10)
            }
        }
    }

    private static func subtitle(_ model: MatchExportModel) -> String {
        var parts = [model.presetName, model.startedAt.formatted(date: .long, time: .shortened)]
        if let venue = model.venue, !venue.isEmpty { parts.insert(venue, at: 1) }
        if model.status == .abandoned {
            parts.append(String(localized: "Abandoned", comment: "PDF status"))
        }
        return parts.joined(separator: " · ")
    }

    @discardableResult
    private static func draw(heading: String, at y: CGFloat, size: CGFloat = 18) -> CGFloat {
        draw(heading, at: y, font: .boldSystemFont(ofSize: size), colour: .label)
    }

    @discardableResult
    private static func draw(body: String, at y: CGFloat, size: CGFloat = 11, width: CGFloat? = nil) -> CGFloat {
        draw(body, at: y, font: .systemFont(ofSize: size), colour: .darkGray, width: width)
    }

    private static func draw(
        _ text: String,
        at y: CGFloat,
        font: UIFont,
        colour: UIColor,
        width: CGFloat? = nil
    ) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: colour]
        let available = width ?? (pageSize.width - margin * 2)
        let bounding = CGSize(width: available, height: .greatestFiniteMagnitude)
        let string = NSAttributedString(string: text, attributes: attributes)
        let height = string.boundingRect(with: bounding, options: .usesLineFragmentOrigin, context: nil).height
        string.draw(with: CGRect(x: margin, y: y, width: available, height: height),
                    options: .usesLineFragmentOrigin, context: nil)
        return y + height + 4
    }
}
