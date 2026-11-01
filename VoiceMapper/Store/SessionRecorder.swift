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
    private var task: Task<Void, Never>?

    private var start: Date?
    private var hz: [Double] = []
    private var scores: [Double] = []
    private var cells: [Int: [Int: Double]] = [:]  // midi → bin → seconds

    init(audio: AudioEngine, context: ModelContext) {
        self.audio = audio
        self.context = context
    }

    func run() {
        guard task == nil else { return }
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
        if start == nil { start = .now }
        guard let pitch = audio.pitch else { return }
        hz.append(pitch.frequency)
        if let r = audio.resonance {
            scores.append(r.score)
            cells[pitch.note.midi, default: [:]][GridCellCount.bin(forResonance: r.score), default: 0] += Self.tick
        }
    }

    /// Saves the open session (if worth keeping). Also called when the app backgrounds.
    func finish() {
        defer { start = nil; hz = []; scores = []; cells = [:] }
        guard let start else { return }
        let voiced = Double(hz.count) * Self.tick
        guard voiced >= Self.minimumVoiced,
              let med = median(hz), let lo = percentile(hz, 0.1), let hi = percentile(hz, 0.9) else { return }
        let session = PracticeSession(
            start: start, duration: Date.now.timeIntervalSince(start), voicedSeconds: voiced,
            medianHz: med, p10Hz: lo, p90Hz: hi, medianResonance: median(scores))
        context.insert(session)
        for (midi, bins) in cells {
            for (bin, seconds) in bins {
                session.cells.append(GridCellCount(pitchMidi: midi, resonanceBin: bin, seconds: seconds))
            }
        }
        try? context.save()
    }
}
