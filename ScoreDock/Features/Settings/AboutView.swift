import SwiftUI

struct AboutView: View {
    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }

    var body: some View {
        List {
            Section {
                LabeledContent(String(localized: "Version", comment: "About row"), value: version)
            }

            // §14.1. Stating this plainly is part of the product: v1.0 is not a free *tier*, it is
            // simply a free app, and anything charged for later must be something that did not
            // exist in v1 (§14.2).
            Section {
                Text(
                    "Every feature in this version is free. There is no paywall, no locked feature and no in-app purchase of any kind.",
                    comment: "Free-forever statement"
                )
                .font(.footnote)
            } header: {
                Text("Pricing", comment: "About section")
            }

            Section {
                Text(
                    "Your matches never leave your device except in the files you explicitly share. ScoreDock collects anonymous usage statistics — how often the app is opened and which boards are used — with no account, no advertising identifier and nothing that identifies you.",
                    comment: "Privacy statement"
                )
                .font(.footnote)
            } header: {
                Text("Privacy", comment: "About section")
            }

            // §2.1 step 6. Not strictly required when a font is embedded in a program, but it is
            // correct practice and it costs one line.
            Section {
                Text(
                    "Seven-segment display font: DSEG by keshikan, SIL Open Font License 1.1.",
                    comment: "Font attribution"
                )
                .font(.footnote)

                Link(
                    String(localized: "keshikan.net", comment: "Font author link"),
                    destination: URL(string: "https://www.keshikan.net/fonts-e.html")!
                )
                .font(.footnote)
            } header: {
                Text("Acknowledgements", comment: "About section")
            }

            #if DEBUG
            // A font that fails to register is silently invisible until someone notices the board
            // looks wrong — usually at a match. §2.1 step 4 asks for runtime verification rather
            // than trusting the filename, so it is surfaced here during development.
            Section {
                let missing = BoardFontRegistry.missingBundledFonts
                if missing.isEmpty {
                    Label(
                        String(localized: "All bundled fonts registered", comment: "Font diagnostic"),
                        systemImage: "checkmark.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.green)
                } else {
                    ForEach(missing) { font in
                        Label(font.rawValue, systemImage: "xmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    Text(
                        "Check Target Membership and the UIAppFonts entries in Info.plist.",
                        comment: "Font diagnostic hint"
                    )
                    .font(.caption2)
                }

                // Same reasoning as the font check: a buzzer that failed to load is silent, and
                // silence is indistinguishable from "the period hasn't ended yet".
                let missingSounds = MatchAudio.shared.missingSounds
                if missingSounds.isEmpty {
                    Label(
                        String(localized: "All sounds loaded", comment: "Audio diagnostic"),
                        systemImage: "checkmark.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(.green)
                } else {
                    ForEach(missingSounds, id: \.rawValue) { sound in
                        Label(sound.fileName, systemImage: "xmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Asset diagnostics (debug)", comment: "About section")
            }
            #endif
        }
        .navigationTitle(Text("About", comment: "About title"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AboutView() }
}
