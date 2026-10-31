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
            .overlay(alignment: .top) {
                PitchLabel(reading: audio.pitch, isListening: audio.isListening || audio.isHearingYourself)
                    .padding(.top, 8)
            }
            .overlay(alignment: .bottom) {
                HStack {
                    Button {
                        Task { await audio.setListening(!audio.isListening) }
                    } label: {
                        Label(audio.isListening ? "Stop" : "Speak",
                              systemImage: audio.isListening ? "mic.fill" : "mic")
                    }
                    .buttonStyle(.bordered)
                    .tint(audio.isListening ? .accentColor : .secondary)
                    .accessibilityValue(audio.isListening ? "On" : "Off")

                    Button {
                        showingHearYourself = true
                    } label: {
                        Label("Listen", systemImage: audio.isHearingYourself ? "headphones.circle.fill" : "headphones")
                    }
                    .buttonStyle(.bordered)
                    .tint(audio.isHearingYourself ? .accentColor : .secondary)
                    .accessibilityValue(audio.isHearingYourself ? "On" : "Off")
                }
                .padding()
            }
            .safeAreaInset(edge: .top) {
                if audio.showsBluetoothBanner {
                    BluetoothBanner { audio.dismissBluetoothBanner() }
                        .padding(.horizontal)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.default, value: audio.showsBluetoothBanner)
            .navigationTitle("Live")
            .sheet(isPresented: $showingHearYourself) {
                HearYourselfSheet()
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// Note name and frequency, e.g. "G4  196 Hz". No needle or cents, by design.
private struct PitchLabel: View {
    let reading: PitchReading?
    let isListening: Bool

    var body: some View {
        VStack(spacing: 2) {
            if let reading {
                Text(reading.note.name)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                Text("\(Int(reading.frequency.rounded())) Hz")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Text("–")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(.tertiary)
                Text(isListening ? "Say or hum a note" : "Tap Speak to start")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    LiveView()
        .environment(AudioEngine())
}
