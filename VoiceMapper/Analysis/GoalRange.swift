import Foundation

/// A pitch range the user is aiming for, as a span of MIDI notes (inclusive).
/// Persisted for now as two `@AppStorage` ints (0 = unset); moves to SwiftData
/// with the rest of the goal in S8/S12.
struct GoalRange: Equatable, Sendable {
    static let lowKey = "goalLowMidi"
    static let highKey = "goalHighMidi"

    let low: Int
    let high: Int

    init?(low: Int, high: Int) {
        guard low > 0, high >= low else { return nil }
        self.low = low
        self.high = high
    }

    func contains(midi: Int) -> Bool { (low...high).contains(midi) }

    /// 0–1: 1 inside the range, falling linearly to 0 at 6 semitones outside it.
    func closeness(of frequency: Double) -> Double {
        let midi = Note.midiValue(frequency: frequency)
        let distance = max(Double(low) - midi, midi - Double(high), 0)
        return max(0, 1 - distance / 6)
    }

    /// Which way to move to reach the range; nil when inside it.
    func direction(of frequency: Double) -> Direction? {
        let midi = Note.midiValue(frequency: frequency)
        if midi < Double(low) - 0.5 { return .higher }
        if midi > Double(high) + 0.5 { return .lower }
        return nil
    }

    enum Direction { case higher, lower }
}
