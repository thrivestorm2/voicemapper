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
