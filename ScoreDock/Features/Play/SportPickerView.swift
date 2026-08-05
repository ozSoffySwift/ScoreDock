import SwiftData
import SwiftUI

/// Home. Favourites · Recent · all presets grouped by category, with search (§3).
struct SportPickerView: View {
    @Query private var userPresets: [UserGamePreset]
    @Query private var preferences: [PresetPreference]

    /// §12: on next launch an in-progress match is detected and offered for resume, restored from
    /// its event log. A crash or a force-quit mid-game must not cost the operator the match.
    @Query private var unfinishedMatches: [Match]

    @Environment(\.modelContext) private var context
    @State private var searchText = ""
    @State private var resumed: AnyMatchStore?
    @State private var resumeFailed = false

    init() {
        // `#Predicate` needs a literal or a captured constant, not an enum member access.
        let live = MatchStatus.live.rawValue
        _unfinishedMatches = Query(
            filter: #Predicate<Match> { $0.statusRaw == live },
            sort: \Match.startedAt,
            order: .reverse
        )
    }

    private var catalog: GameCatalog {
        GameCatalog(userPresets: userPresets, preferences: preferences)
    }

    var body: some View {
        NavigationStack {
            Group {
                if catalog.presets.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No games available", comment: "Empty catalog title"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(
                            "The built-in game catalog could not be loaded. Reinstalling the app should restore it.",
                            comment: "Empty catalog description"
                        )
                    )
                } else {
                    content
                }
            }
            .navigationTitle(Text("Play", comment: "Sport picker title"))
            .searchable(
                text: $searchText,
                prompt: Text("Search games", comment: "Search field prompt")
            )
            .fullScreenCover(item: $resumed) { match in
                NavigationStack {
                    MatchHostView(store: match) { resumed = nil }
                }
            }
            .alert(
                Text("That match can't be reopened", comment: "Resume failure title"),
                isPresented: $resumeFailed
            ) {
                Button(String(localized: "OK", comment: "Alert button")) {}
            } message: {
                Text(
                    "Its saved rules could not be read, so it has been moved to History. The play-by-play is still there.",
                    comment: "Resume failure message"
                )
            }
        }
    }

    /// Offers any match left running — after a crash, a force-quit, or simply backing out (§12).
    @ViewBuilder
    private var resumeSection: some View {
        if let match = unfinishedMatches.first {
            Section {
                Button {
                    // Every engine, not just the team one. Building a `LiveMatchStore` here
                    // regardless of engine meant a live tennis, league or chess match took the
                    // failure path below and was retired — see `ResumedMatch`.
                    guard let store = AnyMatchStore(match: match, context: context) else {
                        // The rules blob could not be decoded, so the match cannot be replayed —
                        // written by a newer build, or by a schema this one no longer reads.
                        // Retire it and say so, rather than leaving a Resume button that silently
                        // does nothing every time it is pressed.
                        match.status = .abandoned
                        match.endedAt = .now
                        try? context.save()
                        resumeFailed = true
                        return
                    }
                    resumed = store
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Resume match", comment: "Resume section")
                                .foregroundStyle(.primary)
                            Text(MatchSummaryLine.text(for: match))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            } footer: {
                Text(
                    "This match is still running. Its clock kept correct time while you were away.",
                    comment: "Resume footer"
                )
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        let results = catalog.matching(searchText)

        List {
            if !searchText.isEmpty {
                if results.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    Section {
                        ForEach(results) { row($0) }
                    }
                }
            } else {
                resumeSection

                if !catalog.favourites.isEmpty {
                    Section(String(localized: "Favourites", comment: "Picker section")) {
                        ForEach(catalog.favourites) { row($0) }
                    }
                }

                let recent = catalog.recent()
                if !recent.isEmpty {
                    Section(String(localized: "Recent", comment: "Picker section")) {
                        ForEach(recent) { row($0) }
                    }
                }

                ForEach(catalog.groupedByCategory(), id: \.category) { group in
                    Section {
                        ForEach(group.presets) { row($0) }
                    } header: {
                        Label(group.category.sectionTitle, systemImage: group.category.symbolName)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ preset: GamePreset) -> some View {
        NavigationLink {
            PresetDetailView(preset: preset)
        } label: {
            PresetRow(preset: preset)
        }
        .swipeActions(edge: .leading) {
            Button {
                PresetPreferenceStore(context: context).toggleFavourite(preset)
            } label: {
                Label(
                    preset.isFavorite
                        ? String(localized: "Unfavourite", comment: "Swipe action")
                        : String(localized: "Favourite", comment: "Swipe action"),
                    systemImage: preset.isFavorite ? "star.slash" : "star"
                )
            }
            .tint(.yellow)
        }
    }
}

struct PresetRow: View {
    var preset: GamePreset

    var body: some View {
        HStack(spacing: 12) {
            Text(preset.emoji)
                .font(.title2)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if preset.isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .accessibilityLabel(Text("Favourite", comment: "Accessibility label"))
            }
            if !preset.isBuiltIn {
                Image(systemName: "person.crop.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Your game", comment: "Accessibility label"))
            }
        }
        .contentShape(.rect)
    }

    /// Composes a mixed-direction line, so each value carries its own bidi isolate (§10.2).
    private var summary: String {
        RuleSummary.rows(for: preset.rules)
            .prefix(2)
            .map { "\($0.label): \($0.isolatedValue)" }
            .joined(separator: " · ")
    }
}

#Preview {
    SportPickerView()
        .environment(AppSettings())
        .modelContainer(try! AppModelContainer.make(inMemory: true))
}
