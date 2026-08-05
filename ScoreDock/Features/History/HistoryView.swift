import SwiftData
import SwiftUI

/// Match list, with the Match Report behind each row (§3, §13.4).
///
/// Nothing here expires. Every match keeps its complete log forever.
struct HistoryView: View {
    @Query(sort: \Match.startedAt, order: .reverse) private var matches: [Match]

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings

    @State private var searchText = ""
    @State private var selection: Set<Match.ID> = []
    @State private var isSelecting = false
    @State private var batchURL: URL?
    @State private var batchError: String?

    private var visible: [Match] {
        guard !searchText.isEmpty else { return matches }
        return matches.filter { match in
            let haystack = [
                match.title ?? "",
                match.venue ?? "",
                BuiltInCatalog.bySlug[match.presetSlug]?.name ?? "",
            ] + match.orderedSides.map(\.displayName)
            return haystack.contains {
                $0.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if matches.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No matches yet", comment: "Empty history title"),
                        systemImage: "clock.arrow.circlepath",
                        description: Text(
                            "Every game you run is saved here with its full timestamped play-by-play, and never expires.",
                            comment: "Empty history description"
                        )
                    )
                } else {
                    list
                }
            }
            .navigationTitle(Text("History", comment: "History title"))
            .toolbar { toolbar }
            .searchable(text: $searchText, prompt: Text("Search matches", comment: "Search prompt"))
            .alert(
                Text("Couldn't create that file", comment: "Export error title"),
                isPresented: .constant(batchError != nil)
            ) {
                Button(String(localized: "OK", comment: "Alert button")) { batchError = nil }
            } message: {
                Text(batchError ?? "")
            }
        }
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(visible) { match in
                if isSelecting {
                    MatchRow(match: match).tag(match.id)
                } else {
                    NavigationLink {
                        MatchReportView(match: match)
                    } label: {
                        MatchRow(match: match)
                    }
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(visible[index]) }
            }
        }
        .environment(\.editMode, .constant(isSelecting ? .active : .inactive))
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(isSelecting
                ? String(localized: "Done", comment: "Dismiss button")
                : String(localized: "Select", comment: "Action")
            ) {
                isSelecting.toggle()
                selection.removeAll()
                batchURL = nil
            }
            .disabled(matches.isEmpty)
        }

        if isSelecting, !selection.isEmpty {
            ToolbarItemGroup(placement: .bottomBar) {
                // §13.5: several matches as one combined PDF or CSV. Tournament organisers ask for
                // this within a week.
                Menu {
                    Button(String(localized: "Combined PDF", comment: "Batch format")) { batchExport(.pdf) }
                    Button(String(localized: "Combined CSV", comment: "Batch format")) { batchExport(.csv) }
                    Button(String(localized: "Combined text", comment: "Batch format")) { batchExport(.text) }
                } label: {
                    Label(
                        String(localized: "Export \(selection.count)", comment: "Batch export action"),
                        systemImage: "square.and.arrow.up.on.square"
                    )
                }

                if let batchURL {
                    ShareLink(item: batchURL) {
                        Label(String(localized: "Share", comment: "Action"), systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func batchExport(_ format: ShareFormat) {
        let chosen = matches.filter { selection.contains($0.id) }
        let models = chosen.map {
            MatchExportBuilder.build($0, options: ExportOptions(includeWatermark: settings.shareWatermark))
        }
        do {
            batchURL = try MatchExporter.batchExport(models, format: format, font: settings.boardFont)
        } catch {
            batchError = error.localizedDescription
        }
    }
}

private struct MatchRow: View {
    var match: Match

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(title)
                if let badge {
                    Text(badge.label)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badge.tint.opacity(0.2), in: .capsule)
                        .foregroundStyle(badge.tint)
                }
                Spacer(minLength: 0)
                Text(match.startedAt, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(scoreLine)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var title: String {
        if let explicit = match.title, !explicit.isEmpty { return explicit }
        return BuiltInCatalog.bySlug[match.presetSlug]?.name
            ?? String(localized: "Match", comment: "Fallback match title")
    }

    /// Status is never conveyed by colour alone (§15) — the badge carries its own text.
    private var badge: (label: String, tint: Color)? {
        switch match.status {
        case .live, .setup:
            (String(localized: "Live", comment: "Match status badge"), Color.green)
        case .abandoned:
            (String(localized: "Abandoned", comment: "Match status badge"), Color.orange)
        case .finished:
            nil
        }
    }

    private var scoreLine: String { MatchSummaryLine.text(for: match) }
}

#Preview {
    HistoryView()
        .environment(AppSettings.shared)
        .modelContainer(try! AppModelContainer.make(inMemory: true))
}
