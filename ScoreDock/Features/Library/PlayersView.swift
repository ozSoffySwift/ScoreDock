import SwiftData
import SwiftUI

/// Saved players (§3, §7.1a).
///
/// Persistence of players is one of the two things a stateless website cannot offer (§1.1), so this
/// is a headline feature rather than a utility screen.
struct PlayersView: View {
    @Query(sort: \Player.name) private var players: [Player]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var showsArchived = false
    @State private var editing: Player?

    private var visible: [Player] {
        players
            .filter { showsArchived || !$0.isArchived }
            .filter {
                searchText.isEmpty
                    || $0.name.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || ($0.nickname ?? "").range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
    }

    var body: some View {
        Group {
            if players.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: "No players yet", comment: "Empty players title"),
                        systemImage: "person.fill"
                    )
                } description: {
                    Text(
                        "Add the people you score for. They keep their photo or emoji, and build up stats across every match.",
                        comment: "Empty players description"
                    )
                } actions: {
                    Button(String(localized: "Add player", comment: "Action")) { addPlayer() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(visible) { player in
                        Button {
                            editing = player
                        } label: {
                            PlayerRow(player: player)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            // Archive rather than delete: history keeps its link to the person,
                            // and a season's stats do not vanish because someone left the club.
                            Button {
                                player.isArchived.toggle()
                            } label: {
                                Label(
                                    player.isArchived
                                        ? String(localized: "Restore", comment: "Swipe action")
                                        : String(localized: "Archive", comment: "Swipe action"),
                                    systemImage: player.isArchived ? "arrow.uturn.backward" : "archivebox"
                                )
                            }
                            .tint(.orange)

                            Button(role: .destructive) {
                                context.delete(player)
                            } label: {
                                Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash")
                            }
                        }
                    }

                    if players.contains(where: \.isArchived) {
                        Toggle(
                            String(localized: "Show archived", comment: "Players filter"),
                            isOn: $showsArchived
                        )
                        .font(.footnote)
                    }
                }
                .searchable(text: $searchText, prompt: Text("Search players", comment: "Search prompt"))
            }
        }
        .navigationTitle(Text("Players", comment: "Library section"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addPlayer()
                } label: {
                    Label(String(localized: "Add player", comment: "Action"), systemImage: "plus")
                }
            }
        }
        // Cleanup runs on `onDismiss` rather than in the editor's Done button, because the sheet can
        // also be swiped away — which otherwise leaves an "Unnamed player" row behind.
        .sheet(item: $editing, onDismiss: discardEmptyPlayers) { player in
            PlayerEditorView(player: player)
        }
    }

    private func addPlayer() {
        let player = Player()
        context.insert(player)
        editing = player
    }

    /// Removes records the user opened and never filled in. Deliberately strict about "empty": a
    /// player with only an emoji is a real, intentional record.
    private func discardEmptyPlayers() {
        for player in players
        where player.name.trimmingCharacters(in: .whitespaces).isEmpty
            && (player.nickname ?? "").isEmpty
            && player.emoji == nil
            && player.image == nil
            && (player.defaultJersey ?? "").isEmpty
            && (player.notes ?? "").isEmpty {
            context.delete(player)
        }
    }
}

struct PlayerRow: View {
    var player: Player

    var body: some View {
        HStack(spacing: 12) {
            IdentityMarkView(player, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.displayName.isEmpty
                    ? String(localized: "Unnamed player", comment: "Placeholder name")
                    : player.displayName)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if player.isArchived {
                Text("Archived", comment: "Archived badge")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: .capsule)
            }
        }
        .contentShape(.rect)
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let jersey = player.defaultJersey, !jersey.isEmpty { parts.append("#\(jersey)") }
        let teams = (player.memberships ?? []).compactMap { $0.team?.name }
        parts.append(contentsOf: teams)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

struct PlayerEditorView: View {
    @Bindable var player: Player
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name", comment: "Field"), text: $player.name)
                        .textInputAutocapitalization(.words)
                    TextField(
                        String(localized: "Nickname", comment: "Field"),
                        text: Binding($player.nickname, replacingNilWith: "")
                    )
                    .textInputAutocapitalization(.words)
                } footer: {
                    Text("The nickname is what shows on the board — it is shorter, and it is what the crowd shouts.", comment: "Nickname footer")
                }

                IdentityEditor(
                    emoji: $player.emoji,
                    imageData: $player.image,
                    mark: Binding(get: { player.mark }, set: { player.mark = $0 }),
                    colorHex: player.colorHex,
                    displayName: player.displayName
                )

                Section {
                    TextField(
                        String(localized: "Default jersey", comment: "Field"),
                        text: Binding($player.defaultJersey, replacingNilWith: "")
                    )
                    ColorPicker(
                        String(localized: "Colour", comment: "Field"),
                        selection: Binding(
                            get: { Color(hex: player.colorHex ?? "#1E88E5") },
                            set: { player.colorHex = $0.resolvedHex }
                        ),
                        supportsOpacity: false
                    )
                }

                Section {
                    TextField(
                        String(localized: "Notes", comment: "Field"),
                        text: Binding($player.notes, replacingNilWith: ""),
                        axis: .vertical
                    )
                    .lineLimit(3 ... 6)
                }

                if !(player.memberships ?? []).isEmpty {
                    Section(String(localized: "Teams", comment: "Editor section")) {
                        ForEach(player.memberships ?? []) { membership in
                            LabeledContent(membership.team?.name ?? "—") {
                                Text(membership.jersey.map { "#\($0)" } ?? "")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(Text("Player", comment: "Editor title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Dismiss button")) {
                        // A player who was added and never named is noise, not data.
                        if player.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            context.delete(player)
                        }
                        dismiss()
                    }
                }
            }
        }
    }
}

extension Binding where Value == String {
    /// Bridges an optional stored property to a `TextField`, treating empty as nil so a cleared
    /// field does not persist an empty string.
    init(_ source: Binding<String?>, replacingNilWith placeholder: String) {
        self.init(
            get: { source.wrappedValue ?? placeholder },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
