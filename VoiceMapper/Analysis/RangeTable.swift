import Foundation

/// How a speaking voice at a given pitch is typically perceived. These are
/// typical ranges from speaking-F0 research (Gelfer & Mikos 2005; Hillenbrand &
/// Clark 2009), not rules: resonance and intonation matter too.
enum PerceivedGender: Sendable {
    case male, ambiguous, female

    /// Single-letter label so colour is never the only cue.
    var letter: String {
        switch self {
        case .male: "M"
        case .ambiguous: "A"
        case .female: "F"
        }
    }

    var meaning: String {
        switch self {
        case .male: "usually read male"
        case .ambiguous: "ambiguous / androgynous"
        case .female: "usually read female"
        }
    }

    init(frequency: Double) {
        switch frequency {
        case ..<145: self = .male
        case ..<175: self = .ambiguous
        default: self = .female
        }
    }
}

/// Classical voice type whose range the note most typically sits in.
enum VoiceType: String, Sendable {
    case bass = "Bass"
    case baritone = "Bari"
    case tenor = "Tenor"
    case alto = "Alto"
    case mezzo = "Mezzo"
    case soprano = "Sop"

    init(midi: Int) {
        switch midi {
        case ..<48: self = .bass       // below C3
        case 48..<52: self = .baritone // C3–D♯3
        case 52..<55: self = .tenor    // E3–F♯3
        case 55..<65: self = .alto     // G3–E4
        case 65..<69: self = .mezzo    // F4–G♯4
        default: self = .soprano       // A4 and up
        }
    }
}

struct RangeRow: Identifiable, Sendable {
    let note: Note
    var id: Int { note.midi }
    var frequency: Double { note.frequency }
    var voiceType: VoiceType { VoiceType(midi: note.midi) }
    var perceived: PerceivedGender { PerceivedGender(frequency: note.frequency) }
}

enum RangeTable {
    /// Every semitone from C2 to C6, highest first like a piano turned on its end.
    static let rows: [RangeRow] = (36...84).reversed().map { RangeRow(note: Note(midi: $0)) }

    /// The row to highlight for a live reading, clamped to the table's ends.
    static func rowID(for note: Note) -> Int {
        min(max(note.midi, 36), 84)
    }
}
