import Foundation

/// Runs `VoiceQualityAnalyzer` on the live stream while the voice is pitched
/// and reports the median of the last ~1 s of frames. Called only from the
/// audio thread, so make a new one whenever the engine is rebuilt.
final class VoiceQualityTracker: @unchecked Sendable {
    /// ~1 s of frames at a half-frame hop.
    private static let windowCount = 24
    private static let minimumFrames = 6
    /// Analyses in a row without a usable frame before the reading clears.
    private static let dropoutFrames = 8
    private static let pitchRange = 70.0...800.0

    private let analyzer: VoiceQualityAnalyzer
    private let hop: Int
    private let onReading: @Sendable (VoiceQuality?) -> Void
    private var samples: [Float] = []
    private var recent: [VoiceQuality] = []
    private var missedRun = 0
    private var hasReading = false

    init(sampleRate: Double, onReading: @escaping @Sendable (VoiceQuality?) -> Void) {
        analyzer = VoiceQualityAnalyzer(sampleRate: sampleRate)
        hop = analyzer.frameLength / 2
        self.onReading = onReading
    }

    /// `pitch` is the current smoothed F0, nil when unvoiced.
    func process(_ incoming: UnsafeBufferPointer<Float>, pitch: Double?) {
        samples.append(contentsOf: incoming)
        while samples.count >= analyzer.frameLength {
            var quality: VoiceQuality?
            if let pitch, Self.pitchRange.contains(pitch) {
                quality = samples.withUnsafeBufferPointer { analyzer.analyze($0, pitch: pitch) }
            }
            samples.removeFirst(hop)
            update(with: quality)
        }
    }

    private func update(with quality: VoiceQuality?) {
        guard let quality else {
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
        recent.append(quality)
        if recent.count > Self.windowCount { recent.removeFirst() }
        guard recent.count >= Self.minimumFrames else { return }
        hasReading = true
        onReading(VoiceQuality.median(of: recent))
    }
}

extension VoiceQuality {
    /// Field-by-field median; nil fields are skipped.
    static func median(of values: [VoiceQuality]) -> VoiceQuality? {
        guard let h1h2 = VoiceMapper.median(values.map(\.h1h2)),
              let alpha = VoiceMapper.median(values.map(\.alphaRatio)),
              let cpp = VoiceMapper.median(values.map(\.cpp)),
              let hnr = VoiceMapper.median(values.map(\.hnr)),
              let level = VoiceMapper.median(values.map(\.level)) else { return nil }
        return VoiceQuality(h1h2: h1h2, alphaRatio: alpha, cpp: cpp, hnr: hnr,
                            jitter: VoiceMapper.median(values.compactMap(\.jitter)),
                            shimmer: VoiceMapper.median(values.compactMap(\.shimmer)),
                            level: level)
    }
}
