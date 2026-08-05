import Foundation

/// The 12 built-in themes (§9.1), all free in v1 like everything else (§14.1).
///
/// Bundled values, not seeded rows — same reasoning as the preset catalog (§7.4). Every palette
/// here is held to a 7:1 minimum contrast on digits, labels and accent, and that is asserted by
/// `ThemeContrastTests` rather than assumed (§9.2, §15).
enum BuiltInThemes {
    /// Dark is the default: it holds contrast under gym house lights and keys cleanly in OBS (§9.2).
    static let defaultID = "dark"

    static let all: [ThemeSpec] = [
        ThemeSpec(
            id: "dark", name: "Dark",
            background: "#101114", digit: "#F5F7FA", digitGhost: "#26282E",
            label: "#C7CBD1", accent: "#FFB300", isDark: true
        ),
        ThemeSpec(
            id: "light", name: "Light",
            background: "#F2F3F5", digit: "#14161A", digitGhost: "#DCDEE2",
            label: "#33373D", accent: "#7A3D00", isDark: false
        ),
        ThemeSpec(
            id: "black", name: "Black",
            background: "#000000", digit: "#FFFFFF", digitGhost: "#1C1C1C",
            label: "#E6E6E6", accent: "#FFC400", isDark: true
        ),
        // The pure-white case §2.1 warns about: the ghost segments have to stay visible without
        // turning muddy, which is why #E4E4E4 is tuned rather than picked by eye.
        ThemeSpec(
            id: "white", name: "White",
            background: "#FFFFFF", digit: "#000000", digitGhost: "#E4E4E4",
            label: "#1A1A1A", accent: "#8A3A00", isDark: false
        ),
        ThemeSpec(
            id: "grass", name: "Grass",
            background: "#0B3D1E", digit: "#F2FFF4", digitGhost: "#134A28",
            label: "#CFEBD6", accent: "#FFD54F", isDark: true
        ),
        ThemeSpec(
            id: "neon", name: "Neon",
            background: "#07070E", digit: "#39FF14", digitGhost: "#0E2A0B",
            label: "#B8FFAE", accent: "#FF4FE8", isDark: true
        ),
        // Classic amber LED panel.
        ThemeSpec(
            id: "amber", name: "Amber",
            background: "#140E00", digit: "#FFB000", digitGhost: "#2E1F00",
            label: "#FFD98A", accent: "#FF8A50", isDark: true
        ),
        ThemeSpec(
            id: "sky", name: "Sky",
            background: "#04263D", digit: "#EAF7FF", digitGhost: "#0B3A57",
            label: "#B8DDF2", accent: "#FFCA28", isDark: true
        ),
        ThemeSpec(
            id: "cyan", name: "Cyan",
            background: "#001A1C", digit: "#00E5E0", digitGhost: "#00393B",
            label: "#8FF3F0", accent: "#FFD166", isDark: true
        ),
        ThemeSpec(
            id: "forest", name: "Forest",
            background: "#06231A", digit: "#E8FFF4", digitGhost: "#0C3628",
            label: "#A8D9C4", accent: "#FFD166", isDark: true
        ),
        ThemeSpec(
            id: "coral", name: "Coral",
            background: "#2B0D10", digit: "#FFE9E6", digitGhost: "#4A1A1F",
            label: "#FFB3A7", accent: "#FF8A73", isDark: true
        ),
        ThemeSpec(
            id: "roland", name: "Roland",
            background: "#0A0A0A", digit: "#FF7A3D", digitGhost: "#421C0C",
            label: "#FFC9A8", accent: "#E8D44D", isDark: true
        ),
    ]

    static let byID: [String: ThemeSpec] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    /// Never fails: an unknown id lands on the default rather than leaving a board unrendered.
    static func theme(id: String?) -> ThemeSpec {
        guard let id, let match = byID[id] else { return byID[defaultID]! }
        return match
    }
}
