import SwiftUI

/// Darker ↔ brighter resonance bar with a dot for the live score. Neutral
/// colours on purpose: neither end is "right". The S7 grid will build on this.
struct ResonanceMeter: View {
    let reading: ResonanceReading?
    let isListening: Bool
    @State private var showingInfo = false

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Resonance")
                    .font(.subheadline.weight(.semibold))
                if let reading {
                    Text("\(Int(reading.score.rounded()))")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                Button {
                    showingInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
                .accessibilityLabel("About resonance")
                .popover(isPresented: $showingInfo) {
                    Text("Resonance is how small and bright, or big and dark, your voice's space sounds. It comes from the spacing of your formants (the vocal tract's resonances).\n\nVowels change it a lot: “ee” reads brighter than “oo”. Compare yourself on the same vowel.\n\nThere's no correct place on this bar. Work toward what feels like your voice.")
                        .font(.subheadline)
                        .padding()
                        .frame(width: 290)
                        .presentationCompactAdaptation(.popover)
                }
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(LinearGradient(colors: [.indigo, .teal, .yellow],
                                             startPoint: .leading, endPoint: .trailing))
                        .opacity(reading == nil ? 0.3 : 1)
                        .frame(height: 10)
                    if let reading {
                        Circle()
                            .fill(.background)
                            .stroke(.primary, lineWidth: 3)
                            .frame(width: 22, height: 22)
                            .offset(x: (width - 22) * reading.score / 100)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 22)
            .animation(.easeOut(duration: 0.15), value: reading?.score)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Resonance")
            .accessibilityValue(accessibilityValue)

            HStack {
                Text("Darker")
                Spacer()
                if reading == nil, isListening {
                    Text("Hold a vowel like “ee” or “ah”")
                }
                Spacer()
                Text("Brighter")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var accessibilityValue: String {
        guard let reading else { return "No reading" }
        let score = Int(reading.score.rounded())
        let word = score < 35 ? "darker" : score > 65 ? "brighter" : "middle"
        return "\(score) out of 100, \(word)"
    }
}

#Preview {
    VStack(spacing: 40) {
        ResonanceMeter(reading: ResonanceReading(score: 62, spacing: 1150, formants: []), isListening: true)
        ResonanceMeter(reading: nil, isListening: true)
    }
    .padding()
}
