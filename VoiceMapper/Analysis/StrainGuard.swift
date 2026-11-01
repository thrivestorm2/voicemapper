import Foundation
import Observation

/// Heuristic strain watch and daily practice cap. See docs/PLAN.md §5.
/// Not diagnostic: it compares the user against their own reference (the
/// baseline, else the first minute of the session) and suggests rest.
/// Fed 5×/second by `SessionRecorder`.
@MainActor
@Observable
final class StrainGuard {
    enum Health: Equatable {
        /// Not voicing, or no reference yet.
        case unknown
        case steady
        /// One measure is off its reference.
        case watch
        /// Two or more measures are off: signs of strain.
        case strain
    }

    enum Alert: Equatable {
        case strain(reasons: [String])
        case dailyCap(minutes: Int)
    }

    static let alertsKey = "safety.strainAlerts"
    static let capKey = "safety.dailyCapMinutes"
    static let defaultCapMinutes = 30
    static let restLength: TimeInterval = 5 * 60
    /// No new strain alert this soon after the last one.
    static let cooldown: TimeInterval = 5 * 60
    /// "5 more minutes" on the cap alert.
    static let capExtension = 5

    // Each rule looks back over a wall-clock window and needs a minimum of
    // voiced time inside it (speech is only ~50% voiced).
    private static let healthWindow = 30.0
    private static let healthMinimum = 10.0
    private static let rangeWindow = 60.0
    private static let rangeMinimum = 25.0
    private static let rangeShare = 0.75
    private static let loudWindow = 30.0
    private static let loudMinimum = 12.0
    /// Seconds of session voice used as the reference when there's no baseline.
    private static let sessionReferenceLength = 60.0
    private static let sessionReferenceMinimum = 30.0

    private(set) var health: Health = .unknown
    var alert: Alert?
    private(set) var restUntil: Date?
    /// Practice (capture) time today, including the open session.
    private(set) var todaySeconds = 0.0

    var capMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: Self.capKey)
        return v > 0 ? v : Self.defaultCapMinutes
    }

    private var alertsEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.alertsKey) as? Bool ?? true
    }

    private struct Sample {
        let time: Date
        let hz: Double
        let quality: VoiceQuality?
    }

    private var samples: [Sample] = []
    private var baseline: QualitySummary?
    private var topHz: Double?
    private var sessionReference: [VoiceQuality] = []
    private var cooldownUntil: Date?
    private var extraMinutes = 0
    private var day = Calendar.current.startOfDay(for: .now)

    /// Called when capture starts. `topHz` is the top of the comfortable range
    /// (an octave above the baseline median), nil without a baseline.
    func beginSession(priorToday: Double, baseline: QualitySummary?, topHz: Double?) {
        rollDay()
        todaySeconds = priorToday
        self.baseline = baseline
        self.topHz = topHz
        samples = []
        sessionReference = []
        health = .unknown
    }

    /// Sets today's total while idle (launch, after a session is saved).
    func setToday(_ seconds: Double) {
        rollDay()
        todaySeconds = seconds
    }

    func endSession() {
        samples = []
        health = .unknown
    }

    func observe(tick: Double, pitch: Double?, quality: VoiceQuality?, now: Date = .now) {
        rollDay()
        todaySeconds += tick
        if alert == nil, todaySeconds >= Double(capMinutes + extraMinutes) * 60 {
            alert = .dailyCap(minutes: capMinutes)
        }
        guard let pitch else { health = .unknown; return }

        samples.append(Sample(time: now, hz: pitch, quality: quality))
        let oldest = now.addingTimeInterval(-Self.rangeWindow * 2)
        if let first = samples.firstIndex(where: { $0.time >= oldest }), first > 0 {
            samples.removeFirst(first)
        }
        if baseline == nil, let quality,
           Double(sessionReference.count) * tick < Self.sessionReferenceLength {
            sessionReference.append(quality)
        }

        let reasons = healthReasons(tick: tick)
        health = reasons.map { $0.count >= 2 ? .strain : $0.isEmpty ? .steady : .watch } ?? .unknown

        guard alertsEnabled, alert == nil, now >= (cooldownUntil ?? .distantPast) else { return }
        var triggers = (reasons?.count ?? 0) >= 2 ? reasons! : []
        if sustainedHigh(tick: tick) { triggers.append("a long stretch at the top of your range") }
        if sustainedLoud(tick: tick) { triggers.append("speaking loudly for a while") }
        if !triggers.isEmpty {
            alert = .strain(reasons: triggers)
            cooldownUntil = now.addingTimeInterval(Self.cooldown)
            samples = []
        }
    }

    // MARK: - Actions

    /// Starts a 5-minute rest. The caller stops capture.
    func rest() {
        alert = nil
        restUntil = .now.addingTimeInterval(Self.restLength)
    }

    func endRest() { restUntil = nil }

    func dismiss() {
        if case .dailyCap = alert { extraMinutes += Self.capExtension }
        alert = nil
    }

    /// "Stop for today" on the cap alert. The caller stops capture; the alert
    /// returns if capture starts again today.
    func stopForToday() { alert = nil }

    // MARK: - Rules

    private var reference: QualitySummary? {
        if let baseline { return baseline }
        guard Double(sessionReference.count) * 0.2 >= Self.sessionReferenceMinimum else { return nil }
        return QualitySummary(sessionReference)
    }

    /// Health measures that have moved past their reference over the last
    /// 30 s. Nil until there's a reference and enough voice.
    private func healthReasons(tick: Double) -> [String]? {
        guard let ref = reference else { return nil }
        let recent = voiced(within: Self.healthWindow).compactMap(\.quality)
        guard Double(recent.count) * tick >= Self.healthMinimum,
              let now = VoiceQuality.median(of: recent) else { return nil }
        var reasons: [String] = []
        if now.hnr < ref.hnr - 4 || now.cpp < ref.cpp - 4 {
            reasons.append("a less clear, noisier tone")
        }
        if let j = now.jitter, let r = ref.jitter, j > max(1.6 * r, r + 0.5) {
            reasons.append("less steady pitch")
        }
        if let s = now.shimmer, let r = ref.shimmer, s > max(1.5 * r, r + 2) {
            reasons.append("less steady loudness")
        }
        return reasons
    }

    private func sustainedHigh(tick: Double) -> Bool {
        guard let topHz else { return false }
        let recent = voiced(within: Self.rangeWindow)
        guard Double(recent.count) * tick >= Self.rangeMinimum else { return false }
        let high = recent.filter { $0.hz >= topHz }.count
        return Double(high) >= Self.rangeShare * Double(recent.count)
    }

    /// Louder than the reference by 10 dB, or (with no reference) above
    /// −14 dBFS, which is close to shouting into the iPhone mic.
    private func sustainedLoud(tick: Double) -> Bool {
        let levels = voiced(within: Self.loudWindow).compactMap(\.quality?.level)
        guard Double(levels.count) * tick >= Self.loudMinimum, let level = median(levels) else { return false }
        let limit = reference.map { $0.level + 10 } ?? -14
        return level > limit
    }

    private func voiced(within seconds: Double) -> ArraySlice<Sample> {
        let cutoff = (samples.last?.time ?? .now).addingTimeInterval(-seconds)
        let first = samples.firstIndex { $0.time >= cutoff } ?? samples.endIndex
        return samples[first...]
    }

    private func rollDay() {
        let today = Calendar.current.startOfDay(for: .now)
        guard today != day else { return }
        day = today
        todaySeconds = 0
        extraMinutes = 0
    }
}
