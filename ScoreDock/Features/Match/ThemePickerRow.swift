import SwiftUI

/// The horizontal strip of theme swatches every setup screen offers (§9.2).
///
/// Extracted on the fourth copy. Each swatch renders a real `88:88` in the board font rather than a
/// colour chip, because what a theme actually changes is how the digits read — and a swatch that
/// truncated that number would advertise a board that cannot show a score.
struct ThemePickerRow: View {
    @Binding var selection: String

    @Environment(AppSettings.self) private var settings

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(BuiltInThemes.all) { candidate in
                    Button { selection = candidate.id } label: {
                        ThemeSwatch(theme: candidate, font: settings.boardFont, size: 18)
                            .frame(width: 104)
                            .overlay {
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(
                                        candidate.id == selection ? Color.accentColor : .clear,
                                        lineWidth: 3
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(candidate.name))
                    .accessibilityAddTraits(candidate.id == selection ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 4)
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
    }
}
