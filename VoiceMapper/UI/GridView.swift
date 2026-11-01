import SwiftUI

/// Pitch (up) × resonance (right) grid with typical-zone shading, the goal
/// pitch band, and a live dot with a short fading trail.
struct GridView: View {
    @AppStorage(GoalRange.lowKey) private var goalLow = 0
    @AppStorage(GoalRange.highKey) private var goalHigh = 0

    let pitch: PitchReading?
    let resonance: ResonanceReading?
    let isListening: Bool

    @State private var trail: [TrailPoint] = []
    /// Last resonance seen, kept so the dot can stay on screen at pitches where
    /// formants can't be tracked (it then draws hollow).
    @State private var lastScore: Double?
    @State private var showingInfo = false

    private static let lowMidi = 40.0   // E2
    private static let highMidi = 72.0  // C5
    private static let trailLife = 1.5
    private static let axisNotes = [48, 55, 60, 67]  // C3 G3 C4 G4

    struct TrailPoint: Equatable {
        let date: Date
        let x: Double  // 0–100
        let midi: Double
    }

    private struct Zone {
        let gender: PerceivedGender
        let score: Double
        let midi: Double
        let color: Color
    }

    // Typical positions: pitch from PerceivedGender.typicalFrequency, resonance
    // from average ΔF for male / female voices (see ResonanceScorer).
    private static let zones: [Zone] = [
        Zone(gender: .male, score: 25, midi: Note.midiValue(frequency: 120), color: .blue),
        Zone(gender: .ambiguous, score: 50, midi: Note.midiValue(frequency: 160), color: .green),
        Zone(gender: .female, score: 72, midi: Note.midiValue(frequency: 210), color: .orange),
    ]

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 4) {
                axisLabels
                GeometryReader { geo in
                    let size = geo.size
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.secondarySystemBackground))
                        ForEach(Self.zones.indices, id: \.self) { i in
                            zoneView(Self.zones[i], in: size)
                        }
                        goalBand(in: size)
                        gridLines(in: size)
                        trailAndDot(in: size)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Pitch and resonance grid")
                .accessibilityValue(accessibilityValue)
            }

            HStack {
                Text("Darker")
                Spacer()
                Text(hint).multilineTextAlignment(.center)
                Spacer()
                Text("Brighter")
                Button { showingInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About the grid")
                    .popover(isPresented: $showingInfo) {
                        Text("Up is higher pitch, right is brighter resonance (formant spacing).\n\nShaded areas show where voices are typically heard as male (M), ambiguous (A) or female (F). They're typical ranges, not rules: intonation, vowels and speech habits matter too.\n\nVowels change resonance a lot (“ee” reads brighter than “oo”), so compare on the same vowel. There's no correct place on this grid. Work toward what feels like your voice.")
                            .font(.subheadline)
                            .padding()
                            .frame(width: 300)
                            .presentationCompactAdaptation(.popover)
                    }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 34)
        }
        .onChange(of: resonance) { _, new in
            if let new { lastScore = new.score }
            record()
        }
        .onChange(of: pitch) { _, _ in record() }
    }

    // MARK: - Mapping

    private func y(_ midi: Double, _ size: CGSize) -> CGFloat {
        let t = (midi - Self.lowMidi) / (Self.highMidi - Self.lowMidi)
        return size.height * (1 - min(1, max(0, t)))
    }

    private func x(_ score: Double, _ size: CGSize) -> CGFloat {
        size.width * min(1, max(0, score / 100))
    }

    // MARK: - Layers

    private func zoneView(_ zone: Zone, in size: CGSize) -> some View {
        let w = size.width * 0.5, h = size.height * 8 / (Self.highMidi - Self.lowMidi)
        return ZStack {
            Ellipse().fill(zone.color.opacity(0.22))
            Text(zone.gender.letter)
                .font(.caption.weight(.bold))
                .foregroundStyle(zone.color)
        }
        .frame(width: w, height: h)
        .position(x: x(zone.score, size), y: y(zone.midi, size))
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func goalBand(in size: CGSize) -> some View {
        if let goal = GoalRange(low: goalLow, high: goalHigh) {
            let top = y(Double(goal.high) + 0.5, size)
            let bottom = y(Double(goal.low) - 0.5, size)
            Rectangle()
                .stroke(.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: size.width, height: max(2, bottom - top))
                .offset(y: top)
                .overlay(alignment: .topLeading) {
                    Text("Goal").font(.caption2).padding(3).offset(y: top)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func gridLines(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Self.axisNotes, id: \.self) { midi in
                Rectangle().fill(.primary.opacity(0.08))
                    .frame(height: 1)
                    .offset(y: y(Double(midi), size))
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private func trailAndDot(in size: CGSize) -> some View {
        TimelineView(.animation(paused: trail.isEmpty && pitch == nil)) { context in
            Canvas { gc, _ in
                let now = context.date
                let live = trail.filter { now.timeIntervalSince($0.date) < Self.trailLife }
                var path = Path()
                for (i, p) in live.enumerated() {
                    let pt = CGPoint(x: x(p.x, size), y: y(p.midi, size))
                    if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
                }
                for (i, p) in live.enumerated() where i > 0 {
                    let age = now.timeIntervalSince(p.date) / Self.trailLife
                    var seg = Path()
                    let prev = live[i - 1]
                    seg.move(to: CGPoint(x: x(prev.x, size), y: y(prev.midi, size)))
                    seg.addLine(to: CGPoint(x: x(p.x, size), y: y(p.midi, size)))
                    gc.stroke(seg, with: .color(.accentColor.opacity(0.6 * (1 - age))),
                              style: StrokeStyle(lineWidth: 4, lineCap: .round))
                }
                if let pitch, let score = resonance?.score ?? lastScore {
                    let c = CGPoint(x: x(score, size), y: y(Note.midiValue(frequency: pitch.frequency), size))
                    let dot = Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18))
                    if resonance != nil {
                        gc.fill(dot, with: .color(.accentColor))
                        gc.stroke(dot, with: .color(.white), lineWidth: 2)
                    } else {
                        gc.fill(dot, with: .color(Color(.systemBackground)))
                        gc.stroke(dot, with: .color(.accentColor), lineWidth: 3)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var axisLabels: some View {
        GeometryReader { geo in
            ForEach(Self.axisNotes, id: \.self) { midi in
                Text(Note(midi: midi).name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(x: 15, y: y(Double(midi), geo.size))
            }
        }
        .frame(width: 30)
        .accessibilityHidden(true)
    }

    // MARK: - State

    private func record() {
        guard let pitch, let score = resonance?.score ?? lastScore else {
            return
        }
        let now = Date()
        trail.append(TrailPoint(date: now, x: score, midi: Note.midiValue(frequency: pitch.frequency)))
        trail.removeAll { now.timeIntervalSince($0.date) > Self.trailLife }
    }

    private var hint: String {
        if pitch == nil { return " " }
        if resonance == nil { return "Hold a vowel like “ee” or “ah”" }
        return " "
    }

    private var accessibilityValue: String {
        guard let pitch else { return "No reading" }
        var text = "\(pitch.note.name)"
        if let resonance {
            let score = Int(resonance.score.rounded())
            text += ", resonance \(score) out of 100"
        }
        return text
    }
}

#Preview {
    GridView(pitch: PitchReading(frequency: 196, note: Note(frequency: 196)),
             resonance: ResonanceReading(score: 62, spacing: 1150, formants: []),
             isListening: true)
        .padding()
        .frame(height: 400)
}
