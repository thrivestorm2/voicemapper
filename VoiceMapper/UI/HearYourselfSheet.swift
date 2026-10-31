import MediaPlayer
import SwiftUI

/// Hear-yourself controls, matching docs/WIREFRAMES.md §4.
struct HearYourselfSheet: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(\.openURL) private var openURL
    @State private var showingDelayTips = false

    var body: some View {
        @Bindable var audio = audio

        NavigationStack {
            Form {
                Section {
                    Toggle("Hear yourself", isOn: Binding(
                        get: { audio.isHearingYourself },
                        set: { on in Task { await audio.setHearYourself(on) } }
                    ))
                    .disabled(audio.micPermission == .denied)

                    if audio.micPermission == .denied {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Microphone access is off. VoiceMapper needs it to hear your voice.")
                            Button("Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    openURL(url)
                                }
                            }
                        }
                        .font(.footnote)
                    } else if !audio.headphonesConnected {
                        Label("Connect headphones to hear yourself.", systemImage: "headphones")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let error = audio.lastError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Picker("Microphone", selection: $audio.selectedMicrophoneID) {
                        Text("Automatic").tag(String?.none)
                        ForEach(audio.microphones) { mic in
                            Text(mic.name).tag(Optional(mic.id))
                        }
                    }
                    if let active = audio.activeMicrophoneName {
                        LabeledContent("Using", value: active)
                            .foregroundStyle(.secondary)
                    }
                    if let latency = audio.deviceLatencyMs {
                        let level = DelayLevel(ms: latency)
                        LabeledContent {
                            HStack(spacing: 6) {
                                Circle().fill(level.color).frame(width: 8, height: 8)
                                Text("\(level.label) · \(Int(latency.rounded())) ms").monospacedDigit()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Device delay")
                                Button {
                                    showingDelayTips = true
                                } label: {
                                    Image(systemName: "info.circle")
                                }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Tips to reduce delay")
                                .popover(isPresented: $showingDelayTips) {
                                    DelayTips()
                                        .presentationCompactAdaptation(.popover)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if audio.microphones.contains(where: { $0.id == audio.selectedMicrophoneID && $0.isBluetooth }) {
                            Label("You've chosen a Bluetooth mic. Readings will be less accurate.", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                        Text("The iPhone mic is recommended. It records your voice at full quality with no wireless delay, so pitch and resonance readings are as accurate as possible. Bluetooth mics (like AirPods) compress your voice and cut detail that resonance depends on. A wired mic is also fine.")
                        Text("Automatic always uses the iPhone mic.")
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Headphone volume")
                            Spacer()
                            Text(audio.systemVolume, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        SystemVolumeSlider(tint: audio.isAboveSafeVolume ? .systemOrange : nil)
                            .frame(height: 34)
                    }
                    if audio.isAboveSafeVolume {
                        Label("Above the safe-listening level. Long sessions this loud can harm your hearing.",
                              systemImage: "ear.trianglebadge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Voice level")
                            Spacer()
                            Text(audio.voiceLevel, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $audio.voiceLevel, in: 0...1)
                    }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Delay")
                            Spacer()
                            Text("\(Int(audio.delayMs)) ms")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $audio.delayMs, in: 0...AudioEngine.maxDelayMs, step: 10)
                    }
                } footer: {
                    Text("Headphone volume is the same as your headphones' own volume buttons or Digital Crown. Voice level sets how loud your voice is and is remembered for each mic. Delay is for delayed-feedback drills; leave it at 0 ms for normal practice.")
                }
            }
            .navigationTitle("Hear yourself")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// How noticeable the device delay is when hearing yourself.
private enum DelayLevel {
    case low, noticeable, high

    init(ms: Double) {
        self = ms <= 30 ? .low : ms <= 80 ? .noticeable : .high
    }

    var label: String {
        switch self {
        case .low: "Low"
        case .noticeable: "Noticeable"
        case .high: "High"
        }
    }

    var color: Color {
        switch self {
        case .low: .green
        case .noticeable: .yellow
        case .high: .red
        }
    }
}

private struct DelayTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reducing delay").font(.headline)
            Label("Use Automatic (the iPhone mic).", systemImage: "iphone")
            Label("Use wired headphones. Bluetooth adds about 150–250 ms.", systemImage: "cable.connector")
            Label("On AirPods, set noise control to Off or Noise Cancellation. Transparency and Adaptive add processing.", systemImage: "airpodsmax")
            Text("Some headphones add delay iOS can't report, so it may feel longer than shown.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding()
        .frame(idealWidth: 320)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// The system volume slider: the only way apps may change output volume. It
/// stays in sync with the headphones' own volume controls.
private struct SystemVolumeSlider: UIViewRepresentable {
    var tint: UIColor?

    func makeUIView(context: Context) -> MPVolumeView {
        MPVolumeView(frame: .zero)
    }

    func updateUIView(_ view: MPVolumeView, context: Context) {
        view.tintColor = tint
    }
}

#Preview {
    HearYourselfSheet()
        .environment(AudioEngine())
}
