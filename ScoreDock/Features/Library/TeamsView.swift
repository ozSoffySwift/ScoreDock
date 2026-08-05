import SwiftData
import SwiftUI

/// Saved teams and their rosters (§3, §7.1a).
///
/// The app ships **no** real-world team names, crests or league branding — users supply their own
/// (§16). That keeps it clear of trademark exposure and keeps App Review uneventful.
struct TeamsView: View {
    @Query(sort: \Team.name) private var teams: [Team]
    @Environment(\.modelContext) private var context

    @State private var searchText = ""
    @State private var showsArchived = false
    @State private var editing: Team?

    private var visible: [Team] {
        teams
            .filter { showsArchived || !$0.isArchived }
            .filter {
                searchText.isEmpty
                    || $0.name.range(of: searchText, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
    }

    var body: some View {
        Group {
            if teams.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: "No teams yet", comment: "Empty teams title"),
                        systemImage: "person.2.fill"
                    )
                } description: {
                    Text(
                        "Save a team once with its colours and crest, then pick it in Setup instead of typing names every match.",
                        comment: "Empty teams description"
                    )
                } actions: {
                    Button(String(localized: "Add team", comment: "Action")) { addTeam() }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(visible) { team in
                        Button {
                            editing = team
                        } label: {
                            TeamRow(team: team)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button {
                                team.isArchived.toggle()
                            } label: {
                                Label(
                                    team.isArchived
                                        ? String(localized: "Restore", comment: "Swipe action")
                                        : String(localized: "Archive", comment: "Swipe action"),
                                    systemImage: team.isArchived ? "arrow.uturn.backward" : "archivebox"
                                )
                            }
                            .tint(.orange)

                            Button(role: .destructive) {
                                context.delete(team)
                            } label: {
                                Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash")
                            }
                        }
                    }

                    if teams.contains(where: \.isArchived) {
                        Toggle(
                            String(localized: "Show archived", comment: "Teams filter"),
                            isOn: $showsArchived
                        )
                        .font(.footnote)
                    }
                }
                .searchable(text: $searchText, prompt: Text("Search teams", comment: "Search prompt"))
            }
        }
        .navigationTitle(Text("Teams", comment: "Library section"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    addTeam()
                } label: {
                    Label(String(localized: "Add team", comment: "Action"), systemImage: "plus")
                }
            }
        }
        // See the matching note in `PlayersView`: a swipe-dismissed sheet must not leave an empty
        // record behind.
        .sheet(item: $editing, onDismiss: discardEmptyTeams) { team in
            TeamEditorView(team: team)
        }
    }

    private func addTeam() {
        let team = Team()
        context.insert(team)
        editing = team
    }

    private func discardEmptyTeams() {
        for team in teams
        where team.name.trimmingCharacters(in: .whitespaces).isEmpty
            && team.shortName.isEmpty
            && team.emoji == nil
            && team.image == nil
            && (team.roster ?? []).isEmpty {
            context.delete(team)
        }
    }
}

struct TeamRow: View {
    var team: Team

    var body: some View {
        HStack(spacing: 12) {
            IdentityMarkView(team, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(team.name.isEmpty
                    ? String(localized: "Unnamed team", comment: "Placeholder name")
                    : team.name)
                let count = team.activePlayers.count
                if count > 0 {
                    Text("\(count) players", comment: "Roster count")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if team.isArchived {
                Text("Archived", comment: "Archived badge")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.secondary.opacity(0.15), in: .capsule)
            }
        }
        .contentShape(.rect)
    }
}

struct TeamEditorView: View {
    @Bindable var team: Team
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Player.name) private var allPlayers: [Player]

    @State private var showingAddPlayer = false

    private var roster: [TeamMembership] {
        (team.roster ?? []).sorted { lhs, rhs in
            switch (Int(lhs.jersey ?? ""), Int(rhs.jersey ?? "")) {
            case let (l?, r?): return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return (lhs.player?.displayName ?? "") < (rhs.player?.displayName ?? "")
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name", comment: "Field"), text: $team.name)
                        .textInputAutocapitalization(.words)
                    TextField(String(localized: "Short name", comment: "Field"), text: $team.shortName)
                        .textInputAutocapitalization(.characters)
                } footer: {
                    // §10.2: Hebrew glyphs run wider than Latin at the same point size, so a
                    // 4-character short name may still not fit a narrow board.
                    Text(
                        "Four characters or fewer for narrow boards. If it doesn't fit, an emoji or crest works in its place.",
                        comment: "Short name footer"
                    )
                }

                IdentityEditor(
                    emoji: $team.emoji,
                    imageData: $team.image,
                    mark: Binding(get: { team.mark }, set: { team.mark = $0 }),
                    colorHex: team.primaryColorHex,
                    displayName: team.name
                )

                Section(String(localized: "Colours", comment: "Editor section")) {
                    ColorPicker(
                        String(localized: "Primary", comment: "Field"),
                        selection: Binding(
                            get: { Color(hex: team.primaryColorHex) },
                            set: { team.primaryColorHex = $0.resolvedHex }
                        ),
                        supportsOpacity: false
                    )
                    ColorPicker(
                        String(localized: "Secondary", comment: "Field"),
                        selection: Binding(
                            get: { Color(hex: team.secondaryColorHex) },
                            set: { team.secondaryColorHex = $0.resolvedHex }
                        ),
                        supportsOpacity: false
                    )
                }

                Section {
                    if roster.isEmpty {
                        Text("No players on this roster yet.", comment: "Empty roster")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(roster) { membership in
                            RosterRow(membership: membership)
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(roster[index]) }
                        }
                    }

                    Button {
                        showingAddPlayer = true
                    } label: {
                        Label(String(localized: "Add player", comment: "Action"), systemImage: "person.badge.plus")
                    }
                    .disabled(availablePlayers.isEmpty)
                } header: {
                    Text("Roster", comment: "Editor section")
                } footer: {
                    if availablePlayers.isEmpty, roster.isEmpty {
                        Text("Create players in Library → Players first.", comment: "Roster hint")
                    } else {
                        Text(
                            "A player can be on several teams — club players and coaches with multiple age groups usually are.",
                            comment: "Roster footer"
                        )
                    }
                }
            }
            .navigationTitle(Text("Team", comment: "Editor title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Done", comment: "Dismiss button")) {
                        if team.name.trimmingCharacters(in: .whitespaces).isEmpty {
                            context.delete(team)
                        } else if team.shortName.isEmpty {
                            team.shortName = String(team.name.prefix(4)).uppercased()
                        }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingAddPlayer) {
                AddToRosterView(candidates: availablePlayers) { player in
                    let membership = TeamMembership(player: player, team: team, jersey: player.defaultJersey)
                    context.insert(membership)
                }
            }
        }
    }

    private var availablePlayers: [Player] {
        let existing = Set((team.roster ?? []).compactMap { $0.player?.id })
        return allPlayers.filter { !$0.isArchived && !existing.contains($0.id) }
    }
}

private struct RosterRow: View {
    @Bindable var membership: TeamMembership

    var body: some View {
        HStack(spacing: 12) {
            if let player = membership.player {
                IdentityMarkView(player, size: 32)
                Text(player.displayName)
            } else {
                Text("Removed player", comment: "Missing roster player").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            TextField(
                String(localized: "#", comment: "Jersey field"),
                text: Binding($membership.jersey, replacingNilWith: "")
            )
            .frame(width: 48)
            .multilineTextAlignment(.trailing)
            .font(.callout.monospacedDigit())
        }
    }
}

private struct AddToRosterView: View {
    var candidates: [Player]
    var onSelect: (Player) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(candidates) { player in
                Button {
                    onSelect(player)
                    dismiss()
                } label: {
                    PlayerRow(player: player)
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(Text("Add player", comment: "Sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Dialog cancel")) { dismiss() }
                }
            }
        }
    }
}
