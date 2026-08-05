import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import ScoreDock

/// §7.1a: *"Strip all metadata on import, GPS especially. A photo of a child at a home ground
/// carries the home address in its metadata, and these images end up inside shared files."*
///
/// This is the privacy guarantee of the whole identity feature, so it is asserted against an image
/// that genuinely carries GPS tags rather than assumed from the implementation.
@Suite("Identity images (§7.1a)")
struct IdentityImageTests {
    /// A small JPEG carrying GPS and EXIF dictionaries.
    private func imageWithLocation(size: CGSize = CGSize(width: 200, height: 300)) throws -> Data {
        // scale = 1 so the fixture's point size is its pixel size; the renderer would otherwise
        // apply the device scale and turn a 4000-point image into a 12000-pixel one.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let source = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let cgImage = try #require(source.cgImage)

        let output = NSMutableData()
        let destination = try #require(
            CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil)
        )
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 32.0853,
                kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 34.7818,
                kCGImagePropertyGPSLongitudeRef: "E",
            ] as [CFString: Any],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "home ground",
                kCGImagePropertyExifDateTimeOriginal: "2026:07:29 19:00:00",
            ] as [CFString: Any],
        ]
        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return output as Data
    }

    @Test("The fixture really does carry location and comment tags")
    func fixtureIsTagged() throws {
        let tagged = try imageWithLocation()
        let found = IdentityImage.sensitiveMetadata(in: tagged)
        // Without this, the next test would pass against an image that never had GPS to begin with.
        #expect(found.contains("GPS"))
        #expect(found.contains("Exif.\(kCGImagePropertyExifUserComment as String)"))
        #expect(found.contains("Exif.\(kCGImagePropertyExifDateTimeOriginal as String)"))
    }

    /// The guarantee: nothing identifying survives an import.
    @Test("Import strips GPS, timestamps and comments")
    func importStripsIdentifyingMetadata() throws {
        let tagged = try imageWithLocation()
        let cleaned = try IdentityImage.normalize(tagged)

        #expect(
            IdentityImage.sensitiveMetadata(in: cleaned).isEmpty,
            "an imported photo must not carry location, capture time, comments or device identity"
        )
        // And it is genuinely re-encoded, not the original bytes passed through.
        #expect(cleaned != tagged)
    }

    @Test("Import produces a square image within the size ceiling")
    func importIsSquareAndBounded() throws {
        let tagged = try imageWithLocation(size: CGSize(width: 4000, height: 2000))
        let cleaned = try IdentityImage.normalize(tagged)
        let image = try #require(UIImage(data: cleaned))

        #expect(image.size.width == image.size.height, "lists render circular, the board renders square")
        #expect(image.size.width <= IdentityImage.maxDimension)
    }

    @Test("Transparency is preserved as PNG, opaque images become JPEG")
    func formatFollowsTransparency() throws {
        let size = CGSize(width: 120, height: 120)

        let opaqueFormat = UIGraphicsImageRendererFormat()
        opaqueFormat.scale = 1
        opaqueFormat.opaque = true
        let opaque = UIGraphicsImageRenderer(size: size, format: opaqueFormat).image { context in
            UIColor.systemIndigo.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let opaqueData = try #require(IdentityImage.normalize(opaque))
        // JPEG magic number.
        #expect(opaqueData.prefix(2) == Data([0xFF, 0xD8]))

        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        let transparent = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemPink.withAlphaComponent(0.5).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 60))
        }
        let transparentData = try #require(IdentityImage.normalize(transparent))
        // PNG magic number — a crest filled with black would be a visible bug.
        #expect(transparentData.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test("Oversized payloads are refused before decoding")
    func rejectsOversizedInput() {
        let bomb = Data(repeating: 0, count: IdentityImage.maxSourceBytes + 1)
        #expect(throws: IdentityImage.ImportError.self) {
            try IdentityImage.normalize(bomb)
        }
    }

    @Test("Garbage is refused rather than producing a blank image")
    func rejectsGarbage() {
        #expect(throws: IdentityImage.ImportError.self) {
            try IdentityImage.normalize(Data("not an image".utf8))
        }
    }
}
