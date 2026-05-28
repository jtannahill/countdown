import Foundation

/// One computed alert before it becomes a system notification request.
struct ScheduledAlert: Equatable {
    let countdownID: UUID
    let offsetMinutes: Int   // 0 == at-zero
    let fireDate: Date
    let title: String
    let body: String
}

/// A notification request ready to hand to the OS (id + content + fire date).
struct PlannedRequest: Equatable {
    let id: String
    let title: String
    let body: String
    let fireDate: Date
}

/// Stable, reversible identifiers so we can clear exactly our own pending
/// requests before rescheduling. Format: "countdown.alert.<UUID>.<offset>".
enum AlertRequestID {
    static let prefix = "countdown.alert"

    static func make(countdownID: UUID, offsetMinutes: Int) -> String {
        "\(prefix).\(countdownID.uuidString).\(offsetMinutes)"
    }

    static func isOurs(_ id: String) -> Bool { id.hasPrefix(prefix + ".") }

    static func parse(_ id: String) -> (countdownID: UUID, offsetMinutes: Int)? {
        guard isOurs(id) else { return nil }
        let parts = id.components(separatedBy: ".")
        guard parts.count == 4,
              let uuid = UUID(uuidString: parts[2]),
              let offset = Int(parts[3]) else { return nil }
        return (uuid, offset)
    }
}

/// Pure alert planning. No EventKit, no UserNotifications — fully unit tested.
enum AlertPlanner {
    static func alerts(for countdown: Countdown,
                       targetDate: Date,
                       displayLabel: String,
                       isEvent: Bool,
                       now: Date) -> [ScheduledAlert] {
        var result: [ScheduledAlert] = []
        for m in countdown.alertOffsets {
            let fire = targetDate.addingTimeInterval(TimeInterval(-m * 60))
            guard fire > now else { continue }
            let unit = m == 1 ? "minute" : "minutes"
            let body = isEvent
                ? "\(displayLabel) starts in \(m) \(unit)"
                : "\(m) \(unit) until \(displayLabel)"
            result.append(ScheduledAlert(countdownID: countdown.id, offsetMinutes: m,
                                         fireDate: fire, title: displayLabel, body: body))
        }
        if countdown.alertAtZero, targetDate > now {
            let body = isEvent ? "\(displayLabel) starting now" : "\(displayLabel) reached"
            result.append(ScheduledAlert(countdownID: countdown.id, offsetMinutes: 0,
                                         fireDate: targetDate, title: displayLabel, body: body))
        }
        return result
    }

    /// Resolve each countdown's target (next-event vs fallback) and flatten to OS requests.
    static func plannedRequests(items: [Countdown],
                                nextEventStart: Date?,
                                nextEventTitle: String?,
                                now: Date) -> [PlannedRequest] {
        var out: [PlannedRequest] = []
        for c in items {
            let resolved = CountdownTarget.resolve(c, now: now,
                                                   nextEventStart: nextEventStart,
                                                   nextEventTitle: nextEventTitle)
            let isEvent = resolved.title != nil
            let label = resolved.title ?? c.label
            for a in alerts(for: c, targetDate: resolved.date, displayLabel: label, isEvent: isEvent, now: now) {
                out.append(PlannedRequest(
                    id: AlertRequestID.make(countdownID: a.countdownID, offsetMinutes: a.offsetMinutes),
                    title: a.title, body: a.body, fireDate: a.fireDate))
            }
        }
        return out
    }
}
