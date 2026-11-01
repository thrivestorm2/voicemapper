import Foundation

/// Turns one frame's formants into a formant spacing (ΔF) estimate.
///
/// A uniform tube closed at one end resonates at Fi = (2i − 1)/2 · ΔF, with
/// ΔF = c / 2L. Fitting that line through F1–F4 by least squares (Reby &
/// McComb 2003) gives ΔF; a shorter tract or a more forward tongue / smaller
/// mouth space raises it, which listeners hear as brighter resonance.
enum ResonanceScorer {
    /// Speed of sound in warm, moist air (cm/s).
    static let speedOfSound = 35_000.0

    /// ΔF mapped to score 0 and 100. Typical adult averages across vowels are
    /// roughly 1000 Hz (usually read male) and 1190 Hz (usually read female),
    /// from Hillenbrand et al. 1995. To be checked against Praat in S13.
    static let darkSpacing = 900.0
    static let brightSpacing = 1300.0

    /// Plausible range for each formant number (Hillenbrand et al. 1995, with
    /// margin). Frames that break these are usually mis-tracked and dropped.
    private static let ranges: [ClosedRange<Double>] = [
        200...1200,   // F1
        800...3300,   // F2
        1400...4300,  // F3
        2600...5300,  // F4
    ]
    /// Widest bandwidth accepted for F1 and F2.
    private static let maxLowBandwidth = 400.0

    /// ΔF in Hz from formants sorted by frequency, or nil if F1–F3 aren't all
    /// plausible. F4 is used when present and plausible.
    ///
    /// With a higher voice, LPC often puts an extra peak on a harmonic between
    /// F1 and F2 (e.g. ~600 Hz in "ee" at F0 300 Hz). So a peak that is too
    /// low or too wide for the next formant number is passed over rather than
    /// shifting every number up; one that is too high ends the search.
    static func spacing(of formants: [FormantAnalyzer.Formant]) -> Double? {
        guard formants.count >= 3 else { return nil }
        var used: [Double] = []
        for formant in formants {
            let slot = used.count
            guard slot < ranges.count else { break }
            if slot < 2, formant.bandwidth > maxLowBandwidth { continue }
            let f = formant.frequency
            if f < ranges[slot].lowerBound { continue }
            if let last = used.last, f - last < 150 { continue }
            guard f <= ranges[slot].upperBound else { break }
            used.append(f)
        }
        guard used.count >= 3 else { return nil }

        var numerator = 0.0, denominator = 0.0
        for (i, f) in used.enumerated() {
            let k = Double(2 * i + 1) / 2
            numerator += k * f
            denominator += k * k
        }
        return numerator / denominator
    }

    /// 0 (darkest) … 100 (brightest).
    static func score(spacing: Double) -> Double {
        let t = (spacing - darkSpacing) / (brightSpacing - darkSpacing)
        return min(100, max(0, t * 100))
    }

    /// Apparent vocal tract length in cm.
    static func tractLength(spacing: Double) -> Double {
        speedOfSound / (2 * spacing)
    }
}
