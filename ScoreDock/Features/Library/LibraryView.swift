import SwiftData
import SwiftUI

/// Players · Teams · My Games (§3).
///
/// Players and Teams CRUD, rosters and identity marks are M3 deliverables. My Games is live now
/// because "Duplicate and edit" already produces `UserGamePreset` rows, and a saved game with
/// nowhere to appear would read as data loss.
struct LibraryView: View {
    @Query(sort: \Player.name) private var players: [Player]
    @Query(sort: \Team.name) private var teams: [Team]
    @Query(sort: \UserGamePreset.sortIndex) private var myGames: [UserGamePreset]

    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        PlayersView()
                    } label: {
                        LabeledContent {
                            Text("\(players.count { !$0.isArchived })")
                        } label: {
                            Label(String(localized: "Players", comment: "Library section"), systemImage: "person.fill")
                        }
                    }

                    NavigationLink {
                        TeamsView()
                    } label: {
                        LabeledContent {
                            Text("\(teams.count { !$0.isArchived })")
                        } label: {
                            Label(String(localized: "Teams", comment: "Library section"), systemImage: "person.2.fill")
                        }
                    }
                } footer: {
                    Text(
                        "Saved players and teams are what a scoreboard website can't give you — they keep their identity and build up stats across every match.",
                        comment: "Library footer"
                    )
                }

                Section(String(localized: "My Games", comment: "Library section")) {
                    if myGames.isEmpty {
                        Text(
                            "Games you save from Setup, or duplicate from a built-in, appear here.",
                            comment: "Empty My Games"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    } else {
                        ForEach(myGames) { game in
                            HStack(spacing: 12) {
                                Text(game.emoji).font(.title3).frame(width: 30)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(game.name)
                                    if let slug = game.derivedFromSlug,
                                       let origin = BuiltInCatalog.bySlug[slug] {
                                        Text("Based on \(origin.name)", comment: "Derived preset subtitle")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets { context.delete(myGames[index]) }
                        }
                    }
                }
            }
            .navigationTitle(Text("Library", comment: "Library title"))
        }
    }

}

#Preview {
    LibraryView()
        .modelContainer(try! AppModelContainer.make(inMemory: true))
}
