import Accelerate
import Foundation

/// LPC formant estimator. Downsamples one frame to ~11–12 kHz (enough for
/// F1–F4), applies pre-emphasis and a Hamming window, fits an all-pole model
/// (autocorrelation + Levinson–Durbin) and turns the polynomial's roots into
/// formant frequencies and bandwidths. Not thread-safe: one instance per stream.
struct FormantAnalyzer {
    struct Formant: Sendable, Equatable {
        let frequency: Double
        let bandwidth: Double
    }

    /// Input samples `analyze` reads (≈43 ms at 48 kHz).
    let frameLength: Int
    /// Rate after downsampling.
    let analysisRate: Double

    private static let targetRate = 11_025.0
    /// Lowest frequency kept as a formant; below this is usually F0 or noise.
    private static let minFormant = 180.0
    /// Wider resonances than this are too damped to be formants.
    private static let maxBandwidth = 600.0

    private let factor: Int
    private let order: Int
    private let lowPass: [Float]
    private let window: [Float]
    private var decimated: [Float]
    private var emphasized: [Float]

    init(sampleRate: Double) {
        factor = max(1, Int((sampleRate / Self.targetRate).rounded()))
        analysisRate = sampleRate / Double(factor)
        // Rule of thumb: two poles per kHz of bandwidth plus two for the
        // glottal source and lip radiation.
        order = 4 + Int(analysisRate / 1000)
        let analysisCount = Int(analysisRate * 0.040)  // 40 ms window

        // Windowed-sinc anti-alias filter, cutoff 90% of the new Nyquist.
        if factor > 1 {
            let taps = 16 * factor + 1
            let cutoff = 0.9 * 0.5 / Double(factor)  // cycles per input sample
            let mid = Double(taps - 1) / 2
            var filter = (0..<taps).map { i -> Float in
                let n = Double(i) - mid
                let sinc = n == 0 ? 2 * cutoff : sin(2 * .pi * cutoff * n) / (.pi * n)
                let hamming = 0.54 - 0.46 * cos(2 * .pi * Double(i) / Double(taps - 1))
                return Float(sinc * hamming)
            }
            let sum = filter.reduce(0, +)
            filter = filter.map { $0 / sum }
            lowPass = filter
        } else {
            lowPass = [1]
        }
        frameLength = (analysisCount - 1) * factor + lowPass.count

        window = vDSP.window(ofType: Float.self, usingSequence: .hamming,
                             count: analysisCount, isHalfWindow: false)
        decimated = [Float](repeating: 0, count: analysisCount)
        emphasized = [Float](repeating: 0, count: analysisCount)
    }

    /// Formants sorted by frequency, or nil if the frame is too short or silent.
    mutating func analyze(_ x: UnsafeBufferPointer<Float>) -> [Formant]? {
        guard x.count >= frameLength, let base = x.baseAddress else { return nil }
        let n = decimated.count

        vDSP_desamp(base, vDSP_Stride(factor), lowPass, &decimated,
                    vDSP_Length(n), vDSP_Length(lowPass.count))

        // Pre-emphasis from ~50 Hz (as Praat does), then window.
        let alpha = Float(exp(-2 * .pi * 50 / analysisRate))
        emphasized[0] = decimated[0]
        for i in 1..<n { emphasized[i] = decimated[i] - alpha * decimated[i - 1] }
        vDSP.multiply(emphasized, window, result: &emphasized)

        // Autocorrelation r[0...order].
        var r = [Double](repeating: 0, count: order + 1)
        emphasized.withUnsafeBufferPointer { e in
            for lag in 0...order {
                var sum: Float = 0
                vDSP_dotpr(e.baseAddress!, 1, e.baseAddress! + lag, 1, &sum, vDSP_Length(n - lag))
                r[lag] = Double(sum)
            }
        }
        guard r[0] > 1e-9 else { return nil }
        r[0] *= 1 + 1e-9  // tiny white-noise floor keeps Levinson stable

        guard let a = Self.levinson(r, order: order) else { return nil }
        // A(z) = 1 + a1 z⁻¹ + … + ap z⁻ᵖ  →  roots of zᵖ + a1 zᵖ⁻¹ + … + ap.
        let roots = Self.roots(of: a)

        let nyquist = analysisRate / 2
        var formants: [Formant] = []
        for z in roots where z.im > 0 {
            let frequency = atan2(z.im, z.re) * analysisRate / (2 * .pi)
            let bandwidth = -log(z.magnitude) * analysisRate / .pi
            guard frequency >= Self.minFormant, frequency <= nyquist - 100,
                  bandwidth > 0, bandwidth <= Self.maxBandwidth else { continue }
            formants.append(Formant(frequency: frequency, bandwidth: bandwidth))
        }
        return formants.sorted { $0.frequency < $1.frequency }
    }

    /// LPC coefficients [1, a1, …, ap], or nil if the model is unstable.
    static func levinson(_ r: [Double], order p: Int) -> [Double]? {
        var a = [Double](repeating: 0, count: p + 1)
        a[0] = 1
        var error = r[0]
        for i in 1...p {
            var acc = r[i]
            for j in 1..<i { acc += a[j] * r[i - j] }
            let k = -acc / error
            guard abs(k) < 1 else { return nil }
            let previous = a
            for j in 1..<i { a[j] = previous[j] + k * previous[i - j] }
            a[i] = k
            error *= 1 - k * k
        }
        return a
    }

    /// All complex roots of the monic polynomial c[0]·zⁿ + … + c[n] (c[0] = 1),
    /// by Aberth–Ehrlich iteration.
    static func roots(of c: [Double]) -> [Complex] {
        let degree = c.count - 1
        guard degree > 0 else { return [] }

        func evaluate(_ z: Complex) -> (Complex, Complex) {
            var p = Complex(c[0], 0)
            var dp = Complex(0, 0)
            for k in 1...degree {
                dp = dp * z + p
                p = p * z + Complex(c[k], 0)
            }
            return (p, dp)
        }

        // Start spread round a circle just inside the unit circle, offset so no
        // guess sits on the real axis.
        var z = (0..<degree).map { k -> Complex in
            let angle = 2 * Double.pi * (Double(k) + 0.25) / Double(degree)
            return Complex(0.9 * cos(angle), 0.9 * sin(angle))
        }
        for _ in 0..<80 {
            var largestStep = 0.0
            for i in 0..<degree {
                let (p, dp) = evaluate(z[i])
                if p.magnitude < 1e-14 { continue }
                let ratio = p / dp
                var sum = Complex(0, 0)
                for j in 0..<degree where j != i { sum = sum + Complex(1, 0) / (z[i] - z[j]) }
                let step = ratio / (Complex(1, 0) - ratio * sum)
                z[i] = z[i] - step
                largestStep = max(largestStep, step.magnitude)
            }
            if largestStep < 1e-12 { break }
        }
        return z
    }
}

/// Just enough complex arithmetic for root finding.
struct Complex: Sendable, Equatable {
    var re: Double
    var im: Double

    init(_ re: Double, _ im: Double) {
        self.re = re
        self.im = im
    }

    var magnitude: Double { (re * re + im * im).squareRoot() }

    static func + (a: Complex, b: Complex) -> Complex { Complex(a.re + b.re, a.im + b.im) }
    static func - (a: Complex, b: Complex) -> Complex { Complex(a.re - b.re, a.im - b.im) }
    static func * (a: Complex, b: Complex) -> Complex {
        Complex(a.re * b.re - a.im * b.im, a.re * b.im + a.im * b.re)
    }
    static func / (a: Complex, b: Complex) -> Complex {
        let d = b.re * b.re + b.im * b.im
        guard d > 0 else { return Complex(.infinity, 0) }
        return Complex((a.re * b.re + a.im * b.im) / d, (a.im * b.re - a.re * b.im) / d)
    }
}
