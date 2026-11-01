import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Query(sort: \PracticeSession.start, order: .reverse) private var allSessions: [PracticeSession]
    @AppStorage("historyPeriod") private var periodRaw = HistoryPeriod.week.rawValue

    private var period: HistoryPeriod { HistoryPeriod(rawValue: periodRaw) ?? .week }

    var body: some View {
        NavigationStack {
            let sessions = HeatmapBinner.sessions(allSessions, in: period)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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
                        sessionList(sessions)
                    }
                }
                .padding()
            }
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

    private func sessionList(_ sessions: [PracticeSession]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Sessions").font(.headline)
            ForEach(sessions, id: \.start) { s in
                HStack {
                    Text(s.start.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                    Spacer()
                    Text("\(max(1, Int((s.duration / 60).rounded()))) min")
                    Text(Note(frequency: s.medianHz).name).frame(width: 44, alignment: .trailing)
                    Text(s.medianResonance.map { "\(Int($0.rounded()))" } ?? "–")
                        .frame(width: 30, alignment: .trailing)
                }
                .font(.subheadline).monospacedDigit()
                Divider()
            }
            Text("Columns: date, length, median note, resonance score.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
