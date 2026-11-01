import Accelerate
import Foundation

/// Voice-quality measures for one voiced frame. See docs/PLAN.md §5.
/// All are heuristics meant for comparing the user against their own baseline,
/// not clinical values; absolute numbers differ somewhat from Praat.
struct VoiceQuality: Equatable, Sendable {
    /// Level of the 1st minus the 2nd harmonic, dB (uncorrected for formants).
    /// Higher means a lighter, breathier source; lower a heavier, pressed one.
    var h1h2: Double
    /// Spectral tilt as an alpha ratio: energy 1–5 kHz minus 50 Hz–1 kHz, dB.
    /// Closer to 0 means more high-frequency energy (heavier, louder).
    var alphaRatio: Double
    /// Cepstral peak prominence, dB (Hillenbrand et al. 1994). Higher = clearer.
    var cpp: Double
    /// Harmonics-to-noise ratio from the autocorrelation peak, dB (Boersma 1993).
    var hnr: Double
    /// Local jitter, % (cycle-to-cycle period change). Nil if cycles weren't trackable.
    var jitter: Double?
    /// Local shimmer, % (cycle-to-cycle peak amplitude change).
    var shimmer: Double?
    /// RMS level, dB full scale.
    var level: Double

    /// 0 (lighter) … 1 (heavier), from H1–H2 and spectral tilt. Shown neutrally.
    var weight: Double { Self.weight(h1h2: h1h2, alphaRatio: alphaRatio) }

    static func weight(h1h2: Double, alphaRatio: Double) -> Double {
        func unit(_ v: Double) -> Double { min(max(v, 0), 1) }
        // H1–H2 ≈ +12 dB light … −4 dB heavy; alpha ≈ −28 dB light … −8 dB heavy.
        return 0.5 * unit((12 - h1h2) / 16) + 0.5 * unit((alphaRatio + 28) / 20)
    }
}

/// Computes `VoiceQuality` from one frame of mono samples, given the current F0.
/// Not thread-safe: one instance per stream.
final class VoiceQualityAnalyzer {
    let sampleRate: Double
    /// Samples `analyze` reads: the power of two covering ≥ 80 ms.
    let frameLength: Int

    /// Frames quieter than this are skipped.
    private static let silenceLevel = -55.0

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private var windowed: [Float]
    private var real: [Float]
    private var imag: [Float]
    private var spectrum: [Double]   // dB, bins 0...n/2
    private var symmetric: [Float]   // dB spectrum mirrored to length n

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        var n = 1024
        while Double(n) < 0.08 * sampleRate { n *= 2 }
        frameLength = n
        log2n = vDSP_Length(n.trailingZeroBitCount)
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: n, isHalfWindow: false)
        windowed = [Float](repeating: 0, count: n)
        real = [Float](repeating: 0, count: n / 2)
        imag = [Float](repeating: 0, count: n / 2)
        spectrum = [Double](repeating: 0, count: n / 2 + 1)
        symmetric = [Float](repeating: 0, count: n)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Nil for quiet frames or an F0 the frame is too short to measure.
    func analyze(_ x: UnsafeBufferPointer<Float>, pitch f0: Double) -> VoiceQuality? {
        let n = frameLength
        guard x.count >= n, let base = x.baseAddress, f0 > 0 else { return nil }
        let period = sampleRate / f0
        guard Double(n) >= 4 * period else { return nil }

        var meanSquare: Float = 0
        vDSP_measqv(base, 1, &meanSquare, vDSP_Length(n))
        let level = 10 * log10(Double(meanSquare) + 1e-12)
        guard level > Self.silenceLevel else { return nil }

        guard let hnr = Self.hnr(base, count: n, period: period) else { return nil }
        let (jitter, shimmer) = Self.perturbation(base, count: n, period: period)

        // Power spectrum (dB) of the Hann-windowed frame.
        vDSP_vmul(base, 1, window, 1, &windowed, 1, vDSP_Length(n))
        powerSpectrum(of: windowed)
        let binWidth = sampleRate / Double(n)

        let h1 = harmonicPeak(at: f0, binWidth: binWidth)
        let h2 = harmonicPeak(at: 2 * f0, binWidth: binWidth)
        let alpha = bandPower(1000, min(5000, sampleRate / 2), binWidth)
            - bandPower(50, 1000, binWidth)
        guard let cpp = cepstralPeakProminence(f0: f0) else { return nil }

        return VoiceQuality(h1h2: h1 - h2, alphaRatio: alpha, cpp: cpp, hnr: hnr,
                            jitter: jitter, shimmer: shimmer, level: level)
    }

    // MARK: - Spectrum

    /// Fills `spectrum` with 10·log10 power for bins 0...n/2. Absolute scale
    /// doesn't matter: every measure here is a difference of dB values.
    private func powerSpectrum(of input: [Float]) {
        let half = frameLength / 2
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                input.withUnsafeBufferPointer { inBuf in
                    inBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        // zrip packs DC in realp[0] and Nyquist in imagp[0].
        spectrum[0] = 10 * log10(Double(real[0] * real[0]) + 1e-20)
        spectrum[half] = 10 * log10(Double(imag[0] * imag[0]) + 1e-20)
        for k in 1..<half {
            spectrum[k] = 10 * log10(Double(real[k] * real[k] + imag[k] * imag[k]) + 1e-20)
        }
    }

    /// Highest bin within ±10% (at least ±1 bin) of `frequency`.
    private func harmonicPeak(at frequency: Double, binWidth: Double) -> Double {
        let center = frequency / binWidth
        let radius = max(1.0, 0.1 * center)
        let lo = max(1, Int((center - radius).rounded(.down)))
        let hi = min(frameLength / 2, Int((center + radius).rounded(.up)))
        guard lo <= hi else { return -200 }
        return spectrum[lo...hi].max() ?? -200
    }

    private func bandPower(_ lowHz: Double, _ highHz: Double, _ binWidth: Double) -> Double {
        let lo = max(1, Int(lowHz / binWidth)), hi = min(frameLength / 2, Int(highHz / binWidth))
        guard lo < hi else { return -200 }
        var sum = 0.0
        for k in lo...hi { sum += pow(10, spectrum[k] / 10) }
        return 10 * log10(sum + 1e-20)
    }

    /// Cepstrum of the dB spectrum, in dB; the peak near the pitch period
    /// minus a regression line fitted over 1 ms … 1/55 Hz quefrency.
    private func cepstralPeakProminence(f0: Double) -> Double? {
        let n = frameLength, half = n / 2
        for k in 0...half { symmetric[k] = Float(spectrum[k]) }
        for k in 1..<half { symmetric[n - k] = symmetric[k] }
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in
                var split = DSPSplitComplex(realp: re.baseAddress!, imagp: im.baseAddress!)
                symmetric.withUnsafeBufferPointer { inBuf in
                    inBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
            }
        }
        // For q in 1..<n/2, realp[q] = 2·Σ L[k]·cos(2πkq/n); the 1/(2n) scale
        // only shifts every dB value equally, so it cancels in the prominence.
        let qLow = max(2, Int(sampleRate * 0.001))
        let qHigh = min(half - 1, Int(sampleRate / 55))
        guard qHigh > qLow + 10 else { return nil }
        func dB(_ q: Int) -> Double { 20 * log10(Double(abs(real[q])) / Double(2 * n) + 1e-9) }

        var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0
        for q in qLow...qHigh {
            let x = Double(q), y = dB(q)
            sx += x; sy += y; sxx += x * x; sxy += x * y
        }
        let count = Double(qHigh - qLow + 1)
        let slope = (count * sxy - sx * sy) / (count * sxx - sx * sx)
        let intercept = (sy - slope * sx) / count

        let q0 = sampleRate / f0
        let lo = max(qLow, Int(0.85 * q0)), hi = min(qHigh, Int(1.15 * q0))
        guard lo <= hi else { return nil }
        let peak = (lo...hi).max { dB($0) < dB($1) }!
        return dB(peak) - (intercept + slope * Double(peak))
    }

    // MARK: - Periodicity

    /// HNR from the normalised autocorrelation peak r near the period:
    /// 10·log10(r / (1 − r)).
    static func hnr(_ x: UnsafePointer<Float>, count n: Int, period: Double) -> Double? {
        let t0 = Int(period.rounded())
        let radius = max(2, Int(0.03 * period))
        let length = n - t0 - radius - 2
        guard t0 - radius - 1 >= 2, length > 2 * t0 else { return nil }
        let len = vDSP_Length(length)
        func r(_ lag: Int) -> Double {
            var xy: Float = 0, xx: Float = 0, yy: Float = 0
            vDSP_dotpr(x, 1, x + lag, 1, &xy, len)
            vDSP_svesq(x, 1, &xx, len)
            vDSP_svesq(x + lag, 1, &yy, len)
            let d = Double(xx) * Double(yy)
            return d > 0 ? Double(xy) / d.squareRoot() : 0
        }
        var best = t0, bestR = -1.0
        for lag in (t0 - radius)...(t0 + radius) {
            let v = r(lag)
            if v > bestR { bestR = v; best = lag }
        }
        let a = r(best - 1), c = r(best + 1)
        let curve = a - 2 * bestR + c
        var peak = bestR
        if curve < 0 {
            let shift = 0.5 * (a - c) / curve
            peak = bestR - 0.25 * (a - c) * shift
        }
        peak = min(max(peak, 1e-4), 0.9999)
        return 10 * log10(peak / (1 - peak))
    }

    /// Local jitter and shimmer (%) by picking one waveform peak per cycle.
    /// Nil when fewer than 5 cycles are found or the cycles look mis-tracked.
    static func perturbation(_ x: UnsafePointer<Float>, count n: Int, period: Double) -> (Double?, Double?) {
        guard period >= 8 else { return (nil, nil) }
        // Track whichever polarity has the larger peaks.
        var top: Float = 0, bottom: Float = 0
        vDSP_maxv(x, 1, &top, vDSP_Length(n))
        vDSP_minv(x, 1, &bottom, vDSP_Length(n))
        let sign: Float = top >= -bottom ? 1 : -1

        func peak(_ lo: Int, _ hi: Int) -> Int {
            var best = lo
            for i in lo...hi where sign * x[i] > sign * x[best] { best = i }
            return best
        }

        var times: [Double] = [], amps: [Double] = []
        var index = peak(1, min(n - 2, Int(period)))
        while true {
            // Parabolic refinement of the peak's time and height.
            let a = Double(sign * x[index - 1]), b = Double(sign * x[index]), c = Double(sign * x[index + 1])
            let curve = a - 2 * b + c
            let shift = curve < 0 ? 0.5 * (a - c) / curve : 0
            times.append(Double(index) + shift)
            amps.append(b - 0.25 * (a - c) * shift)
            let lo = index + Int(0.75 * period), hi = index + Int(1.25 * period)
            guard hi <= n - 2 else { break }
            index = peak(lo, hi)
        }
        guard times.count >= 5 else { return (nil, nil) }

        let periods = zip(times.dropFirst(), times).map { $0 - $1 }
        guard periods.allSatisfy({ $0 > 0.8 * period && $0 < 1.2 * period }),
              amps.allSatisfy({ $0 > 0 }) else { return (nil, nil) }

        func local(_ v: [Double]) -> Double {
            let diffs = zip(v.dropFirst(), v).map { abs($0 - $1) }
            let mean = v.reduce(0, +) / Double(v.count)
            return 100 * (diffs.reduce(0, +) / Double(diffs.count)) / mean
        }
        return (local(periods), local(amps))
    }
}
