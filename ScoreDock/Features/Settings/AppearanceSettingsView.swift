import SwiftUI

/// Theme and board font picker, each rendering a live board preview.
///
/// This is where M0's "board font correct on device" exit criterion is checked: every theme and
/// every font is visible side by side, including the DSEG7 ghost segments against the pure-white
/// theme that §2.1 specifically warns about.
struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        List {
            Section {
                BoardSpecimenView(theme: settings.theme, font: settings.boardFont)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            } header: {
                Text("Preview", comment: "Appearance section")
            }

            Section {
                ForEach(BuiltInThemes.all) { theme in
                    Button {
                        settings.themeID = theme.id
                    } label: {
                        HStack(spacing: 12) {
                            ThemeSwatch(theme: theme, font: settings.boardFont)
                                .frame(width: 150)

                            Text(theme.name)
                                .foregroundStyle(.primary)

                            Spacer(minLength: 0)

                            if theme.id == settings.themeID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Theme", comment: "Appearance section")
            } footer: {
                Text(
                    "Every theme is checked to a 7:1 contrast minimum between the digits and the background, so the board stays readable across a hall.",
                    comment: "Theme section footer"
                )
            }

            Section {
                ForEach(BoardFont.allCases) { font in
                    Button {
                        settings.boardFont = font
                    } label: {
                        HStack(spacing: 12) {
                            LEDNumber(text: "12:34", theme: settings.theme, font: font, size: 26)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(settings.theme.backgroundColor)
                                .clipShape(.rect(cornerRadius: 8))
                                .frame(width: 150)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(font.displayName).foregroundStyle(.primary)
                                if !font.isBundled {
                                    Text("Falls back to system", comment: "Unbundled font note")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer(minLength: 0)

                            if font == settings.boardFont {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Board font", comment: "Appearance section")
            } footer: {
                Text(
                    "The board font applies to numbers only. Team names and labels always use the app's text face, because the seven-segment face has no Hebrew and renders letters as approximations.",
                    comment: "Board font footer"
                )
            }
        }
        .navigationTitle(Text("Board appearance", comment: "Appearance title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        AppearanceSettingsView()
            .environment(AppSettings())
    }
}
