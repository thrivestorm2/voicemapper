import SwiftUI

/// Strain and daily-cap alerts, shown over every tab. docs/WIREFRAMES.md §6.
struct SafetyAlertOverlay: View {
    @Environment(AudioEngine.self) private var audio
    @Environment(StrainGuard.self) private var strain

    var body: some View {
        if let alert = strain.alert {
            ZStack {
                Color.black.opacity(0.25).ignoresSafeArea()
                card(for: alert)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .padding(24)
            }
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private func card(for alert: StrainGuard.Alert) -> some View {
        switch alert {
        case .strain(let reasons):
            AlertCard(
                symbol: "drop.fill", title: "Take a break",
                message: "Signs of strain: \(ListFormatter.localizedString(byJoining: reasons)). Rest for 5 minutes and sip some water.",
                primary: ("Rest", { stopCapture(); strain.rest() }),
                secondary: ("Dismiss", { strain.dismiss() }))
        case .dailyCap(let minutes):
            AlertCard(
                symbol: "moon.zzz.fill", title: "Daily practice cap reached",
                message: "You've practised \(minutes) minutes today. Short, regular sessions are kinder to your voice than long ones.",
                primary: ("Stop for today", { stopCapture(); strain.stopForToday() }),
                secondary: ("5 more minutes", { strain.dismiss() }))
        }
    }

    private func stopCapture() {
        Task {
            await audio.setHearYourself(false)
            await audio.setListening(false)
        }
    }
}

private struct AlertCard: View {
    let symbol: String
    let title: String
    let message: String
    let primary: (String, () -> Void)
    let secondary: (String, () -> Void)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.tint)
            Text(message)
            Text("This is an estimate, not a diagnosis. If you have pain, lasting hoarseness or lose your voice, see a speech-language pathologist.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button(primary.0, action: primary.1).buttonStyle(.borderedProminent)
                Button(secondary.0, action: secondary.1).buttonStyle(.bordered)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// Shown while background noise is loud enough to throw off the readings.
struct NoiseBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "speaker.wave.3.fill").foregroundStyle(.orange)
            Text("Background noise is affecting the readings. Try a quieter spot or move closer to the mic.")
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Countdown shown on Live during a rest.
struct RestBanner: View {
    let until: Date
    let onEnd: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = max(0, until.timeIntervalSince(context.date))
            HStack(spacing: 10) {
                Image(systemName: "drop.fill").foregroundStyle(.blue)
                Text(remaining > 0
                     ? "Resting: \(Duration.seconds(remaining.rounded()).formatted(.time(pattern: .minuteSecond))) left"
                     : "Rest done. Start gently.")
                    .font(.subheadline)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(remaining > 0 ? "End" : "OK", action: onEnd)
                    .buttonStyle(.borderless)
                    .font(.subheadline.weight(.semibold))
            }
            .padding(12)
            .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

/// Weight and health rows under the grid. docs/WIREFRAMES.md §2.
struct VoiceQualityPanel: View {
    let quality: VoiceQuality?
    let health: StrainGuard.Health
    let todayMinutes: Int
    let capMinutes: Int

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Text("Weight").frame(width: 56, alignment: .leading)
                Text("lighter").font(.caption).foregroundStyle(.secondary)
                WeightBar(value: quality?.weight)
                Text("heavier").font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Vocal weight")
            .accessibilityValue(weightDescription)

            HStack(spacing: 8) {
                Text("Health").frame(width: 56, alignment: .leading)
                Circle().fill(healthColor).frame(width: 10, height: 10)
                Text(healthText).foregroundStyle(health == .unknown || health == .noisy ? .secondary : .primary)
                Spacer()
                Text("Today \(todayMinutes) / \(capMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
        .font(.subheadline)
    }

    private var weightDescription: String {
        guard let w = quality?.weight else { return "No reading" }
        return w < 0.35 ? "Lighter" : w > 0.65 ? "Heavier" : "Medium"
    }

    private var healthText: String {
        switch health {
        case .unknown: "–"
        case .noisy: "Paused: too noisy"
        case .steady: "Steady"
        case .watch: "Watch: ease off a little"
        case .strain: "Signs of strain"
        }
    }

    private var healthColor: Color {
        switch health {
        case .unknown, .noisy: .secondary.opacity(0.4)
        case .steady: .green
        case .watch: .yellow
        case .strain: .orange
        }
    }
}

private struct WeightBar: View {
    let value: Double?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.25)).frame(height: 4)
                if let value {
                    Circle()
                        .fill(.tint)
                        .frame(width: 14, height: 14)
                        .offset(x: value * (geo.size.width - 14))
                        .animation(.easeOut(duration: 0.3), value: value)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
    }
}

#Preview("Panel") {
    VoiceQualityPanel(quality: VoiceQuality(h1h2: 4, alphaRatio: -20, cpp: 25, hnr: 20,
                                            jitter: 0.5, shimmer: 3, level: -25),
                      health: .watch, todayMinutes: 8, capMinutes: 30)
        .padding()
}
