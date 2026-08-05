import SwiftUI

/// Credits a score to a player (§4.2).
///
/// **Attribution is never mandatory.** A mis-tap under pressure is worse than missing data, so
/// "No credit" is a full-width button at the top of the sheet — the fastest thing to hit — and it
/// records the points exactly as an unattributed score. A scrappy goal nobody claims is a real
/// thing that happens.
struct AttributionSheet: View {
    var sideName: String
    var colorHex: String
    var points: Int
    var roster: [Player]
    var onSelect: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Button {
                        finish(nil)
                    } label: {
                        Label(
                            String(localized: "No credit", comment: "Attribution escape"),
                            systemImage: "person.slash"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)

                    if roster.isEmpty {
                        ContentUnavailableView {
                            Label(
                                String(localized: "No roster", comment: "Empty roster title"),
                                systemImage: "person.2"
                            )
                        } description: {
                            Text(
                                "Link this side to a saved team in Setup to credit points to players.",
                                comment: "Empty roster description"
                            )
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(roster) { player in
                                Button {
                                    finish(player.id)
                                } label: {
                                    VStack(spacing: 8) {
                                        IdentityMarkView(player, size: 48)
                                        Text(player.displayName)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.7)
                                        if let jersey = player.defaultJersey, !jersey.isEmpty {
                                            Text("#\(jersey)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    // Large targets: the operator is glancing down mid-play (§4.2a).
                                    .frame(maxWidth: .infinity, minHeight: 110)
                                }
                                .buttonStyle(.bordered)
                                .tint(Color(hex: colorHex))
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(Text("\(sideName) +\(points)", comment: "Attribution title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Dialog cancel")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func finish(_ playerID: UUID?) {
        onSelect(playerID)
        dismiss()
    }
}

/// A pending score awaiting attribution.
struct PendingScore: Identifiable, Equatable {
    var id = UUID()
    var slotIndex: Int
    var points: Int
}
