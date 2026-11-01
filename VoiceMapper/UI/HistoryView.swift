import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(SessionRecorder.self) private var recorder
    @Query(sort: \PracticeSession.start, order: .reverse) private var allSessions: [PracticeSession]
    @AppStorage("historyPeriod") private var periodRaw = HistoryPeriod.week.rawValue

    private var period: HistoryPeriod { HistoryPeriod(rawValue: periodRaw) ?? .week }

    var body: some View {
        NavigationStack {
            let sessions = HeatmapBinner.sessions(allSessions, in: period)
            // A List (not a ScrollView) so session rows can be swiped to delete.
            List {
                Group {
                    Picker("Period", selection: $periodRaw) {
                        ForEach(HistoryPeriod.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    if sessions.isEmpty {
                        ContentUnavailableView("No sessions yet",
                                               systemImage: "chart.xyaxis.line",
                                               description: Text(allSessions.isEmpty
                                                    ? "Practise on the Live tab and your sessions will appear here."
                                                    : "Nothing recorded in this period. Try a longer one."))
                    } else {
                        heatMap(sessions)
                        chart("Median pitch (Hz)", sessions: sessions) { $0.medianHz }
                        chart("Resonance score", sessions: sessions.filter { $0.medianResonance != nil }) { $0.medianResonance ?? 0 }
                        weightChart(sessions.filter { $0.quality != nil })
                    }
                }
                .listRowSeparator(.hidden)
                .padding(.vertical, 6)

                if !sessions.isEmpty { sessionList(sessions) }
            }
            .listStyle(.plain)
            .navigationTitle("History")
        }
    }

    private func heatMap(_ sessions: [PracticeSession]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Time spent").font(.headline)
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground))
                ZoneField().opacity(0.5)
                HeatmapLayer(cells: HeatmapBinner.cells(from: sessions))
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Heat map of time spent at each pitch and resonance")
            HStack {
                Text("Darker"); Spacer(); Text("Brighter")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("Orange shows where you spent voiced time; stronger means longer. Up is higher pitch.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func chart(_ title: String, sessions: [PracticeSession],
                       value: @escaping (PracticeSession) -> Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            if sessions.count < 2 {
                Text("Needs at least two sessions.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(sessions.sorted { $0.start < $1.start }, id: \.start) { s in
                    LineMark(x: .value("Date", s.start), y: .value(title, value(s)))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", s.start), y: .value(title, value(s)))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 140)
            }
        }
    }

    /// Session medians of vocal weight on a fixed lighter … heavier scale.
    private func weightChart(_ sessions: [PracticeSession]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vocal weight").font(.headline)
            if sessions.count < 2 {
                Text("Needs at least two sessions.").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(sessions.sorted { $0.start < $1.start }, id: \.start) { s in
                    let w = s.quality?.weight ?? 0
                    LineMark(x: .value("Date", s.start), y: .value("Weight", w))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Date", s.start), y: .value("Weight", w))
                }
                .chartYScale(domain: 0...1)
                .chartYAxis {
                    AxisMarks(values: [0, 0.5, 1]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            switch value.as(Double.self) {
                            case 0: Text("lighter")
                            case 1: Text("heavier")
                            default: Text("")
                            }
                        }
                    }
                }
                .frame(height: 140)
                .accessibilityLabel("Vocal weight per session, from lighter to heavier")
            }
            Text("Neither end is better: lighter or heavier is your choice.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sessionList(_ sessions: [PracticeSession]) -> some View {
        Section {
            ForEach(sessions) { s in
                HStack {
                    Text(s.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    if (s.noisyShare ?? 0) >= SessionRecorder.noisyPromptShare {
                        Image(systemName: "speaker.wave.3.fill")
                            .font(.caption).foregroundStyle(.orange)
                            .accessibilityLabel("Noisy")
                    }
                    Spacer()
                    Text("\(max(1, Int((s.duration / 60).rounded()))) min")
                    Text(Note(frequency: s.medianHz).name).frame(width: 44, alignment: .trailing)
                    Text(s.medianResonance.map { "\(Int($0.rounded()))" } ?? "–")
                        .frame(width: 30, alignment: .trailing)
                }
                .font(.subheadline).monospacedDigit()
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { recorder.delete(s) }
                }
            }
        } header: {
            Text("Sessions").font(.headline).foregroundStyle(.primary)
        } footer: {
            Text("Columns: date, length, median note, resonance score. Swipe left on a session to delete it. \(Image(systemName: "speaker.wave.3.fill")) marks a noisy session.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
