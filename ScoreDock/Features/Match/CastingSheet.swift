import SwiftUI

/// Instructions for getting the board onto a TV (§5.4).
///
/// **The honest constraint.** There is no public API to start whole-app screen mirroring from
/// inside an app. `AVRoutePickerView` routes AVFoundation *media playback*, not the app's UI, so a
/// route picker here would look like the answer and do nothing. The user has to open Control Centre
/// themselves — so the app's job is to explain it once, clearly, and then get out of the way.
///
/// The sheet dismisses itself the moment an external scene connects. Detect it, confirm it,
/// disappear.
struct CastingSheet: View {
    @State private var externalDisplay = ExternalDisplay.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if externalDisplay.isConnected {
                    Section {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Connected", comment: "Casting status")
                                    .font(.headline)
                                Text(
                                    "The board is on your TV. Your controls stay here.",
                                    comment: "Casting connected detail"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        // Reachable from every board, not just the two panels that happened to
                        // have an inline strip. Shows nothing when the board has one mode.
                        BoardModePicker()
                    }
                } else {
                    Section {
                        step(1, systemImage: "iphone.gen3", text: String(
                            localized: "Swipe down from the top-right corner to open Control Centre.",
                            comment: "Casting step"
                        ))
                        step(2, systemImage: "rectangle.on.rectangle", text: String(
                            localized: "Tap Screen Mirroring.",
                            comment: "Casting step"
                        ))
                        step(3, systemImage: "appletv", text: String(
                            localized: "Pick your Apple TV. Come back here — the board appears on the TV automatically.",
                            comment: "Casting step"
                        ))
                    } header: {
                        Text("Cast over AirPlay", comment: "Casting section")
                    } footer: {
                        Text(
                            "iOS does not let an app start mirroring for you, so this part has to be done from Control Centre.",
                            comment: "Casting explanation"
                        )
                    }

                    Section {
                        Label {
                            Text(
                                "A USB-C or Lightning to HDMI adapter connects with no steps at all, and does not drop out mid-match. In a real venue it is the more reliable choice.",
                                comment: "Wired casting advice"
                            )
                            .font(.footnote)
                        } icon: {
                            Image(systemName: "cable.connector")
                        }
                    } header: {
                        Text("Or use a cable", comment: "Casting section")
                    }

                    Section {
                        Label {
                            Text(
                                "Turn on a Focus before you start, so notifications don't appear on the TV.",
                                comment: "Casting focus advice"
                            )
                            .font(.footnote)
                        } icon: {
                            Image(systemName: "moon.fill")
                        }
                    }
                }
            }
            .navigationTitle(Text("Cast to TV", comment: "Casting sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Dismiss button")) { dismiss() }
                }
            }
            // Celebrate it, then get out of the way (§5.4).
            .onChange(of: externalDisplay.isConnected) { _, connected in
                guard connected else { return }
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    dismiss()
                }
            }
        }
    }

    private func step(_ number: Int, systemImage: String, text: String) -> some View {
        Label {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(number).")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.tint)
                Text(text).font(.subheadline)
            }
        } icon: {
            Image(systemName: systemImage)
        }
    }
}

#Preview {
    CastingSheet()
}
