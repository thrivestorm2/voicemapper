import SwiftUI

/// Hear-yourself controls, matching docs/WIREFRAMES.md §4.
struct HearYourselfSheet: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(\.openURL) private var openURL

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
                } footer: {
                    if audio.microphones.contains(where: { $0.id == audio.selectedMicrophoneID && $0.isBluetooth }) {
                        Text("Bluetooth mics record at lower quality and add delay, which makes pitch and resonance readings less accurate. The iPhone or a wired mic works best.")
                    } else {
                        Text("Automatic uses a wired or USB mic when one is connected, otherwise the iPhone's mic.")
                    }
                }

                Section {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Volume")
                            Spacer()
                            Text(audio.volume, format: .percent.precision(.fractionLength(0)))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $audio.volume, in: 0...1)
                            .tint(audio.isAboveSafeVolume ? .orange : .accentColor)
                            .accessibilityValue(audio.isAboveSafeVolume ? "Above safe listening level" : "")
                    }
                    if audio.isAboveSafeVolume {
                        Label("Above the safe-listening level. Long sessions this loud can harm your hearing.",
                              systemImage: "ear.trianglebadge.exclamationmark")
                            .font(.footnote)
                            .foregroundStyle(.orange)
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
                    Text("Delay is for delayed-feedback drills. Leave it at 0 ms for normal practice.")
                }
            }
            .navigationTitle("Hear yourself")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    HearYourselfSheet()
        .environment(AudioEngine())
}
