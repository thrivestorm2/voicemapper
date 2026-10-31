import SwiftUI

struct LiveView: View {
    @Environment(AudioEngine.self) private var audio
    @State private var showingHearYourself = false

    var body: some View {
        NavigationStack {
            // Overlay rather than stack the controls so the placeholder stays
            // centred like the other tabs.
            ContentUnavailableView(
                "Live",
                systemImage: "waveform",
                description: Text("Your pitch and resonance grid will appear here.")
            )
            .overlay(alignment: .bottomLeading) {
                Button {
                    showingHearYourself = true
                } label: {
                    Label("Hear self", systemImage: audio.isHearingYourself ? "headphones.circle.fill" : "headphones")
                }
                .buttonStyle(.bordered)
                .tint(audio.isHearingYourself ? .accentColor : .secondary)
                .accessibilityValue(audio.isHearingYourself ? "On" : "Off")
                .padding()
            }
            .navigationTitle("Live")
            .sheet(isPresented: $showingHearYourself) {
                HearYourselfSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

#Preview {
    LiveView()
        .environment(AudioEngine())
}
