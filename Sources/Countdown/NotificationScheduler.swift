import Foundation
import UserNotifications

/// Seam over UNUserNotificationCenter so the scheduler stays thin/replaceable.
protocol NotificationClient {
    func requestAuthorization(_ completion: @escaping (Bool) -> Void)
    func pendingIdentifiers(_ completion: @escaping ([String]) -> Void)
    func removePending(withIdentifiers ids: [String])
    func add(_ request: UNNotificationRequest)
}

final class LiveNotificationClient: NotificationClient {
    private var center: UNUserNotificationCenter { .current() }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async { completion(granted) }
        }
    }
    func pendingIdentifiers(_ completion: @escaping ([String]) -> Void) {
        center.getPendingNotificationRequests { reqs in
            DispatchQueue.main.async { completion(reqs.map(\.identifier)) }
        }
    }
    func removePending(withIdentifiers ids: [String]) {
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
    func add(_ request: UNNotificationRequest) {
        center.add(request)
    }
}

final class NotificationScheduler {
    static let shared = NotificationScheduler()
    private let client: NotificationClient

    init(client: NotificationClient = LiveNotificationClient()) { self.client = client }

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        client.requestAuthorization(completion)
    }

    /// Clear our previously-scheduled requests, then register the current plan.
    func reschedule(items: [Countdown], nextEventStart: Date?, nextEventTitle: String?, now: Date = Date()) {
        let planned = AlertPlanner.plannedRequests(items: items,
                                                   nextEventStart: nextEventStart,
                                                   nextEventTitle: nextEventTitle,
                                                   now: now)
        client.pendingIdentifiers { [weak self] ids in
            guard let self else { return }
            // remove-then-add is safe: UNUserNotificationCenter serializes these
            // on its internal queue in call order, so no extra synchronization.
            self.client.removePending(withIdentifiers: ids.filter { AlertRequestID.isOurs($0) })
            for p in planned {
                let content = UNMutableNotificationContent()
                content.title = p.title
                content.body = p.body
                content.sound = .default
                let comps = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .second], from: p.fireDate)
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                self.client.add(UNNotificationRequest(identifier: p.id, content: content, trigger: trigger))
            }
        }
    }
}
