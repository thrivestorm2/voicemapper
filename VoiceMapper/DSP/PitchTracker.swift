import Foundation

/// What the pitch tracker reports while the user is voicing.
struct PitchReading: Equatable, Sendable {
    let frequency: Double
    let note: Note
}

/// Turns the live mic stream into smoothed pitch readings: buffers samples,
/// runs `PitchDetector` on overlapping frames, takes a short median and holds
/// the last note through brief dropouts. Called only from the audio thread, so
/// make a new one whenever the engine is rebuilt.
final class PitchTracker: @unchecked Sendable {
    /// Samples between detections (~21 ms at 48 kHz).
    private static let hop = 1024
    private static let medianCount = 5
    /// Unvoiced frames in a row before the reading clears (~120 ms).
    private static let dropoutFrames = 6
    /// A drop of more than this many semitones is suspect (usually an octave
    /// error as a note fades or goes creaky) ...
    private static let suspectDrop = 4.0
    /// ... and is only believed after this many frames in a row (~210 ms);
    /// until then the last note is held.
    private static let jumpFrames = 10

    private var detector: PitchDetector
    private let onReading: @Sendable (PitchReading?) -> Void
    private var samples: [Float] = []
    private var recent: [Double] = []
    private var unvoicedRun = 0
    private var hasReading = false
    private var lastFrequency: Double?
    /// Frames in a row that disagree with the current note by a large drop.
    private var jumpRun = 0

    /// Latest smoothed F0, nil while unvoiced. Audio thread only.
    var currentFrequency: Double? { hasReading ? lastFrequency : nil }

    init(sampleRate: Double, onReading: @escaping @Sendable (PitchReading?) -> Void) {
        detector = PitchDetector(sampleRate: sampleRate)
        self.onReading = onReading
    }

    func process(_ incoming: UnsafeBufferPointer<Float>) {
        samples.append(contentsOf: incoming)
        let needed = detector.frameLength
        while samples.count >= needed {
            let result = samples.withUnsafeBufferPointer { detector.detect($0) }
            samples.removeFirst(Self.hop)
            update(with: result)
        }
    }

    private func update(with result: PitchDetector.Result?) {
        guard let result else {
            unvoicedRun += 1
            if unvoicedRun >= Self.dropoutFrames, hasReading {
                hasReading = false
                jumpRun = 0
                recent.removeAll()
                onReading(nil)
            }
            return
        }
        unvoicedRun = 0
        if hasReading, let last = lastFrequency,
           12 * log2(result.frequency / last) < -Self.suspectDrop {
            jumpRun += 1
            if jumpRun < Self.jumpFrames { return }
            recent.removeAll()
        }
        jumpRun = 0
        recent.append(result.frequency)
        if recent.count > Self.medianCount { recent.removeFirst() }
        let median = recent.sorted()[recent.count / 2]
        hasReading = true
        lastFrequency = median
        onReading(PitchReading(frequency: median, note: Note(frequency: median)))
    }
}
