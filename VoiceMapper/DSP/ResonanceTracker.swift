import Foundation

/// What the resonance tracker reports while the user holds a voiced sound.
struct ResonanceReading: Equatable, Sendable {
    /// 0 (darker) … 100 (brighter).
    let score: Double
    /// Smoothed formant spacing ΔF in Hz.
    let spacing: Double
    /// Latest formant frequencies (F1…F4) behind the reading.
    let formants: [Double]
}

/// Runs `FormantAnalyzer` on the live stream while the voice is pitched,
/// gates out unreliable frames and median-smooths the spacing. Called only from
/// the audio thread, so make a new one whenever the engine is rebuilt.
final class ResonanceTracker: @unchecked Sendable {
    /// Samples between analyses (~43 ms at 48 kHz).
    private static let hop = 2048
    /// ~0.4 s of accepted frames.
    private static let medianCount = 9
    /// Accepted frames before the first reading is shown.
    private static let minimumFrames = 3
    /// Analyses in a row without an accepted frame before the reading clears
    /// (~0.35 s).
    private static let dropoutFrames = 8
    /// Above this F0 the harmonics are too sparse for LPC to find formants.
    private static let maxPitch = 450.0

    private var analyzer: FormantAnalyzer
    private let onReading: @Sendable (ResonanceReading?) -> Void
    private var samples: [Float] = []
    private var recent: [Double] = []
    private var missedRun = 0
    private var hasReading = false

    init(sampleRate: Double, onReading: @escaping @Sendable (ResonanceReading?) -> Void) {
        analyzer = FormantAnalyzer(sampleRate: sampleRate)
        self.onReading = onReading
    }

    /// `pitch` is the current smoothed F0, nil when unvoiced.
    func process(_ incoming: UnsafeBufferPointer<Float>, pitch: Double?) {
        samples.append(contentsOf: incoming)
        let needed = max(analyzer.frameLength, Self.hop)
        while samples.count >= needed {
            var formants: [FormantAnalyzer.Formant]?
            if let pitch, pitch <= Self.maxPitch {
                formants = samples.withUnsafeBufferPointer { analyzer.analyze($0) }
            }
            samples.removeFirst(Self.hop)
            update(with: formants)
        }
    }

    private func update(with formants: [FormantAnalyzer.Formant]?) {
        guard let formants, let spacing = ResonanceScorer.spacing(of: formants) else {
            missedRun += 1
            if missedRun >= Self.dropoutFrames {
                recent.removeAll()
                if hasReading {
                    hasReading = false
                    onReading(nil)
                }
            }
            return
        }
        missedRun = 0
        recent.append(spacing)
        if recent.count > Self.medianCount { recent.removeFirst() }
        guard recent.count >= Self.minimumFrames else { return }
        let median = recent.sorted()[recent.count / 2]
        hasReading = true
        onReading(ResonanceReading(
            score: ResonanceScorer.score(spacing: median),
            spacing: median,
            formants: formants.prefix(4).map(\.frequency)
        ))
    }
}
