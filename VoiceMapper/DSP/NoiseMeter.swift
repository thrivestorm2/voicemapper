import Accelerate
import Foundation

/// Estimates the background noise floor: the 10th-percentile level of short
/// buffers over the last ~3 s. Speech has gaps between syllables, so the
/// quietest moments are the room, even while talking. Called only from the
/// audio thread, so make a new one whenever the engine is rebuilt.
final class NoiseMeter: @unchecked Sendable {
    private static let window = 3.0
    private static let reportInterval = 0.25

    private let onFloor: @Sendable (Double) -> Void
    private let sampleRate: Double
    private var levels: [Double] = []
    private var sinceReport = 0.0

    init(sampleRate: Double, onFloor: @escaping @Sendable (Double) -> Void) {
        self.sampleRate = sampleRate
        self.onFloor = onFloor
    }

    func process(_ samples: UnsafeBufferPointer<Float>) {
        guard let base = samples.baseAddress, samples.count > 0 else { return }
        var meanSquare: Float = 0
        vDSP_measqv(base, 1, &meanSquare, vDSP_Length(samples.count))
        let seconds = Double(samples.count) / sampleRate
        levels.append(10 * log10(Double(meanSquare) + 1e-12))
        let capacity = Int(Self.window / seconds)
        if levels.count > capacity { levels.removeFirst(levels.count - capacity) }
        sinceReport += seconds
        guard sinceReport >= Self.reportInterval, levels.count >= capacity / 2 else { return }
        sinceReport = 0
        if let floor = percentile(levels, 0.1) { onFloor(floor) }
    }
}
