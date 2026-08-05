import SwiftData
import SwiftUI

/// Preset detail: a live board preview, the rule summary, and where each rule value came from.
///
/// At M1 this becomes the entry point to Setup. It already carries the two things §8.5 requires of
/// every preset: the "rules vary by league" hint, and visible provenance for each value.
struct PresetDetailView: View {
    var preset: GamePreset

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var duplicated: UserGamePreset?

    private var theme: ThemeSpec { BuiltInThemes.theme(id: preset.defaultThemeID) }

    /// Tables need the room for several rows; a chess clock is two stacked faces and looks squashed
    /// in a scoreboard's letterbox.
    private var previewHeight: CGFloat {
        if preset.engine == .list { return 200 }
        switch preset.rules.specialisedRules?.board {
        case .chessClock: return 240
        case .raceTimer: return 220
        // The football board carries a situation strip under the scores, so it needs more depth
        // than the plain team letterbox.
        case .americanFootball: return 200
        case .cricket: return 190
        case .baseball: return 210
        default: return 170
        }
    }

    /// M6 lands the five bespoke boards one at a time, so a specialised preset is only playable once
    /// its board exists (§6.3).
    private var isBoardImplemented: Bool {
        guard let board = preset.rules.specialisedRules?.board else { return false }
        return SpecialisedEngine.implementedBoards.contains(board)
    }
    private var citations: [String: RuleSource] {
        guard case let .builtIn(slug) = preset.origin else { return [:] }
        return BuiltInCatalog.bySlug[slug]?.sources ?? [:]
    }

    var body: some View {
        Group {
            List {
                Section {
                    PresetPreviewView(preset: preset, theme: theme, font: settings.boardFont)
                        .frame(height: previewHeight)
                        .clipShape(.rect(cornerRadius: 12))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    if preset.engine == .team {
                        NavigationLink {
                            MatchSetupView(preset: preset)
                        } label: {
                            Label(
                                String(localized: "Set up match", comment: "Action"),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.headline)
                        }
                    } else if preset.engine == .setMatch {
                        NavigationLink {
                            SetMatchSetupView(preset: preset)
                        } label: {
                            Label(
                                String(localized: "Set up match", comment: "Action"),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.headline)
                        }
                    } else if preset.engine == .list {
                        NavigationLink {
                            ListSetupView(preset: preset)
                        } label: {
                            Label(
                                String(localized: "Set up", comment: "Action"),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.headline)
                        }
                    } else if preset.engine == .specialised, isBoardImplemented {
                        NavigationLink {
                            SpecialisedSetupView(preset: preset)
                        } label: {
                            Label(
                                String(localized: "Set up", comment: "Action"),
                                systemImage: "slider.horizontal.3"
                            )
                            .font(.headline)
                        }
                    } else {
                        // Unreachable for this build's own presets — all four engines and all five
                        // bespoke boards are implemented as of M6. It stays for a preset synced
                        // from a newer build naming a board this one has never heard of, where
                        // saying so beats a button that silently does nothing.
                        Label {
                            Text(
                                "This board is not available in this version of ScoreDock.",
                                comment: "Engine not yet available"
                            )
                            .font(.footnote)
                        } icon: {
                            Image(systemName: "clock.badge")
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Section(String(localized: "Rules", comment: "Detail section")) {
                    ForEach(RuleSummary.rows(for: preset.rules)) { row in
                        LabeledContent(row.label, value: row.value)
                            .badge(citations[row.key]?.status == .needsReview ? "!" : nil)
                    }
                }

                // §8.5 requires this on first use of every preset. Shown unconditionally here
                // because a preset's own detail screen is exactly where it belongs.
                Section {
                    Label {
                        Text(
                            "Rules vary by league — check yours. Every value here is editable in Setup.",
                            comment: "Rules disclaimer"
                        )
                        .font(.footnote)
                    } icon: {
                        Image(systemName: "info.circle")
                    }
                }

                if !preset.unverifiedRuleKeys.isEmpty {
                    Section {
                        ForEach(preset.unverifiedRuleKeys, id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key).font(.caption.weight(.semibold))
                                Text(citations[key]?.cite ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Awaiting verification", comment: "Detail section")
                    } footer: {
                        Text(
                            "These values are plausible defaults that have not yet been checked against the governing body's published rules.",
                            comment: "Unverified rules footer"
                        )
                    }
                }

                if !citations.isEmpty {
                    Section(String(localized: "Sources", comment: "Detail section")) {
                        ForEach(citations.keys.sorted(), id: \.self) { key in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key).font(.caption.weight(.semibold))
                                Text(citations[key]?.cite ?? "")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section {
                    Button {
                        PresetPreferenceStore(context: context).toggleFavourite(preset)
                    } label: {
                        Label(
                            preset.isFavorite
                                ? String(localized: "Remove from favourites", comment: "Action")
                                : String(localized: "Add to favourites", comment: "Action"),
                            systemImage: preset.isFavorite ? "star.slash" : "star"
                        )
                    }

                    // Built-ins are read-only; editing offers Duplicate and edit (§7.4).
                    Button {
                        duplicated = PresetPreferenceStore(context: context).duplicate(preset)
                    } label: {
                        Label(
                            String(localized: "Duplicate and edit", comment: "Action"),
                            systemImage: "doc.on.doc"
                        )
                    }
                }
            }
            .navigationTitle(preset.name)
            .navigationBarTitleDisplayMode(.inline)
            .alert(
                Text("Saved to My Games", comment: "Duplicate confirmation title"),
                isPresented: .constant(duplicated != nil),
                presenting: duplicated
            ) { _ in
                Button(String(localized: "OK", comment: "Alert button")) { duplicated = nil }
            } message: { copy in
                Text("“\(copy.name)” is now editable in Library → My Games.", comment: "Duplicate confirmation body")
            }
        }
    }

}
