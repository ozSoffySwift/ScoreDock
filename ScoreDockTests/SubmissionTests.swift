import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import ScoreDock

/// §16, §18 — the things App Store Connect refuses a build for.
///
/// Every one of these is invisible while developing and fatal at upload, which is the worst
/// combination a check can have. They are asserted against the **built bundle**, not the source, so
/// a file that exists but never gets copied still fails.
@Suite("Submission readiness (§16, §18)")
struct SubmissionTests {
    private var bundle: Bundle { Bundle(for: AppDelegate.self) }

    // MARK: Privacy manifest

    @Test("The privacy manifest ships in the bundle")
    func privacyManifestExists() throws {
        let url = try #require(
            bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy is not in the app bundle"
        )
        _ = try Data(contentsOf: url)
    }

    @Test("The manifest declares no tracking and no collected data")
    func privacyManifestClaimsNothing() throws {
        let manifest = try privacyManifest()

        #expect(manifest["NSPrivacyTracking"] as? Bool == false)
        #expect((manifest["NSPrivacyTrackingDomains"] as? [String])?.isEmpty == true)

        // §16 is a factual claim, not an aspiration: there is no analytics SDK, no telemetry, no
        // crash reporter and no network client in the app at all.
        let collected = manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        #expect(collected?.isEmpty == true, "the app collects nothing; the manifest must say so")
    }

    /// A required-reason API used without a declared reason is an automatic rejection.
    @Test("Every required-reason API the app uses is declared with a reason")
    func requiredReasonsDeclared() throws {
        let manifest = try privacyManifest()
        let declared = manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]] ?? []

        let byCategory = Dictionary(uniqueKeysWithValues: declared.compactMap { entry -> (String, [String])? in
            guard let category = entry["NSPrivacyAccessedAPIType"] as? String else { return nil }
            return (category, entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? [])
        })

        // `AppSettings` keeps board font, theme, sound and haptics in `UserDefaults`. They are this
        // app's own settings, read and written only by this app — reason CA92.1.
        #expect(byCategory["NSPrivacyAccessedAPICategoryUserDefaults"]?.contains("CA92.1") == true)

        // Nothing may be declared without a reason, whatever the category.
        for (category, reasons) in byCategory {
            #expect(!reasons.isEmpty, "\(category) is declared with no reason")
        }
    }

    private func privacyManifest() throws -> [String: Any] {
        let url = try #require(bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"))
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    // MARK: App icon

    /// An app icon is **not** loadable with `UIImage(named:)` — `actool` extracts it to
    /// `AppIcon60x60@2x.png` at the bundle root and registers it under `CFBundleIcons`. Asking for
    /// it by name returns nil even when everything is correct, so the icon set being empty (which it
    /// was until M8) has to be caught through the registration instead.
    @Test("The app icon is registered and extracted into the bundle")
    func appIconExists() throws {
        let icons = try #require(
            bundle.infoDictionary?["CFBundleIcons"] as? [String: Any],
            "CFBundleIcons is missing — the icon set is empty"
        )
        let primary = try #require(icons["CFBundlePrimaryIcon"] as? [String: Any])
        #expect(primary["CFBundleIconName"] as? String == "AppIcon")

        let files = try #require(primary["CFBundleIconFiles"] as? [String])
        #expect(!files.isEmpty)

        // Registered is not the same as present: the PNG has to actually be in the bundle.
        for file in files {
            let matches = try #require(
                try? FileManager.default.contentsOfDirectory(atPath: bundle.bundlePath)
                    .filter { $0.hasPrefix(file) }
            )
            #expect(!matches.isEmpty, "\(file) is registered but not in the bundle")
        }
    }

    /// App Store Connect rejects a marketing icon carrying an alpha channel, and the renderer
    /// produced one by default until it was told not to.
    ///
    /// Checked against the **source** PNG rather than the extracted variants, because that 1024 is
    /// the file the App Store actually inspects; the smaller ones are re-encoded by `actool`.
    @Test("The marketing icon is opaque")
    func appIconIsOpaque() throws {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "ScoreDock/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
            )

        let data = try Data(contentsOf: source)
        let image = try #require(UIImage(data: data)?.cgImage)

        #expect(image.width == 1024 && image.height == 1024)
        let alpha = image.alphaInfo
        #expect(
            alpha == .none || alpha == .noneSkipLast || alpha == .noneSkipFirst,
            "the icon has an alpha channel (\(alpha.rawValue))"
        )
    }

    // MARK: Info.plist

    @Test("Export compliance is answered in the bundle, not at every upload")
    func encryptionDeclared() {
        #expect(bundle.infoDictionary?["ITSAppUsesNonExemptEncryption"] as? Bool == false)
    }

    @Test("A shared game file opens in place rather than being copied to an Inbox")
    func opensDocumentsInPlace() {
        #expect(bundle.infoDictionary?["LSSupportsOpeningDocumentsInPlace"] as? Bool == true)
    }

    @Test("The exported game type and its document type agree")
    func gameTypeIsConsistent() throws {
        let exported = bundle.infoDictionary?["UTExportedTypeDeclarations"] as? [[String: Any]]
        let identifier = try #require((exported?.first?["UTTypeIdentifier"]) as? String)
        #expect(identifier == UTType.sdGame.identifier)

        let documents = bundle.infoDictionary?["CFBundleDocumentTypes"] as? [[String: Any]]
        let handled = try #require((documents?.first?["LSItemContentTypes"]) as? [String])
        #expect(handled.contains(identifier), "the app declares a type it does not open")
    }

    @Test("Every orientation stays supported, on both idioms")
    func orientationsStayOpen() throws {
        // Read from the bundle's `Info.plist` rather than `infoDictionary`: the runtime dictionary
        // resolves `~ipad` suffixes for the *current* device, so the iPad key is simply invisible
        // from an iPhone. The file is what ships and what the App Store reads.
        let plist = try bundleInfoPlist()

        // §5.1: rotate-to-board depends on the supported set never being narrowed.
        for key in ["UISupportedInterfaceOrientations", "UISupportedInterfaceOrientations~ipad"] {
            let orientations = try #require(plist[key] as? [String], "\(key) is missing")
            #expect(orientations.count == 4, "\(key) lost an orientation")
        }
    }

    private func bundleInfoPlist() throws -> [String: Any] {
        let url = bundle.bundleURL.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    /// §17 risk 1 keeps the name in one place; this makes sure it stays there.
    @Test("The display name comes from the bundle, never from source")
    func displayNameIsInThePlist() throws {
        let name = try #require(bundle.infoDictionary?["CFBundleDisplayName"] as? String)
        #expect(!name.isEmpty)
    }

    // MARK: Product identity

    /// The name lives in five places that are each easy to change alone: the display name, the
    /// bundle identifier, the Swift module, the exported UTI and the file extension. The rename from
    /// *ScoreCounter* (§17 risk 1) touched all five at once; this makes a half-revert fail loudly
    /// instead of shipping an app called one thing that writes files named after another.
    @Test("The product name is consistent everywhere it is recorded")
    func productIdentityIsConsistent() throws {
        let plist = try bundleInfoPlist()

        #expect(bundle.infoDictionary?["CFBundleDisplayName"] as? String == "ScoreDock")
        #expect(bundle.bundleIdentifier == "com.ozsoffy.scoredock")

        // The scene-delegate string carries the module name through `$(PRODUCT_MODULE_NAME)`.
        let manifest = try #require(plist["UIApplicationSceneManifest"] as? [String: Any])
        let configurations = try #require(manifest["UISceneConfigurations"] as? [String: Any])
        let external = try #require(
            configurations["UIWindowSceneSessionRoleExternalDisplayNonInteractive"] as? [[String: Any]]
        )
        let className = try #require(external.first?["UISceneDelegateClassName"] as? String)
        #expect(className == "ScoreDock.ExternalDisplaySceneDelegate")

        // The exported type and the extension it claims.
        #expect(UTType.sdGame.identifier == "com.ozsoffy.scoredock.game")
        #expect(ShareFormat.sdgame.fileExtension == "sdgame")
    }

    /// The old name must not survive anywhere a user could see it.
    @Test("No shipped string still says ScoreCounter")
    func oldNameIsGone() throws {
        let plist = try bundleInfoPlist()

        for key in ["CFBundleDisplayName", "CFBundleName"] {
            let value = plist[key] as? String ?? ""
            #expect(!value.localizedCaseInsensitiveContains("scorecounter"), "\(key) still says \(value)")
        }

        let exported = try #require(plist["UTExportedTypeDeclarations"] as? [[String: Any]])
        let identifier = try #require(exported.first?["UTTypeIdentifier"] as? String)
        #expect(!identifier.contains("scorecounter"))

        let description = try #require(exported.first?["UTTypeDescription"] as? String)
        #expect(description == "ScoreDock Game")
    }
}
