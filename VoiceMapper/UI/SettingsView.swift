import SwiftUI
import SwiftData

struct SettingsView: View {
    @Query private var baselines: [Baseline]
    @State private var showingBaseline = false

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
                Text("More settings arrive in later sessions.").foregroundStyle(.secondary)
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingBaseline) { BaselineView() }
        }
    }
}
