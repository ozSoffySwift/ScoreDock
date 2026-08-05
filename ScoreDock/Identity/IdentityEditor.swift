import PhotosUI
import SwiftUI

/// Edits a record's identity mark (§7.1a).
///
/// Both an emoji and an image can be set at once; `preferredMark` decides which one represents the
/// record, rather than the app guessing. Neither is required — coloured initials are always a valid
/// terminal fallback, so this control can be ignored entirely.
struct IdentityEditor: View {
    @Binding var emoji: String?
    @Binding var imageData: Data?
    @Binding var mark: IdentityMark
    var colorHex: String?
    var displayName: String

    @State private var photoItem: PhotosPickerItem?
    @State private var showingEmojiPicker = false
    @State private var importError: String?
    @State private var isImporting = false

    private var preview: ResolvedMark {
        PreviewBearer(displayName: displayName, emoji: emoji, image: imageData, mark: mark, colorHex: colorHex)
            .resolvedMark
    }

    var body: some View {
        Section {
            markRow
                // **These belong on the row, not on the `Section`.** A `Section` is not a view:
                // modifiers applied to one are pushed into its rows or dropped, and a `.sheet` there
                // resolved against the *enclosing* sheet — so tapping "Add emoji" inside the player
                // editor dismissed the editor instead of presenting the picker, discarding the
                // half-filled player on the way out.
                .sheet(isPresented: $showingEmojiPicker) {
                    EmojiQuickPicker(emoji: $emoji, mark: $mark)
                }
                .onChange(of: photoItem) { _, item in
                    guard let item else { return }
                    Task { await load(item) }
                }
                .alert(
                    Text("Couldn't use that image", comment: "Import error title"),
                    isPresented: .constant(importError != nil)
                ) {
                    Button(String(localized: "OK", comment: "Alert button")) { importError = nil }
                } message: {
                    Text(importError ?? "")
                }

            // Only offered when there is genuinely a choice to make.
            if emoji != nil, imageData != nil {
                Picker(String(localized: "Show", comment: "Preferred mark picker"), selection: $mark) {
                    Text("Photo", comment: "Mark option").tag(IdentityMark.image)
                    Text("Emoji", comment: "Mark option").tag(IdentityMark.emoji)
                    Text("Initials", comment: "Mark option").tag(IdentityMark.initials)
                }
                .pickerStyle(.segmented)
            }

            if emoji != nil || imageData != nil {
                Button(role: .destructive) {
                    emoji = nil
                    imageData = nil
                    mark = .initials
                } label: {
                    Label(String(localized: "Remove mark", comment: "Identity action"), systemImage: "trash")
                }
                .font(.subheadline)
            }
        } header: {
            Text("Identity", comment: "Editor section")
        } footer: {
            Text(
                "Emoji reads perfectly in shared text and on a projector. A photo carries a real crest. You can set both and choose which one shows.",
                comment: "Identity footer"
            )
        }
    }

    /// The mark and its two actions, as one row — and the view every presentation hangs off.
    private var markRow: some View {
        HStack(spacing: 16) {
            IdentityMarkView(mark: preview, colorHex: colorHex, size: 72)
                .overlay(alignment: .bottomTrailing) {
                    if isImporting {
                        ProgressView().controlSize(.small)
                    }
                }

            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showingEmojiPicker = true
                } label: {
                    Label(
                        emoji == nil
                            ? String(localized: "Add emoji", comment: "Identity action")
                            : String(localized: "Change emoji", comment: "Identity action"),
                        systemImage: "face.smiling"
                    )
                }

                // Resolved before the call: `PhotosPicker`'s label builder is `@Sendable`, and
                // reading main-actor state from inside it is a concurrency warning even though
                // the view itself never leaves the main actor.
                let photoLabel = imageData == nil
                    ? String(localized: "Add photo", comment: "Identity action")
                    : String(localized: "Change photo", comment: "Identity action")

                PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                    Label(photoLabel, systemImage: "photo")
                }
            }
            .buttonStyle(.borderless)
            .font(.subheadline)
        }
        .padding(.vertical, 4)
    }

    private func load(_ item: PhotosPickerItem) async {
        isImporting = true
        defer { isImporting = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                importError = IdentityImage.ImportError.unreadable.localizedDescription
                return
            }
            // Re-encoded here, which is what removes GPS and every other tag (§7.1a).
            imageData = try IdentityImage.normalize(raw)
            mark = .image
        } catch {
            importError = error.localizedDescription
        }
    }
}

/// A curated grid above the system keyboard.
///
/// §7.1a is specific about this: hunting for 🥍 in the standard picker is miserable, and the whole
/// point of an emoji mark is that it takes one tap.
struct EmojiQuickPicker: View {
    @Binding var emoji: String?
    @Binding var mark: IdentityMark
    @Environment(\.dismiss) private var dismiss
    @State private var custom = ""

    private static let sports = "⚽️🏀🏈⚾️🥎🎾🏐🏉🥏🏓🏸🏒🏑🥍🏏🥅⛳️🥊🥋🤼🤸⛹️🤾🏌️🏇🏄🏊🤽🚴🛹⛸️🎿🏂🏋️"
    private static let mascots = "🐺🦅🦁🐯🐻🐗🦌🐴🦄🐝🦂🐍🦖🦈🐬🐳🦉🦇🐉🦍🐘🦏🐆🦓🐂🐎🐕🐈🐓🦚🦜🐇🦔🐊"
    private static let symbols = "🏆🥇🔥⚡️⭐️💥🎯🚀👑💎🛡️🎖️🧨☄️🌟🍀"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField(
                        String(localized: "Any emoji", comment: "Custom emoji field"),
                        text: $custom
                    )
                    .font(.title2)
                    .onChange(of: custom) { _, value in
                        // Validated as a single grapheme cluster so this cannot become a second
                        // name field (§7.1a).
                        if let valid = EmojiInput.validated(value) {
                            choose(valid)
                        }
                    }
                } footer: {
                    Text("Or type any emoji from the keyboard.", comment: "Custom emoji footer")
                }

                grid(String(localized: "Sports", comment: "Emoji section"), Self.sports)
                grid(String(localized: "Mascots", comment: "Emoji section"), Self.mascots)
                grid(String(localized: "Symbols", comment: "Emoji section"), Self.symbols)
            }
            .navigationTitle(Text("Choose emoji", comment: "Emoji picker title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Dialog cancel")) { dismiss() }
                }
            }
        }
    }

    private func grid(_ title: String, _ source: String) -> some View {
        Section(title) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                ForEach(Array(source.map(String.init)), id: \.self) { candidate in
                    Button {
                        choose(candidate)
                    } label: {
                        Text(candidate)
                            .font(.system(size: 30))
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func choose(_ value: String) {
        emoji = value
        mark = .emoji
        dismiss()
    }
}

/// Lets the editor resolve a preview without owning a model object.
private struct PreviewBearer: IdentityBearing {
    var displayName: String
    var emoji: String?
    var image: Data?
    var mark: IdentityMark
    var colorHex: String?
    var identityColorHex: String? { colorHex }
}
