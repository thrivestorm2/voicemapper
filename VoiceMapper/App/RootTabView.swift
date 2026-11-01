import SwiftUI

/// The five main tabs, matching docs/WIREFRAMES.md.
enum AppTab: Hashable {
    case live, range, exercises, history, settings
}

struct RootTabView: View {
    @Environment(StrainGuard.self) private var strain
    @Environment(SessionRecorder.self) private var recorder
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
        .overlay { SafetyAlertOverlay() }
        .alert("Keep this session?", isPresented: noisyPromptShown, presenting: recorder.noisySession) { session in
            Button("Keep") { recorder.noisySession = nil }
            Button("Delete", role: .destructive) { recorder.delete(session) }
        } message: { session in
            Text("About \(Int(((session.noisyShare ?? 0) * 100).rounded()))% of it had loud background noise, so its readings may be off.")
        }
        .animation(.default, value: strain.alert)
    }

    private var noisyPromptShown: Binding<Bool> {
        Binding(get: { recorder.noisySession != nil && strain.alert == nil },
                set: { if !$0 { recorder.noisySession = nil } })
    }
}
