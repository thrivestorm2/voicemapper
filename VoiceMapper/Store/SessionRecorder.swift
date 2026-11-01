import Foundation
import SwiftData

/// Watches the audio engine and saves a `PracticeSession` each time capturing
/// runs and stops. Samples the latest readings 5×/second.
@MainActor
final class SessionRecorder {
    static let tick = 0.2
    /// Sessions with less voiced time than this are discarded as accidental taps.
    static let minimumVoiced = 3.0

    private let audio: AudioEngine
    private let context: ModelContext
    private let strain: StrainGuard
    private var task: Task<Void, Never>?

    private var start: Date?
    private var hz: [Double] = []
    private var scores: [Double] = []
    private var qualities: [VoiceQuality] = []
    private var cells: [Int: [Int: Double]] = [:]  // midi → bin → seconds

    init(audio: AudioEngine, context: ModelContext, strain: StrainGuard) {
        self.audio = audio
        self.context = context
        self.strain = strain
    }

    func run() {
        guard task == nil else { return }
        strain.setToday(practicedToday())
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tick))
                self?.sample()
            }
        }
    }

    private func sample() {
        let capturing = audio.isListening || audio.isHearingYourself
        guard capturing else { finish(); return }
        if start == nil { begin() }
        // Noise skews the quality measures, so they're left out while noisy.
        let quality = audio.isNoisy ? nil : audio.quality
        strain.observe(tick: Self.tick, pitch: audio.pitch?.frequency, quality: quality, noisy: audio.isNoisy)
        guard let pitch = audio.pitch else { return }
        hz.append(pitch.frequency)
        if let quality { qualities.append(quality) }
        if let r = audio.resonance {
            scores.append(r.score)
            cells[pitch.note.midi, default: [:]][GridCellCount.bin(forResonance: r.score), default: 0] += Self.tick
        }
    }

    private func begin() {
        start = .now
        let baseline = try? context.fetch(FetchDescriptor<Baseline>()).first
        strain.beginSession(priorToday: practicedToday(), baseline: baseline?.quality,
                            topHz: baseline.map { $0.medianHz * 2 })
    }

    /// Capture seconds in sessions saved since midnight.
    private func practicedToday() -> Double {
        let midnight = Calendar.current.startOfDay(for: .now)
        let today = FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.start >= midnight })
        return ((try? context.fetch(today)) ?? []).reduce(0) { $0 + $1.duration }
    }

    /// Saves the open session (if worth keeping). Also called when the app backgrounds.
    func finish() {
        defer {
            if start != nil {
                strain.endSession()
                strain.setToday(practicedToday())
            }
            start = nil; hz = []; scores = []; qualities = []; cells = [:]
        }
        guard let start else { return }
        let voiced = Double(hz.count) * Self.tick
        guard voiced >= Self.minimumVoiced,
              let med = median(hz), let lo = percentile(hz, 0.1), let hi = percentile(hz, 0.9) else { return }
        let session = PracticeSession(
            start: start, duration: Date.now.timeIntervalSince(start), voicedSeconds: voiced,
            medianHz: med, p10Hz: lo, p90Hz: hi, medianResonance: median(scores))
        session.quality = QualitySummary(qualities)
        context.insert(session)
        for (midi, bins) in cells {
            for (bin, seconds) in bins {
                session.cells.append(GridCellCount(pitchMidi: midi, resonanceBin: bin, seconds: seconds))
            }
        }
        try? context.save()
    }
}
