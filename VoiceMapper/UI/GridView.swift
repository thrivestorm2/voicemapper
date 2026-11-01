import SwiftUI

/// Pitch (up) × resonance (right) grid with typical-zone shading, the goal
/// pitch band, and a live dot with a short fading trail.
struct GridView: View {
    @AppStorage(GoalRange.lowKey) private var goalLow = 0
    @AppStorage(GoalRange.highKey) private var goalHigh = 0
    @AppStorage(ResonanceGoal.lowKey) private var resLow = 0.0
    @AppStorage(ResonanceGoal.highKey) private var resHigh = 0.0

    let pitch: PitchReading?
    let resonance: ResonanceReading?
    let isListening: Bool

    @State private var trail: [TrailPoint] = []
    /// Last resonance seen, kept so the dot can stay on screen at pitches where
    /// formants can't be tracked (it then draws hollow).
    @State private var lastScore: Double?
    @State private var showingInfo = false

    /// Centred on the androgynous zone (resonance 50, ~156 Hz) with equal reach
    /// each way: 50 score points sideways, 16 semitones up and down, drawn square.
    private static let centerScore = 50.0
    private static let centerMidi = 51.0  // D♯3
    private static let halfSpan = 16.0
    static let lowMidi = centerMidi - halfSpan
    static let highMidi = centerMidi + halfSpan
    private static let trailLife = 1.5
    private static let axisNotes = [36, 43, 48, 55, 60, 64]  // C2 G2 C3 G3 C4 E4

    struct TrailPoint: Equatable {
        let date: Date
        let x: Double  // 0–100
        let midi: Double
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let size = geo.size
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(.secondarySystemBackground))
                    ZoneField().frame(width: size.width, height: size.height)
                    ForEach([PerceivedGender.male, .ambiguous, .female], id: \.letter) { zone in
                        zoneLabel(zone, in: size)
                    }
                    goalBand(in: size)
                    resonanceGoalBand(in: size)
                    gridLines(in: size)
                    trailAndDot(in: size)
                    offScaleIndicator(in: size)
                }
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
                .contentShape(Rectangle())
                .gesture(resonanceGoalGesture(width: size.width))
            }
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .leading) { axisLabels.offset(x: -34) }
            .padding(.leading, 34)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Pitch and resonance grid")
            .accessibilityValue(accessibilityValue)

            HStack {
                Text("Darker")
                Spacer()
                Text(hint).multilineTextAlignment(.center)
                Spacer()
                Text("Brighter")
                Button { showingInfo = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About the grid")
                    .popover(isPresented: $showingInfo) {
                        Text("Up is higher pitch, right is brighter resonance (formant spacing).\n\nShaded areas show where voices are typically heard as male (M), ambiguous (A) or female (F). The colours blend because there are no hard edges: they're typical ranges, not rules, and intonation, vowels and speech habits matter too.\n\nSet a pitch goal by tapping notes on the Range tab. Set a resonance goal by dragging sideways across the grid; tap the grid to clear it.\n\nVowels change resonance a lot (“ee” reads brighter than “oo”), so compare on the same vowel. There's no correct place on this grid. Work toward what feels like your voice.")
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

    private func zoneLabel(_ zone: PerceivedGender, in size: CGSize) -> some View {
        Text(zone.letter)
            .font(.caption.weight(.bold))
            .foregroundStyle(zone.color)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Color(.systemBackground).opacity(0.85)))
            .overlay(Circle().stroke(zone.color, lineWidth: 1.5))
            .position(x: x(zone.typicalResonance, size),
                      y: y(Note.midiValue(frequency: zone.typicalFrequency), size))
            .accessibilityHidden(true)
    }

    /// Drag sideways to set a resonance goal; a tap clears it.
    private func resonanceGoalGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                guard abs(drag.translation.width) >= 8 else { return }
                let a = Double(drag.startLocation.x / width) * 100
                let b = Double(drag.location.x / width) * 100
                resLow = min(max(0, min(a, b)), 100)
                resHigh = min(100, max(0, max(a, b)))
            }
            .onEnded { drag in
                if abs(drag.translation.width) < 8 { resLow = 0; resHigh = 0 }
            }
    }

    @ViewBuilder
    private func resonanceGoalBand(in size: CGSize) -> some View {
        if let goal = ResonanceGoal(low: resLow, high: resHigh) {
            let left = x(goal.low, size), right = x(goal.high, size)
            Rectangle()
                .stroke(.primary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                .frame(width: right - left, height: size.height)
                .offset(x: left)
                .overlay(alignment: .bottomLeading) {
                    Text("Goal").font(.caption2).padding(3).offset(x: left)
                        .foregroundStyle(.secondary)
                }
        }
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
        .overlay {
            // Axes crossing at the centre (the androgynous point).
            ZStack {
                Rectangle().fill(.primary.opacity(0.35)).frame(width: 1.5)
                Rectangle().fill(.primary.opacity(0.35)).frame(height: 1.5)
            }
        }
    }

    private var isOffScale: Bool {
        guard let pitch else { return false }
        let midi = Note.midiValue(frequency: pitch.frequency)
        return midi > Self.highMidi || midi < Self.lowMidi
    }

    /// When the pitch is above or below the grid, pin a pill with the note to
    /// the top or bottom edge at the current resonance.
    @ViewBuilder
    private func offScaleIndicator(in size: CGSize) -> some View {
        if let pitch, isOffScale {
            let above = Note.midiValue(frequency: pitch.frequency) > Self.highMidi
            let px = min(max(x(resonance?.score ?? lastScore ?? Self.centerScore, size), 40), size.width - 40)
            Label(pitch.note.name, systemImage: above ? "arrow.up" : "arrow.down")
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.thinMaterial, in: Capsule())
                .overlay(Capsule().stroke(Color.accentColor, lineWidth: 2))
                .position(x: px, y: above ? 18 : size.height - 18)
                .accessibilityHidden(true)
        }
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
                if let pitch, !isOffScale, let score = resonance?.score ?? lastScore {
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
        guard let resonance else { return "Hold a vowel like “ee” or “ah”" }
        guard let goal = ResonanceGoal(low: resLow, high: resHigh) else { return " " }
        switch goal.direction(of: resonance.score) {
        case nil: return "In your resonance goal"
        case .brighter: return "Goal is brighter"
        case .darker: return "Goal is darker"
        }
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

/// Zone shading: colour blends smoothly between male, ambiguous and female
/// (see `VoicePerception`); strength follows how common voices are at each
/// spot, so it peaks around each zone's typical pitch and resonance.
private struct ZoneField: View {
    private static let cells = 64

    var body: some View {
        Canvas { gc, size in
            let n = Self.cells
            let w = size.width / Double(n), h = size.height / Double(n)
            for row in 0..<n {
                let midi = GridView.highMidi - (Double(row) + 0.5) / Double(n) * (GridView.highMidi - GridView.lowMidi)
                let hz = 440 * pow(2, (midi - 69) / 12)
                let y0 = (Double(row) * h).rounded(), y1 = (Double(row + 1) * h).rounded()
                for col in 0..<n {
                    let score = (Double(col) + 0.5) / Double(n) * 100
                    let blend = VoicePerception.blend(frequency: hz, score: score)
                    let alpha = 0.1 + 0.55 * VoicePerception.commonness(frequency: hz, score: score, blend: blend)
                    // Edges snapped to whole points so neighbours meet exactly.
                    let x0 = (Double(col) * w).rounded(), x1 = (Double(col + 1) * w).rounded()
                    gc.fill(Path(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)),
                            with: .color(VoicePerception.color(blend).opacity(alpha)))
                }
            }
        }
    }
}
