import Foundation

/// The resolved thing a countdown is counting down to, plus an optional title
/// (set only when showing a calendar event in `.nextEvent` mode).
struct ResolvedTarget: Equatable {
    let date: Date
    let title: String?
}

/// Single source of truth for "next calendar event vs. EOD/fixed target".
/// Pure and deterministic so it can be unit tested without EventKit.
enum CountdownTarget {
    static func resolve(_ countdown: Countdown,
                        now: Date,
                        nextEventStart: Date?,
                        nextEventTitle: String?) -> ResolvedTarget {
        if countdown.mode == .nextEvent,
           let start = nextEventStart,
           start > now {
            let windowEnd = now.addingTimeInterval(TimeInterval(countdown.eventLookaheadHours) * 3600)
            if start <= windowEnd {
                return ResolvedTarget(date: start, title: nextEventTitle)
            }
        }
        // daily, fixed, or next-event fallback to EOD
        return ResolvedTarget(date: countdown.currentTarget(now: now), title: nil)
    }
}
