import SwiftUI

/// Picks what the television shows (§6.1) — the reference site's "separate screen URL", natively.
///
/// Offers only the modes the running board can actually fill. Both call sites listed
/// `BoardMode.allCases`, so a basketball match with the shot clock switched off still offered "Shot
/// clock only", and the TV answered with a dash. With the external display now reaching every
/// engine, the same list would have offered a chess clock a shot clock.
///
/// Renders nothing at all when there is only one mode, because a picker with one option is a label
/// that looks like a control.
struct BoardModePicker: View {
    @State private var active = ActiveMatch.shared

    var body: some View {
        let modes = active.store.map(BoardMode.available(for:)) ?? []

        if modes.count > 1 {
            Picker(
                String(localized: "TV shows", comment: "Board mode picker"),
                selection: Binding(get: { active.boardMode }, set: { active.boardMode = $0 })
            ) {
                ForEach(modes) { mode in
                    Label(mode.displayName, systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}
