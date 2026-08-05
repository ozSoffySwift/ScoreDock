import Foundation
import SwiftData

/// A stored theme record.
///
/// The 12 built-in themes are value types in `BuiltInThemes`, not rows — same reasoning as the
/// preset catalog (§7.4). This model exists for user-authored themes, which are a post-v1 feature;
/// it is defined now so that shipping them later is not a schema migration.
@Model
final class ThemePreset {
    var id: String = ""
    var name: String = ""
    var isBuiltIn: Bool = true

    /// Inert in v1 and always false — v1.0 has no paid features at all (§14.1).
    ///
    /// Kept in the schema deliberately: it costs nothing now and saves a migration if paid themes
    /// ever ship (§14.3). It must never be set true for anything that shipped free, because a
    /// feature that shipped free can never later move behind a paywall (§14.2).
    var isPro: Bool = false

    /// Held as `Data` and read through `spec`, for the same reason as the rule blobs — see
    /// `CodableBlob`.
    var specData: Data?

    init(id: String = "", name: String = "", isBuiltIn: Bool = true, isPro: Bool = false, spec: ThemeSpec? = nil) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.isPro = isPro
        self.specData = CodableBlob.encode(spec)
    }
}

extension ThemePreset {
    var spec: ThemeSpec? {
        get { CodableBlob.decode(specData) }
        set { specData = CodableBlob.encode(newValue) }
    }
}
