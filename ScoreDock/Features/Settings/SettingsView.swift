import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        AppearanceSettingsView()
                    } label: {
                        LabeledContent {
                            Text(settings.theme.name)
                        } label: {
                            Label(
                                String(localized: "Board appearance", comment: "Settings row"),
                                systemImage: "paintpalette"
                            )
                        }
                    }
                }

                Section {
                    Toggle(isOn: $settings.soundEnabled) {
                        Label(String(localized: "Sound", comment: "Settings row"), systemImage: "speaker.wave.2")
                    }
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label(String(localized: "Haptics", comment: "Settings row"), systemImage: "hand.tap")
                    }
                } header: {
                    Text("Feedback", comment: "Settings section")
                } footer: {
                    // §11.1: `.playback` with `.mixWithOthers` means the buzzer sounds with the
                    // ring switch on silent — correct for a scoreboard — while venue music keeps
                    // playing.
                    Text(
                        "The end-of-period buzzer sounds even when your phone is on silent, and it won't stop the venue's music.",
                        comment: "Audio settings footer"
                    )
                }

                if settings.soundEnabled {
                    Section {
                        soundToggle(.buzzer, isOn: $settings.buzzerEnabled)
                        soundToggle(.horn, isOn: $settings.shotClockHornEnabled)
                        soundToggle(.tick, isOn: $settings.shotClockTickEnabled)
                        soundToggle(.chime, isOn: $settings.breakChimeEnabled)
                        soundToggle(.warning, isOn: $settings.timerWarningEnabled)
                    } header: {
                        Text("Individual sounds", comment: "Settings section")
                    } footer: {
                        Text(
                            "Tap a name to hear it. The timer warning is off by default — an unexpected beep in a quiet hall is worse than none.",
                            comment: "Individual sounds footer"
                        )
                    }
                }

                Section {
                    Toggle(isOn: $settings.burnInProtection) {
                        Label(
                            String(localized: "Burn-in protection", comment: "Settings row"),
                            systemImage: "display"
                        )
                    }
                } header: {
                    Text("Display", comment: "Settings section")
                } footer: {
                    Text(
                        "Shifts the board by a couple of points every 90 seconds. Imperceptible while watching, and it protects OLED phone and TV panels during a long match.",
                        comment: "Burn-in footer"
                    )
                }

                Section {
                    Toggle(isOn: $settings.shareWatermark) {
                        Label(
                            String(localized: "App mark on shared images", comment: "Settings row"),
                            systemImage: "square.and.arrow.up"
                        )
                    }
                } header: {
                    Text("Sharing", comment: "Settings section")
                } footer: {
                    Text(
                        "A small app mark appears in the corner of shared images and PDFs. Turning it off is free and always will be.",
                        comment: "Watermark footer"
                    )
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label(String(localized: "About", comment: "Settings row"), systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle(Text("Settings", comment: "Settings title"))
        }
    }

    /// A toggle whose label previews the sound, so an operator can tell the period buzzer and the
    /// shot-clock horn apart without starting a match to find out.
    private func soundToggle(_ sound: MatchSound, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Button {
                MatchAudio.shared.play(sound)
            } label: {
                HStack(spacing: 6) {
                    Text(sound.displayName).foregroundStyle(.primary)
                    Image(systemName: "play.circle").font(.caption).foregroundStyle(.tint)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Double tap to preview", comment: "Accessibility"))
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppSettings())
}
