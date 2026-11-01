import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var baselines: [Baseline]
    @State private var showingBaseline = false
    @AppStorage(StrainGuard.alertsKey) private var strainAlerts = true
    @AppStorage(StrainGuard.capKey) private var capMinutes = StrainGuard.defaultCapMinutes

    var body: some View {
        NavigationStack {
            List {
                Section("Voice") {
                    Button {
                        showingBaseline = true
                    } label: {
                        VStack(alignment: .leading) {
                            Text(baselines.isEmpty ? "Record baseline" : "Re-record baseline")
                            if let b = baselines.first {
                                Text("\(Note(frequency: b.medianHz).name), \(b.date.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section {
                    Stepper("Daily practice cap: \(capMinutes) min", value: $capMinutes, in: 10...120, step: 5)
                    Toggle("Strain alerts", isOn: $strainAlerts)
                } header: {
                    Text("Safety")
                } footer: {
                    Text("Strain alerts compare clarity, steadiness, pitch and loudness against your baseline (or the first minute of a session) and suggest a rest. They're an estimate, not a diagnosis: if you have pain or lasting hoarseness, see a speech-language pathologist.")
                }
                Text("More settings arrive in later sessions.").foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingBaseline) { BaselineView() }
        }
    }
}
