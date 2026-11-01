import SwiftUI

/// Smooth blend of how a voice at a given pitch and resonance is typically
/// heard: mostly male, ambiguous or mostly female. The three weights always sum
/// to 1, so zones fade into each other instead of ending at hard edges.
///
/// Built from published central values rather than a fitted model of any one
/// study, so treat it as typical, not exact:
/// - Pitch is the strongest cue. Men's average speaking F0 is ~120-130 Hz and
///   women's ~210-220 Hz (Hillenbrand et al. 1995); voices in roughly
///   145-185 Hz are the ones most often judged ambiguous (Gelfer & Mikos 2005).
///   The logistic is centred at 165 Hz.
/// - Resonance is a real but weaker cue (Hillenbrand & Clark 2009): average
///   formant spacing is ~1000 Hz for men and ~1190 Hz for women, which is
///   score 25 and ~72 on our scale. Moving 50 score points counts for about as
///   much as ~3.75 semitones of pitch here.
/// To be tuned against listener data / Praat checks in S13.
enum VoicePerception {
    struct Blend: Equatable, Sendable {
        let male: Double
        let ambiguous: Double
        let female: Double
    }

    static let centerFrequency = 165.0
    /// Logistic steepness per semitone of pitch.
    private static let pitchSlope = 0.8
    /// Logistic steepness per resonance score point.
    private static let resonanceSlope = 0.06
    /// Half-width of the ambiguous band in logistic units.
    private static let ambiguousHalfWidth = 1.1

    static func blend(frequency: Double, score: Double) -> Blend {
        let semitones = 12 * log2(frequency / centerFrequency)
        let z = pitchSlope * semitones + resonanceSlope * (score - 50)
        let female = sigmoid(z - ambiguousHalfWidth)
        let male = 1 - sigmoid(z + ambiguousHalfWidth)
        return Blend(male: male, ambiguous: max(0, 1 - male - female), female: female)
    }

    /// Weighted mix of the three zone colours.
    static func color(_ blend: Blend) -> Color {
        let m = PerceivedGender.male.rgb, a = PerceivedGender.ambiguous.rgb, f = PerceivedGender.female.rgb
        return Color(
            red: m.0 * blend.male + a.0 * blend.ambiguous + f.0 * blend.female,
            green: m.1 * blend.male + a.1 * blend.ambiguous + f.1 * blend.female,
            blue: m.2 * blend.male + a.2 * blend.ambiguous + f.2 * blend.female
        )
    }

    /// 0–1: how common voices are at this spot, from each zone's typical pitch
    /// and resonance, weighted by the blend. Drives how strong the colour is.
    static func commonness(frequency: Double, score: Double, blend: Blend) -> Double {
        let zones: [(PerceivedGender, Double)] = [(.male, blend.male), (.ambiguous, blend.ambiguous), (.female, blend.female)]
        return zones.reduce(0) { sum, entry in
            sum + entry.1 * entry.0.commonness(at: frequency) * entry.0.resonanceCommonness(at: score)
        }
    }

    /// Time-weighted average blend over every grid cell of a session, so the
    /// whole session counts, not a single median. Nil without resonance data.
    static func blend(of cells: [GridCellCount]) -> Blend? {
        var male = 0.0, ambiguous = 0.0, female = 0.0, total = 0.0
        for cell in cells where cell.seconds > 0 {
            let hz = 440 * pow(2, (Double(cell.pitchMidi) - 69) / 12)
            let score = (Double(cell.resonanceBin) + 0.5) * GridCellCount.resonanceBinWidth
            let b = blend(frequency: hz, score: score)
            male += b.male * cell.seconds
            ambiguous += b.ambiguous * cell.seconds
            female += b.female * cell.seconds
            total += cell.seconds
        }
        guard total > 0 else { return nil }
        return Blend(male: male / total, ambiguous: ambiguous / total, female: female / total)
    }

    /// Plain-words summary of a blend, e.g. for VoiceOver.
    static func description(_ b: Blend) -> String {
        func pct(_ v: Double) -> Int { Int((v * 100).rounded()) }
        let lead: String
        if b.female >= 0.6 { lead = "Mostly reads feminine" }
        else if b.male >= 0.6 { lead = "Mostly reads masculine" }
        else if b.ambiguous >= max(b.male, b.female) { lead = "Mostly reads androgynous" }
        else { lead = "Mixed" }
        return "\(lead): \(pct(b.female))% feminine, \(pct(b.ambiguous))% androgynous, \(pct(b.male))% masculine"
    }

    private static func sigmoid(_ z: Double) -> Double { 1 / (1 + exp(-z)) }
}
