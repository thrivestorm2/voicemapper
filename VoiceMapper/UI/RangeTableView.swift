import SwiftUI

struct RangeTableView: View {
    @Environment(AudioEngine.self) private var audio
    @AppStorage(GoalRange.lowKey) private var goalLow = 0
    @AppStorage(GoalRange.highKey) private var goalHigh = 0

    private var goal: GoalRange? { GoalRange(low: goalLow, high: goalHigh) }

    /// First tap sets a one-note goal, a second tap on another row stretches it
    /// to a range, tapping the lone note again clears it, and any tap on an
    /// existing range starts over.
    private func tap(_ midi: Int) {
        if let goal, goal.low == goal.high {
            if midi == goal.low {
                goalLow = 0; goalHigh = 0
            } else {
                goalLow = min(midi, goal.low); goalHigh = max(midi, goal.low)
            }
        } else {
            goalLow = midi; goalHigh = midi
        }
    }

    /// Row of the note being sung, nil when silent.
    private var currentID: Int? {
        audio.pitch.map { RangeTable.rowID(for: $0.note) }
    }

    var body: some View {
        NavigationStack {
            // Rows share the height equally, so the table never scrolls.
            VStack(spacing: 0) {
                HeaderRow()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                ForEach(RangeTable.rows) { row in
                    RangeRowView(row: row, isCurrent: row.id == currentID)
                        .padding(.horizontal, 16)
                        .frame(maxHeight: .infinity)
                        .background {
                            ZStack {
                                if goal?.contains(midi: row.id) == true { Color.teal.opacity(0.18) }
                                if row.id == currentID { Color.accentColor.opacity(0.2) }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { tap(row.id) }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint("Sets your goal range")
                }
                Divider()
                Legend(isListening: audio.isListening) {
                    Task { await audio.setListening(!audio.isListening) }
                }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                CurrentNote(reading: audio.pitch, isListening: audio.isListening || audio.isHearingYourself)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(.bar)
            }
            .navigationTitle("Range")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct CurrentNote: View {
    let reading: PitchReading?
    let isListening: Bool

    var body: some View {
        Group {
            if let reading {
                Text("\(reading.note.name)   \(Int(reading.frequency.rounded())) Hz")
            } else {
                Text(isListening ? "Say or hum a note" : "Tap Speak to start")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.title2.weight(.semibold))
        .monospacedDigit()
    }
}

private struct HeaderRow: View {
    @State private var showingInfo = false

    var body: some View {
        HStack {
            Text("Note").frame(width: 56, alignment: .leading)
            Text("Hz").frame(width: 48, alignment: .trailing)
            Text("Voice").frame(width: 64, alignment: .leading).padding(.leading, 12)
            Text("Read").frame(maxWidth: .infinity, alignment: .leading)
            Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
            }
            .accessibilityLabel("About this table")
            .popover(isPresented: $showingInfo) {
                Text("Tap a note to set your goal, then another to stretch it into a range. Tap the single note again to clear.\n\nResonance matters too. These are typical speaking ranges, not rules.")
                    .font(.subheadline)
                    .padding()
                    .frame(width: 280)
                    .presentationCompactAdaptation(.popover)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }
}

private struct RangeRowView: View {
    let row: RangeRow
    let isCurrent: Bool

    var body: some View {
        HStack {
            Text(row.note.name)
                .font(.body.weight(isCurrent ? .bold : .regular))
                .frame(width: 56, alignment: .leading)
            Text("\(Int(row.frequency.rounded()))")
                .frame(width: 48, alignment: .trailing)
                .monospacedDigit()
            Text(row.voiceType.rawValue)
                .frame(width: 64, alignment: .leading)
                .padding(.leading, 12)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ZoneSwatch(perceived: row.perceived, strength: row.commonness)
                Text(row.perceived.letter).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.note.name), \(Int(row.frequency.rounded())) hertz, \(row.voiceType.rawValue), \(row.perceived.meaning)")
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Bar tinted by zone; the fill is strongest at the zone's most common pitch,
/// so density is a cue as well as colour.
private struct ZoneSwatch: View {
    let perceived: PerceivedGender
    let strength: Double

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(strength))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(color, lineWidth: 1))
            .frame(width: 40, height: 14)
    }

    private var color: Color { perceived.color }
}

private struct Legend: View {
    let isListening: Bool
    let toggleListening: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach([PerceivedGender.female, .ambiguous, .male], id: \.letter) { zone in
                        HStack(spacing: 8) {
                            ZoneSwatch(perceived: zone, strength: 1)
                            Text("\(zone.letter) – \(zone.meaning)")
                        }
                    }
                }
                Spacer()
                Button(action: toggleListening) {
                    Label(isListening ? "Stop" : "Speak",
                          systemImage: isListening ? "mic.fill" : "mic")
                }
                .buttonStyle(.bordered)
                .tint(isListening ? .accentColor : .secondary)
                .accessibilityValue(isListening ? "On" : "Off")
            }
        }
        .font(.subheadline)
    }
}

#Preview {
    RangeTableView()
        .environment(AudioEngine())
}
