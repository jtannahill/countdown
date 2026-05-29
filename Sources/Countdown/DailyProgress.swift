import Foundation

/// Pure: fraction [0,1] of a reset→target window that has elapsed at `now`,
/// or nil when `now` is outside the window (so the caller hides the indicator).
enum DailyProgress {
    static func fraction(now: Date, reset: Date, target: Date) -> Double? {
        let total = target.timeIntervalSince(reset)
        guard total > 0 else { return nil }
        let elapsed = now.timeIntervalSince(reset)
        guard elapsed >= 0, elapsed <= total else { return nil }
        return elapsed / total
    }
}
