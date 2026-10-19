import SwiftUI
import UIKit

/// Picks a format and hands the file to the system share sheet (§13.5, §13.6).
///
/// The sheet is explicit about what is in the file, because some of these matches involve children
/// and "the operator knows what they typed" is not the same as making it visible at the moment they
/// send it.
struct MatchShareSheet: View {
    @Bindable var match: Match

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var format: ShareFormat = .image
    @State private var aspect: ShareCardAspect = .portrait
    @State private var anonymise = false
    @State private var includeTimeline = true
    @State private var exportURL: URL?
    @State private var exportError: String?

    private var options: ExportOptions {
        ExportOptions(
            anonymisePlayers: anonymise,
            includeWatermark: settings.shareWatermark,
            includeTimeline: includeTimeline
        )
    }

    private var model: MatchExportModel {
        MatchExportBuilder.build(match, options: options)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker(String(localized: "Format", comment: "Share picker"), selection: $format) {
                        ForEach(ShareFormat.allCases) { candidate in
                            Label(candidate.displayName, systemImage: candidate.symbolName)
                                .tag(candidate)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Share as", comment: "Share section")
                } footer: {
                    Text(format.detail)
                }

                if format == .image {
                    Section {
                        Picker(String(localized: "Shape", comment: "Share picker"), selection: $aspect) {
                            ForEach(ShareCardAspect.allCases) { candidate in
                                Text(candidate.displayName).tag(candidate)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if format == .pdf || format == .text || format == .csv {
                    Section {
                        Toggle(
                            String(localized: "Include play-by-play", comment: "Share option"),
                            isOn: $includeTimeline
                        )
                    } footer: {
                        // §19.2 leaves the default open; full detail suits a referee, a group chat
                        // usually wants the short version.
                        Text(
                            "Full detail is right for a league record. For a group chat, the summary alone usually reads better.",
                            comment: "Timeline option footer"
                        )
                    }
                }

                Section {
                    Toggle(String(localized: "Anonymise names", comment: "Share option"), isOn: $anonymise)
                } footer: {
                    Text(
                        "Replaces names with initials and removes photos and crests. Emoji is the safest mark for anything shared publicly.",
                        comment: "Anonymise footer"
                    )
                }

                Section {
                    ForEach(includedItems, id: \.self) { item in
                        Label(item, systemImage: "checkmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let size = formattedSize {
                        LabeledContent(String(localized: "File size", comment: "Share detail"), value: size)
                            .font(.footnote)
                    }
                } header: {
                    Text("What's included", comment: "Share section")
                } footer: {
                    Text(
                        "This match stays on your device. Only the file you share leaves it, to the destination you pick.",
                        comment: "Privacy footer"
                    )
                }

                Section {
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label(
                                String(localized: "Share", comment: "Action"),
                                systemImage: "square.and.arrow.up"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }

                    if format == .pdf || format == .image {
                        // Clubs still pin paper results to a wall (§13.5).
                        Button {
                            printExport()
                        } label: {
                            Label(String(localized: "Print", comment: "Action"), systemImage: "printer")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
            }
            .navigationTitle(Text("Share match", comment: "Share sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done", comment: "Dismiss button")) { dismiss() }
                }
            }
            .task(id: exportKey) { await regenerate() }
            .alert(
                Text("Couldn't create that file", comment: "Export error title"),
                isPresented: .constant(exportError != nil)
            ) {
                Button(String(localized: "OK", comment: "Alert button")) { exportError = nil }
            } message: {
                Text(exportError ?? "")
            }
        }
    }

    /// Any change that invalidates the generated file.
    private var exportKey: String {
        "\(format.rawValue)-\(aspect.rawValue)-\(anonymise)-\(includeTimeline)-\(settings.shareWatermark)"
    }

    private func regenerate() async {
        exportURL = nil
        do {
            exportURL = try MatchExporter.export(
                model,
                format: format,
                aspect: aspect,
                font: settings.boardFont
            )
        } catch {
            exportError = error.localizedDescription
        }
    }

    private var includedItems: [String] {
        var items = [
            String(localized: "Final score and per-period breakdown", comment: "Share contents"),
        ]
        if !anonymise {
            items.append(String(localized: "Team and player names", comment: "Share contents"))
            if match.venue?.isEmpty == false {
                items.append(String(localized: "Venue", comment: "Share contents"))
            }
            if format.carriesImages, match.orderedSides.contains(where: { $0.image != nil }) {
                items.append(String(localized: "Crests and photos", comment: "Share contents"))
            }
        }
        if includeTimeline || format == .image || format == .sdgame {
            items.append(String(localized: "Timestamped play-by-play", comment: "Share contents"))
        }
        return items
    }

    private var formattedSize: String? {
        guard let bytes = MatchExporter.estimatedSize(
            model, format: format, aspect: aspect, font: settings.boardFont
        ) else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func printExport() {
        guard let exportURL, UIPrintInteractionController.canPrint(exportURL) else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = model.title
        controller.printInfo = info
        controller.printingItem = exportURL
        controller.present(animated: true)
    }
}
