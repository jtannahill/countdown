import Foundation
import EventKit

/// Calendar-source-agnostic event snapshot (so resolution is testable without EventKit).
struct EventInfo: Equatable {
    let title: String
    let startDate: Date
    let isAllDay: Bool
}

protocol EventProviding {
    var hasAccess: Bool { get }
    func upcomingEvents(from start: Date, to end: Date) -> [EventInfo]
}

/// Pure selection logic — unit tested.
enum NextEventResolver {
    static func soonestTimedEvent(in events: [EventInfo], now: Date) -> EventInfo? {
        events
            .filter { !$0.isAllDay && $0.startDate > now }
            .min(by: { $0.startDate < $1.startDate })
    }
}

/// Live EventKit wrapper. Thin; not unit tested (verified by the manual smoke test).
final class EventKitService: ObservableObject, EventProviding {
    static let shared = EventKitService()

    private let store = EKEventStore()
    private var timer: Timer?
    private let lookaheadDays = 7

    @Published private(set) var nextEvent: EventInfo?

    private init() {
        // No deinit remover needed: this is a process-lifetime singleton, so the
        // observer never outlives the object.
        NotificationCenter.default.addObserver(
            self, selector: #selector(refresh),
            name: .EKEventStoreChanged, object: store)
    }

    var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        if #available(macOS 14.0, *) { return status == .fullAccess }
        return status == .authorized
    }

    func start() {
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Requests calendar access; calls completion on the main queue and refreshes.
    func requestAccess(_ completion: @escaping (Bool) -> Void) {
        let done: (Bool, Error?) -> Void = { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.refresh()
                completion(granted)
            }
        }
        if #available(macOS 14.0, *) {
            store.requestFullAccessToEvents(completion: done)
        } else {
            store.requestAccess(to: .event, completion: done)
        }
    }

    func upcomingEvents(from start: Date, to end: Date) -> [EventInfo] {
        guard hasAccess else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            EventInfo(title: $0.title ?? "Event", startDate: $0.startDate, isAllDay: $0.isAllDay)
        }
    }

    @objc func refresh() {
        let now = Date()
        guard hasAccess else { setNextEvent(nil); return }
        let end = Calendar.current.date(byAdding: .day, value: lookaheadDays, to: now) ?? now
        let events = upcomingEvents(from: now, to: end)
        setNextEvent(NextEventResolver.soonestTimedEvent(in: events, now: now))
    }

    /// `.EKEventStoreChanged` can fire off the main thread; `nextEvent` drives
    /// SwiftUI, so always publish it on the main thread.
    private func setNextEvent(_ value: EventInfo?) {
        let apply = { if self.nextEvent != value { self.nextEvent = value } }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }
}
