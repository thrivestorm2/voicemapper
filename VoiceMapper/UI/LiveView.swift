import SwiftUI
import SwiftData

struct LiveView: View {
    @Environment(AudioEngine.self) private var audio
    @Query(sort: \PracticeSession.start) private var allSessions: [PracticeSession]
    @AppStorage("showHistoryOverlay") private var showOverlay = false
    @AppStorage("showHeatMap") private var showHeat = false
    @AppStorage("historyPeriod") private var periodRaw = HistoryPeriod.week.rawValue
    @State private var showingHearYourself = false

    private var period: HistoryPeriod { HistoryPeriod(rawValue: periodRaw) ?? .week }

    private var isCapturing: Bool { audio.isListening || audio.isHearingYourself }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                PitchLabel(reading: audio.pitch, isListening: isCapturing)
                let sessions = (showOverlay || showHeat) ? HeatmapBinner.sessions(allSessions, in: period) : []
                GridView(pitch: audio.pitch, resonance: audio.resonance, isListening: isCapturing,
                         heat: showHeat ? HeatmapBinner.cells(from: sessions) : [],
                         trace: showOverlay ? HeatmapBinner.points(from: sessions) : [])
                    .padding(.horizontal, 16)
                historyControls
                Color.clear.frame(height: 56)  // room for the buttons below
            }
            .padding(.top, 8)
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

extension LiveView {
    fileprivate var historyControls: some View {
        HStack(spacing: 8) {
            Toggle("History", isOn: $showOverlay)
            Toggle("Heat map", isOn: $showHeat)
            Picker("Period", selection: $periodRaw) {
                ForEach(HistoryPeriod.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.menu)
        }
        .toggleStyle(.button)
        .buttonStyle(.bordered)
        .font(.subheadline)
        .padding(.horizontal, 16)
    }
}

/// Note name and frequency, e.g. "G4  196 Hz". No needle or cents, by design.
private struct PitchLabel: View {
    @AppStorage(GoalRange.lowKey) private var goalLow = 0
    @AppStorage(GoalRange.highKey) private var goalHigh = 0
    let reading: PitchReading?
    let isListening: Bool

    /// Always three lines (note, Hz or prompt, goal caption) so the height
    /// never changes and the resonance bar below stays put.
    var body: some View {
        VStack(spacing: 2) {
            if let reading {
                Text(reading.note.name)
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .foregroundStyle(noteColor(for: reading))
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
            Text(caption ?? " ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityHidden(caption == nil)
        }
        .lineLimit(1)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

extension PitchLabel {
    fileprivate var caption: String? {
        guard let reading, let goal = GoalRange(low: goalLow, high: goalHigh) else { return nil }
        return goalCaption(goal.direction(of: reading.frequency))
    }

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
