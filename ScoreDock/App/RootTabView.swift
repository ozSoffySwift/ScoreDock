import SwiftUI

/// The five tabs from §3: Play · Library · History · Stats · Settings.
///
/// App chrome uses iOS 26's design language and mirrors fully under RTL. The board does not — see
/// `BoardSpecimenView` and §10.1.
struct RootTabView: View {
    var storeFailure: String?

    var body: some View {
        TabView {
            Tab(String(localized: "Play", comment: "Tab title"), systemImage: "sportscourt.fill") {
                SportPickerView()
            }
            Tab(String(localized: "Library", comment: "Tab title"), systemImage: "person.2.fill") {
                LibraryView()
            }
            Tab(String(localized: "History", comment: "Tab title"), systemImage: "clock.arrow.circlepath") {
                HistoryView()
            }
            Tab(String(localized: "Stats", comment: "Tab title"), systemImage: "chart.bar.fill") {
                StatsView()
            }
            Tab(String(localized: "Settings", comment: "Tab title"), systemImage: "gearshape.fill") {
                SettingsView()
            }
        }
        .safeAreaInset(edge: .top) {
            if let storeFailure {
                StoreFailureBanner(message: storeFailure)
            }
        }
    }
}

/// Shown when the persistent store could not be opened and the app fell back to memory.
private struct StoreFailureBanner: View {
    var message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Saved data is unavailable", comment: "Store failure banner title")
                    .font(.footnote.weight(.semibold))
                Text("Matches played now will not be kept. \(message)", comment: "Store failure banner detail")
                    .font(.caption)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.25))
    }
}

#Preview {
    RootTabView()
        .environment(AppSettings())
}
