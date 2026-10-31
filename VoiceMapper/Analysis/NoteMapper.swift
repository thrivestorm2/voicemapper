import Foundation

/// A pitch as a named equal-tempered note (A4 = 440 Hz).
struct Note: Hashable, Sendable {
    let midi: Int

    private static let names = ["C", "C♯", "D", "D♯", "E", "F", "F♯", "G", "G♯", "A", "A♯", "B"]

    /// Nearest note to a frequency.
    init(frequency: Double) {
        midi = Int(Self.midiValue(frequency: frequency).rounded())
    }

    init(midi: Int) {
        self.midi = midi
    }

    /// e.g. "G4"
    var name: String { Self.names[((midi % 12) + 12) % 12] + String(midi / 12 - 1) }

    /// Exact frequency of the note.
    var frequency: Double { 440 * pow(2, Double(midi - 69) / 12) }

    /// Fractional MIDI number: 69 + 12·log2(f/440).
    static func midiValue(frequency: Double) -> Double {
        69 + 12 * log2(frequency / 440)
    }
}
