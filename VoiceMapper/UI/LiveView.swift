import SwiftUI

struct LiveView: View {
    @Environment(AudioEngine.self) private var audio
    @State private var showingHearYourself = false

    private var isCapturing: Bool { audio.isListening || audio.isHearingYourself }

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
                VStack(spacing: 20) {
                    PitchLabel(reading: audio.pitch, isListening: isCapturing)
                    ResonanceMeter(reading: audio.resonance, isListening: isCapturing)
                        .padding(.horizontal, 24)
                }
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
    @AppStorage(GoalRange.lowKey) private var goalLow = 0
    @AppStorage(GoalRange.highKey) private var goalHigh = 0
    let reading: PitchReading?
    let isListening: Bool

    var body: some View {
        VStack(spacing: 2) {
            if let reading {
                Text(reading.note.name)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(noteColor(for: reading))
                Text("\(Int(reading.frequency.rounded())) Hz")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if let goal = GoalRange(low: goalLow, high: goalHigh) {
                    Text(goalCaption(goal.direction(of: reading.frequency)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
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

extension PitchLabel {
    /// Red when far from the goal range through yellow to green inside it; the
    /// caption below says the same in words.
    fileprivate func noteColor(for reading: PitchReading) -> Color {
        guard let goal = GoalRange(low: goalLow, high: goalHigh) else { return .primary }
        let closeness = goal.closeness(of: reading.frequency)
        // Hue 0 is red, 1/3 is green.
        return Color(hue: closeness / 3, saturation: 0.85, brightness: 0.85)
    }

    fileprivate func goalCaption(_ direction: GoalRange.Direction?) -> String {
        switch direction {
        case nil: "In your goal range"
        case .higher: "Goal is higher"
        case .lower: "Goal is lower"
        }
    }
}

#Preview {
    LiveView()
        .environment(AudioEngine())
}
