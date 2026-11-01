import Foundation

/// A resonance range the user is aiming for, as scores on the 0–100 scale.
/// Stored for now as two `@AppStorage` doubles (both 0 = unset); moves to
/// SwiftData with the rest of the goal in S8/S12.
struct ResonanceGoal: Equatable, Sendable {
    static let lowKey = "goalResonanceLow"
    static let highKey = "goalResonanceHigh"
    /// Narrowest band a drag can set, so a tap doesn't leave a hairline.
    static let minimumWidth = 4.0

    let low: Double
    let high: Double

    init?(low: Double, high: Double) {
        guard high - low >= Self.minimumWidth else { return nil }
        self.low = max(0, low)
        self.high = min(100, high)
    }

    enum Direction { case brighter, darker }

    /// Which way to move to reach the range; nil when inside it.
    func direction(of score: Double) -> Direction? {
        if score < low { return .brighter }
        if score > high { return .darker }
        return nil
    }
}
