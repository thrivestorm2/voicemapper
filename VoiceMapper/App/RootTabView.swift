import SwiftUI

/// The five main tabs, matching docs/WIREFRAMES.md.
enum AppTab: Hashable {
    case live, range, exercises, history, settings
}

struct RootTabView: View {
    @State private var selection: AppTab = .live

    var body: some View {
        TabView(selection: $selection) {
            LiveView()
                .tabItem { Label("Live", systemImage: "waveform") }
                .tag(AppTab.live)

            RangeTableView()
                .tabItem { Label("Range", systemImage: "music.note.list") }
                .tag(AppTab.range)

            ExercisesView()
                .tabItem { Label("Exercises", systemImage: "figure.mind.and.body") }
                .tag(AppTab.exercises)

            HistoryView()
                .tabItem { Label("History", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
    }
}

#Preview {
    RootTabView()
}
