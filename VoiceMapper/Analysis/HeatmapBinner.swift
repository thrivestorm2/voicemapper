import Foundation

/// Time window for the History tab, heat map and grid overlay.
enum HistoryPeriod: String, CaseIterable, Identifiable, Sendable {
    case today, week, month, all
    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .week: "Week"
        case .month: "Month"
        case .all: "All"
        }
    }

    /// Earliest session start included; nil means no limit.
    func cutoff(now: Date = .now, calendar: Calendar = .current) -> Date? {
        switch self {
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.date(byAdding: .day, value: -7, to: now)
        case .month: calendar.date(byAdding: .day, value: -30, to: now)
        case .all: nil
        }
    }
}

/// Voiced seconds in one grid cell (one semitone × one 5-point resonance band).
struct HeatCell: Identifiable, Equatable, Sendable {
    let midi: Int
    let bin: Int
    let seconds: Double
    var id: Int { midi * 100 + bin }
}

/// One session's average position on the grid.
struct HistoryPoint: Identifiable, Equatable, Sendable {
    let date: Date
    let score: Double
    let midi: Double
    var id: Date { date }
}

enum HeatmapBinner {
    static func sessions(_ all: [PracticeSession], in period: HistoryPeriod, now: Date = .now) -> [PracticeSession] {
        guard let cutoff = period.cutoff(now: now) else { return all }
        return all.filter { $0.start >= cutoff }
    }

    /// Sums voiced time per cell across sessions.
    static func cells(from sessions: [PracticeSession]) -> [HeatCell] {
        var totals: [Int: Double] = [:]
        for session in sessions {
            for c in session.cells {
                totals[c.pitchMidi * 100 + c.resonanceBin, default: 0] += c.seconds
            }
        }
        return totals.map { HeatCell(midi: $0.key / 100, bin: $0.key % 100, seconds: $0.value) }
    }

    /// Session medians in time order; sessions without a resonance reading are skipped.
    static func points(from sessions: [PracticeSession]) -> [HistoryPoint] {
        sessions.sorted { $0.start < $1.start }.compactMap { s in
            guard let r = s.medianResonance, s.medianHz > 0 else { return nil }
            return HistoryPoint(date: s.start, score: r, midi: Note.midiValue(frequency: s.medianHz))
        }
    }
}
