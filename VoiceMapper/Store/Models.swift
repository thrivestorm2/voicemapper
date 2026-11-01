import Foundation
import SwiftData

/// One continuous stretch of capturing (Speak or Listen on, until both off).
/// Only summaries and per-cell voiced time are kept — never audio.
@Model
final class PracticeSession {
    var start: Date
    /// Wall-clock seconds capturing.
    var duration: Double
    /// Seconds with a voiced pitch reading.
    var voicedSeconds: Double
    var medianHz: Double
    var p10Hz: Double
    var p90Hz: Double
    /// Median resonance score (0–100); nil if no reliable readings.
    var medianResonance: Double?
    @Relationship(deleteRule: .cascade, inverse: \GridCellCount.session)
    var cells: [GridCellCount] = []

    init(start: Date, duration: Double, voicedSeconds: Double, medianHz: Double,
         p10Hz: Double, p90Hz: Double, medianResonance: Double?) {
        self.start = start
        self.duration = duration
        self.voicedSeconds = voicedSeconds
        self.medianHz = medianHz
        self.p10Hz = p10Hz
        self.p90Hz = p90Hz
        self.medianResonance = medianResonance
    }
}

/// Voiced seconds spent in one grid cell (one semitone × one 5-point resonance
/// band) during a session. Feeds the S9 heat map.
@Model
final class GridCellCount {
    var pitchMidi: Int
    var resonanceBin: Int
    var seconds: Double
    var session: PracticeSession?

    init(pitchMidi: Int, resonanceBin: Int, seconds: Double) {
        self.pitchMidi = pitchMidi
        self.resonanceBin = resonanceBin
        self.seconds = seconds
    }

    static let resonanceBinWidth = 5.0
    static func bin(forResonance score: Double) -> Int {
        Int(min(max(score, 0), 99.999) / resonanceBinWidth)
    }
}

/// The user's own reference voice from a 20-second recording. One row;
/// re-recording replaces it. Health measures (HNR, jitter, shimmer) join in S10.
@Model
final class Baseline {
    var date: Date
    var medianHz: Double
    var medianResonance: Double?

    init(date: Date, medianHz: Double, medianResonance: Double?) {
        self.date = date
        self.medianHz = medianHz
        self.medianResonance = medianResonance
    }
}

func median(_ values: [Double]) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func percentile(_ values: [Double], _ p: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let s = values.sorted()
    return s[min(s.count - 1, Int((Double(s.count - 1) * p).rounded()))]
}
