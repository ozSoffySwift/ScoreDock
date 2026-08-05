import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// Import and normalisation for player photos and team crests (§7.1a).
///
/// ## Metadata is stripped, not trusted
///
/// Every import is **re-rendered into a fresh bitmap** rather than having its bytes copied through.
/// That is the whole point: a photo of a child at a home ground carries the home address in its GPS
/// tags, and these images end up inside `.sdgame` files, PDFs and share cards that get handed to
/// strangers. Re-drawing through a `CGContext` cannot carry EXIF, GPS, or anything else — there is
/// no "strip the tags" step to forget, because nothing from the original container survives.
///
/// `IdentityImageTests` proves this by constructing an image *with* GPS tags and asserting they are
/// gone afterwards.
enum IdentityImage {
    /// Longest edge after import. Enough for a projected board, small enough to keep the store and
    /// `.sdgame` exports light (§7.1a, §17 risk 12).
    static let maxDimension: CGFloat = 1024

    static let jpegQuality: CGFloat = 0.85

    /// Refuse anything absurd before decoding it — an imported `.sdgame` is an untrusted file
    /// (§17 risk 11), and a decompression bomb is the cheapest attack on an image pipeline.
    static let maxSourcePixels = 64_000_000
    static let maxSourceBytes = 40 * 1024 * 1024

    enum ImportError: LocalizedError {
        case unreadable
        case tooLarge
        case tooManyPixels

        var errorDescription: String? {
            switch self {
            case .unreadable:
                String(localized: "That image could not be read.", comment: "Image import error")
            case .tooLarge, .tooManyPixels:
                String(localized: "That image is too large to use.", comment: "Image import error")
            }
        }
    }

    /// Normalises arbitrary image data into a square, metadata-free asset.
    static func normalize(_ data: Data) throws -> Data {
        guard data.count <= maxSourceBytes else { throw ImportError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { throw ImportError.unreadable }

        // Check declared dimensions *before* decoding, so an oversized image is rejected rather
        // than expanded into memory first.
        if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = properties[kCGImagePropertyPixelWidth] as? Int,
           let height = properties[kCGImagePropertyPixelHeight] as? Int,
           width * height > maxSourcePixels {
            throw ImportError.tooManyPixels
        }

        guard let image = UIImage(data: data) else { throw ImportError.unreadable }
        guard let normalized = normalize(image) else { throw ImportError.unreadable }
        return normalized
    }

    /// Square, centre-cropped, downscaled, and re-encoded.
    ///
    /// Transparency decides the format: crests usually have it and JPEG would fill it with black,
    /// so those become PNG. Photographs become JPEG, which is dramatically smaller.
    static func normalize(_ image: UIImage) -> Data? {
        guard let cgImage = image.cgImage else { return nil }

        let keepsAlpha = hasAlpha(cgImage)
        let side = min(
            maxDimension,
            max(1, min(CGFloat(cgImage.width), CGFloat(cgImage.height)))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = !keepsAlpha
        format.preferredRange = .standard

        let canvas = CGSize(width: side, height: side)
        let rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            // Aspect-fill into the square: scale so the shorter edge covers, then centre.
            let scale = max(canvas.width / image.size.width, canvas.height / image.size.height)
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(
                x: (canvas.width - drawn.width) / 2,
                y: (canvas.height - drawn.height) / 2,
                width: drawn.width,
                height: drawn.height
            ))
        }

        // Re-encoding a freshly drawn bitmap is what drops the source's tags. The encoder writes a
        // new structural EXIF/TIFF block of its own — pixel dimensions, colour space, orientation —
        // which identifies nothing and cannot be suppressed without breaking PNG output. What must
        // never survive is anything *identifying*; `sensitiveMetadata(in:)` is the checkable form
        // of that, and `IdentityImageTests` asserts it against a genuinely GPS-tagged fixture.
        return keepsAlpha ? rendered.pngData() : rendered.jpegData(compressionQuality: jpegQuality)
    }

    /// Written as a statement with explicit returns rather than as a switch *expression*: the
    /// expression form does not accept `@unknown default` as a value-producing branch, and dropping
    /// it to a plain `default` would give up the warning that tells us a new alpha format exists.
    static func hasAlpha(_ cgImage: CGImage) -> Bool {
        switch cgImage.alphaInfo {
        // `.alphaOnly` is a mask — alpha and nothing else — so it is the most alpha an image can be.
        case .first, .last, .premultipliedFirst, .premultipliedLast, .alphaOnly:
            return true
        case .none, .noneSkipFirst, .noneSkipLast:
            return false
        @unknown default:
            // Errs towards **keeping** the channel. This chooses PNG over JPEG, so an alpha format
            // this build has never heard of costs a larger file rather than silently flattening the
            // transparency out of somebody's crest.
            return true
        }
    }

    /// Identifying metadata found in image data — empty is the requirement.
    ///
    /// Deliberately narrower than "any metadata at all". A re-encoded bitmap always carries some
    /// structural EXIF/TIFF (pixel dimensions, colour space, orientation), and asserting its absence
    /// would test the encoder rather than the privacy property. What this looks for is everything
    /// that can identify a **person, a place, a time or a device**:
    ///
    /// - a GPS dictionary in any form — the home-address case §7.1a calls out
    /// - original capture timestamps
    /// - free-text comments and descriptions
    /// - camera make/model, owner, artist, copyright
    /// - IPTC and Apple maker notes, which carry both
    static func sensitiveMetadata(in data: Data) -> Set<String> {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return [] }

        var found: Set<String> = []

        // Any GPS at all is a failure — there is no benign subset.
        if properties[kCGImagePropertyGPSDictionary] != nil { found.insert("GPS") }
        if properties[kCGImagePropertyIPTCDictionary] != nil { found.insert("IPTC") }
        if properties[kCGImagePropertyMakerAppleDictionary] != nil { found.insert("MakerApple") }

        let exifFields: [CFString] = [
            kCGImagePropertyExifDateTimeOriginal,
            kCGImagePropertyExifDateTimeDigitized,
            kCGImagePropertyExifSubsecTimeOriginal,
            kCGImagePropertyExifUserComment,
            kCGImagePropertyExifCameraOwnerName,
            kCGImagePropertyExifBodySerialNumber,
            kCGImagePropertyExifLensSerialNumber,
        ]
        if let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            for field in exifFields where exif[field] != nil {
                found.insert("Exif.\(field as String)")
            }
        }

        let tiffFields: [CFString] = [
            kCGImagePropertyTIFFMake,
            kCGImagePropertyTIFFModel,
            kCGImagePropertyTIFFArtist,
            kCGImagePropertyTIFFCopyright,
            kCGImagePropertyTIFFDateTime,
            kCGImagePropertyTIFFImageDescription,
        ]
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            for field in tiffFields where tiff[field] != nil {
                found.insert("TIFF.\(field as String)")
            }
        }

        return found
    }
}
