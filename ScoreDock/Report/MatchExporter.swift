import Foundation
import PDFKit
import SwiftUI
import UIKit

/// Writes an export to a file the system share sheet can hand on (§13.5).
///
/// Everything goes through `ShareLink` and the system sheet, so it reaches Messages, WhatsApp,
/// Mail, AirDrop, Notes and Files with no integration work and no server. Nothing leaves the device
/// except the file the user explicitly shares (§13.6).
@MainActor
enum MatchExporter {
    static func export(
        _ model: MatchExportModel,
        format: ShareFormat,
        aspect: ShareCardAspect = .portrait,
        font: BoardFont = .sevenSegment
    ) throws -> URL {
        let data = try payload(model, format: format, aspect: aspect, font: font)
        return try write(data, named: fileName(for: model, format: format))
    }

    /// Several matches as one combined file (§13.5).
    ///
    /// "Tournament organisers will ask for this within a week." Only the text-shaped formats can
    /// genuinely combine; images and `.sdgame` are per-match by nature.
    static func batchExport(
        _ models: [MatchExportModel],
        format: ShareFormat,
        font: BoardFont = .sevenSegment
    ) throws -> URL {
        switch format {
        case .csv:
            var rows = [MatchCSVExport.header + ["match"]].map { $0.joined(separator: ",") }
            for model in models {
                let body = MatchCSVExport.render(model)
                    .split(separator: "\n")
                    .dropFirst()
                    .map { "\($0),\(MatchCSVExport.escape(model.title))" }
                rows.append(contentsOf: body)
            }
            return try write(Data(rows.joined(separator: "\n").utf8), named: batchName(extension: "csv"))

        case .text:
            let joined = models.map(MatchTextExport.render).joined(separator: "\n\n———\n\n")
            return try write(Data(joined.utf8), named: batchName(extension: "txt"))

        case .pdf:
            let pages = models.compactMap { MatchRenderer.pdf($0, font: font) }
            guard let combined = PDFCombiner.combine(pages) else { throw ExportError.renderFailed }
            return try write(combined, named: batchName(extension: "pdf"))

        case .image, .sdgame:
            throw ExportError.notBatchable
        }
    }

    enum ExportError: LocalizedError {
        case renderFailed
        case notBatchable

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                String(localized: "That export could not be created.", comment: "Export error")
            case .notBatchable:
                String(localized: "Images and game files are shared one match at a time.", comment: "Export error")
            }
        }
    }

    /// Byte count without writing to disk, so the share sheet can state the size up front (§13.6).
    static func estimatedSize(
        _ model: MatchExportModel,
        format: ShareFormat,
        aspect: ShareCardAspect,
        font: BoardFont
    ) -> Int? {
        try? payload(model, format: format, aspect: aspect, font: font).count
    }

    // MARK: Payload

    private static func payload(
        _ model: MatchExportModel,
        format: ShareFormat,
        aspect: ShareCardAspect,
        font: BoardFont
    ) throws -> Data {
        switch format {
        case .text:
            Data(MatchTextExport.render(model).utf8)
        case .csv:
            Data(MatchCSVExport.render(model).utf8)
        case .sdgame:
            try SdGameDocument(model).encoded()
        case .image:
            try require(MatchRenderer.image(model, aspect: aspect, font: font))
        case .pdf:
            try require(MatchRenderer.pdf(model, font: font))
        }
    }

    private static func require(_ data: Data?) throws -> Data {
        guard let data else { throw ExportError.renderFailed }
        return data
    }

    // MARK: Files

    private static func write(_ data: Data, named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func fileName(for model: MatchExportModel, format: ShareFormat) -> String {
        let sides = model.sides.map(\.name).joined(separator: " v ")
        let date = model.startedAt.formatted(.dateTime.day().month(.abbreviated).year())
        let base = sides.isEmpty ? model.title : "\(sides) \(date)"
        return "\(sanitize(base)).\(format.fileExtension)"
    }

    private static func batchName(extension ext: String) -> String {
        "\(sanitize(String(localized: "Matches", comment: "Batch export filename"))).\(ext)"
    }

    /// Strips path separators and characters that upset one filesystem or another.
    private static func sanitize(_ name: String) -> String {
        let cleaned = name
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Match" : String(cleaned.prefix(80))
    }
}

/// Merges per-match PDFs into one document for batch export.
enum PDFCombiner {
    static func combine(_ documents: [Data]) -> Data? {
        guard !documents.isEmpty else { return nil }
        let output = PDFDocument()
        var pageIndex = 0
        for data in documents {
            guard let source = PDFDocument(data: data) else { continue }
            for index in 0 ..< source.pageCount {
                guard let page = source.page(at: index) else { continue }
                output.insert(page, at: pageIndex)
                pageIndex += 1
            }
        }
        return pageIndex > 0 ? output.dataRepresentation() : nil
    }
}
