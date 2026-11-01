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
    /// Voice-quality medians (S10); nil for older sessions or no readings.
    var quality: QualitySummary?
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

/// Medians of the voice-quality measures over a session or the baseline.
struct QualitySummary: Codable, Equatable, Sendable {
    var hnr: Double
    var cpp: Double
    var jitter: Double?
    var shimmer: Double?
    var level: Double
    var weight: Double

    init?(_ samples: [VoiceQuality]) {
        guard let m = VoiceQuality.median(of: samples) else { return nil }
        hnr = m.hnr; cpp = m.cpp; jitter = m.jitter; shimmer = m.shimmer; level = m.level
        weight = VoiceMapper.median(samples.map(\.weight)) ?? m.weight
    }
}

/// The user's own reference voice from a 30-second reading. One row;
/// re-recording replaces it. `quality` is the health reference for StrainGuard.
@Model
final class Baseline {
    var date: Date
    var medianHz: Double
    var medianResonance: Double?
    var quality: QualitySummary?

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
