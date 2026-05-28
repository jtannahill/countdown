# EventKit Next-Event Mode + UserNotifications Alerts — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `.nextEvent` countdown mode that tracks the soonest calendar event (falling back to the daily EOD countdown) and per-countdown pre-scheduled notifications (minutes-before thresholds + at-zero).

**Architecture:** Three new focused units — `EventKitService` (publishes the next imminent event), `NotificationScheduler` (pre-schedules `UNNotificationRequest`s), and a pure `CountdownTarget` resolver (single source of truth for "next event vs EOD fallback"). Pure logic (resolution, alert fire-date planning, id encode/decode, Codable upgrade) is unit-tested behind protocol seams; the live EventKit/UserNotifications wrappers stay thin and are verified by a manual smoke test.

**Tech Stack:** Swift 5.9, SwiftPM executable, SwiftUI + AppKit, EventKit, UserNotifications, XCTest. macOS 13 deployment target.

**Spec:** `docs/superpowers/specs/2026-05-28-eventkit-notifications-design.md`

---

## File map

- Create `Sources/Countdown/CountdownTarget.swift` — `ResolvedTarget`, `CountdownTarget.resolve`.
- Create `Sources/Countdown/AlertPlanner.swift` — `ScheduledAlert`, `PlannedRequest`, `AlertRequestID`, `AlertPlanner`.
- Create `Sources/Countdown/EventKitService.swift` — `EventInfo`, `EventProviding`, `NextEventResolver`, `EventKitService`.
- Create `Sources/Countdown/NotificationScheduler.swift` — `NotificationClient`, `LiveNotificationClient`, `NotificationScheduler`.
- Modify `Sources/Countdown/Models.swift` — `CountdownMode.nextEvent`, new `Countdown` fields.
- Modify `Sources/Countdown/main.swift` — start services, wire rescheduling.
- Modify `Sources/Countdown/ContentView.swift` — render next-event, settings UI (mode/lookahead/alerts), lazy auth.
- Modify `Sources/Countdown/MenuBarController.swift` — render next-event in menu bar.
- Modify `Package.swift` — add test target.
- Modify `build-app.sh` — usage-description keys + Developer ID signing variable.
- Create `Tests/CountdownTests/*.swift` — unit tests.

---

## Task 1: Test target + model fields

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/Countdown/Models.swift:48-58` (CountdownMode), `Sources/Countdown/Models.swift:60-95` (Countdown struct + Codable)
- Test: `Tests/CountdownTests/ModelCodableTests.swift`

- [ ] **Step 1: Add the test target to `Package.swift`**

Replace the whole file with:

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Countdown",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "Countdown", path: "Sources/Countdown"),
        .testTarget(
            name: "CountdownTests",
            dependencies: ["Countdown"],
            path: "Tests/CountdownTests"
        ),
    ]
)
```

- [ ] **Step 2: Add `.nextEvent` to `CountdownMode`**

In `Sources/Countdown/Models.swift`, replace the `CountdownMode` enum (lines 48-58) with:

```swift
enum CountdownMode: String, Codable, CaseIterable, Identifiable {
    case daily
    case fixed
    case nextEvent
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily: return "Daily"
        case .fixed: return "Fixed date"
        case .nextEvent: return "Next event"
        }
    }
}
```

- [ ] **Step 3: Add new fields to `Countdown`**

In `Sources/Countdown/Models.swift`, in `struct Countdown`, add these properties immediately after `var color: TerminalColor = .orange` (line 74):

```swift
    // Notifications: minutes-before thresholds (0 reserved for at-zero) + at-zero toggle.
    var alertOffsets: [Int] = []
    var alertAtZero: Bool = false

    // Next-event mode: how far ahead an event counts as "imminent" before falling back to EOD.
    var eventLookaheadHours: Int = 12
```

Then add the keys to `CodingKeys` (line 80-82) so it reads:

```swift
    enum CodingKeys: String, CodingKey {
        case id, label, mode, resetHour, resetMinute, targetHour, targetMinute, targetTimestamp, color
        case alertOffsets, alertAtZero, eventLookaheadHours
    }
```

Then in `init(from decoder:)`, add after the `color = ...` line (line 94):

```swift
        alertOffsets = try c.decodeIfPresent([Int].self, forKey: .alertOffsets) ?? []
        alertAtZero = try c.decodeIfPresent(Bool.self, forKey: .alertAtZero) ?? false
        eventLookaheadHours = try c.decodeIfPresent(Int.self, forKey: .eventLookaheadHours) ?? 12
```

- [ ] **Step 4: Write the failing Codable-upgrade test**

Create `Tests/CountdownTests/ModelCodableTests.swift`:

```swift
import XCTest
@testable import Countdown

final class ModelCodableTests: XCTestCase {
    // An old persisted blob with none of the new fields must decode with defaults.
    func testLegacyBlobDecodesWithDefaults() throws {
        let legacy = """
        [{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","label":"EOD","mode":"daily",
          "resetHour":9,"resetMinute":0,"targetHour":17,"targetMinute":30,
          "targetTimestamp":0,"color":"orange"}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([Countdown].self, from: legacy)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].alertOffsets, [])
        XCTAssertEqual(items[0].alertAtZero, false)
        XCTAssertEqual(items[0].eventLookaheadHours, 12)
        XCTAssertEqual(items[0].mode, .daily)
    }

    func testRoundTripPreservesNewFields() throws {
        var c = Countdown(label: "EOD")
        c.alertOffsets = [10, 5]
        c.alertAtZero = true
        c.eventLookaheadHours = 6
        c.mode = .nextEvent
        let data = try JSONEncoder().encode([c])
        let back = try JSONDecoder().decode([Countdown].self, from: data)
        XCTAssertEqual(back[0].alertOffsets, [10, 5])
        XCTAssertEqual(back[0].alertAtZero, true)
        XCTAssertEqual(back[0].eventLookaheadHours, 6)
        XCTAssertEqual(back[0].mode, .nextEvent)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter ModelCodableTests`
Expected: both tests PASS. (If `@testable import Countdown` fails to resolve, run `swift build` once first, then re-run.)

- [ ] **Step 6: Commit**

```bash
git add Package.swift Sources/Countdown/Models.swift Tests/CountdownTests/ModelCodableTests.swift
git commit -m "feat: add nextEvent mode + alert fields to Countdown model with test target"
```

---

## Task 2: CountdownTarget resolver

**Files:**
- Create: `Sources/Countdown/CountdownTarget.swift`
- Test: `Tests/CountdownTests/CountdownTargetTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CountdownTests/CountdownTargetTests.swift`:

```swift
import XCTest
@testable import Countdown

final class CountdownTargetTests: XCTestCase {
    private func cal() -> Calendar { Calendar.current }

    func testNextEventWithinWindowUsesEvent() {
        var c = Countdown(label: "EOD"); c.mode = .nextEvent; c.eventLookaheadHours = 12
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = now.addingTimeInterval(3600) // 1h away
        let r = CountdownTarget.resolve(c, now: now, nextEventStart: start, nextEventTitle: "Standup")
        XCTAssertEqual(r.date, start)
        XCTAssertEqual(r.title, "Standup")
    }

    func testNextEventBeyondWindowFallsBackToEOD() {
        var c = Countdown(label: "EOD"); c.mode = .nextEvent; c.eventLookaheadHours = 12
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = now.addingTimeInterval(13 * 3600) // 13h away, beyond 12h window
        let r = CountdownTarget.resolve(c, now: now, nextEventStart: start, nextEventTitle: "Standup")
        XCTAssertEqual(r.date, c.currentTarget(now: now)) // EOD fallback
        XCTAssertNil(r.title)
    }

    func testNextEventNilFallsBackToEOD() {
        var c = Countdown(label: "EOD"); c.mode = .nextEvent
        let now = Date(timeIntervalSince1970: 1_000_000)
        let r = CountdownTarget.resolve(c, now: now, nextEventStart: nil, nextEventTitle: nil)
        XCTAssertEqual(r.date, c.currentTarget(now: now))
        XCTAssertNil(r.title)
    }

    func testDailyModeIgnoresEvent() {
        var c = Countdown(label: "EOD"); c.mode = .daily
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = now.addingTimeInterval(600)
        let r = CountdownTarget.resolve(c, now: now, nextEventStart: start, nextEventTitle: "X")
        XCTAssertEqual(r.date, c.currentTarget(now: now))
        XCTAssertNil(r.title)
    }

    func testPastEventIgnored() {
        var c = Countdown(label: "EOD"); c.mode = .nextEvent
        let now = Date(timeIntervalSince1970: 1_000_000)
        let start = now.addingTimeInterval(-60) // already started
        let r = CountdownTarget.resolve(c, now: now, nextEventStart: start, nextEventTitle: "Past")
        XCTAssertEqual(r.date, c.currentTarget(now: now))
        XCTAssertNil(r.title)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter CountdownTargetTests`
Expected: FAIL — "cannot find 'CountdownTarget' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Countdown/CountdownTarget.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter CountdownTargetTests`
Expected: all 5 PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Countdown/CountdownTarget.swift Tests/CountdownTests/CountdownTargetTests.swift
git commit -m "feat: add CountdownTarget resolver (next-event vs EOD fallback)"
```

---

## Task 3: AlertPlanner + AlertRequestID

**Files:**
- Create: `Sources/Countdown/AlertPlanner.swift`
- Test: `Tests/CountdownTests/AlertPlannerTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CountdownTests/AlertPlannerTests.swift`:

```swift
import XCTest
@testable import Countdown

final class AlertPlannerTests: XCTestCase {
    func testRequestIDRoundTrip() {
        let id = UUID()
        let s = AlertRequestID.make(countdownID: id, offsetMinutes: 5)
        XCTAssertTrue(AlertRequestID.isOurs(s))
        let parsed = AlertRequestID.parse(s)
        XCTAssertEqual(parsed?.countdownID, id)
        XCTAssertEqual(parsed?.offsetMinutes, 5)
    }

    func testForeignIDNotOurs() {
        XCTAssertFalse(AlertRequestID.isOurs("some.other.notification"))
        XCTAssertNil(AlertRequestID.parse("some.other.notification"))
    }

    func testThresholdAndZeroFireDates() {
        var c = Countdown(label: "EOD")
        c.alertOffsets = [10, 5]
        c.alertAtZero = true
        let now = Date(timeIntervalSince1970: 1_000_000)
        let target = now.addingTimeInterval(3600) // 60 min away
        let alerts = AlertPlanner.alerts(for: c, targetDate: target, displayLabel: "EOD", isEvent: false, now: now)
        // 10-min, 5-min, and at-zero are all in the future
        XCTAssertEqual(alerts.count, 3)
        XCTAssertEqual(alerts[0].fireDate, target.addingTimeInterval(-600))
        XCTAssertEqual(alerts[1].fireDate, target.addingTimeInterval(-300))
        XCTAssertEqual(alerts[2].fireDate, target) // at-zero
        XCTAssertEqual(alerts[0].body, "10 minutes until EOD")
        XCTAssertEqual(alerts[2].body, "EOD reached")
    }

    func testPastThresholdsDropped() {
        var c = Countdown(label: "EOD")
        c.alertOffsets = [10, 5]
        c.alertAtZero = true
        let now = Date(timeIntervalSince1970: 1_000_000)
        let target = now.addingTimeInterval(7 * 60) // 7 min away: 10-min alert is in the past
        let alerts = AlertPlanner.alerts(for: c, targetDate: target, displayLabel: "EOD", isEvent: false, now: now)
        XCTAssertEqual(alerts.map(\.offsetMinutes), [5, 0])
    }

    func testEventPhrasingAndSingularMinute() {
        var c = Countdown(label: "EOD")
        c.alertOffsets = [1]
        let now = Date(timeIntervalSince1970: 1_000_000)
        let target = now.addingTimeInterval(3600)
        let alerts = AlertPlanner.alerts(for: c, targetDate: target, displayLabel: "Standup", isEvent: true, now: now)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].body, "Standup starts in 1 minute")
    }

    func testPlannedRequestsUsesResolver() {
        var c = Countdown(label: "EOD")
        c.mode = .nextEvent
        c.alertOffsets = [5]
        let now = Date(timeIntervalSince1970: 1_000_000)
        let eventStart = now.addingTimeInterval(1800) // 30 min away, within default 12h
        let reqs = AlertPlanner.plannedRequests(items: [c], nextEventStart: eventStart, nextEventTitle: "Standup", now: now)
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].fireDate, eventStart.addingTimeInterval(-300))
        XCTAssertEqual(reqs[0].title, "Standup")
        XCTAssertEqual(reqs[0].body, "Standup starts in 5 minutes")
        XCTAssertTrue(AlertRequestID.isOurs(reqs[0].id))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter AlertPlannerTests`
Expected: FAIL — "cannot find 'AlertRequestID' / 'AlertPlanner' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Countdown/AlertPlanner.swift`:

```swift
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter AlertPlannerTests`
Expected: all 6 PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Countdown/AlertPlanner.swift Tests/CountdownTests/AlertPlannerTests.swift
git commit -m "feat: add AlertPlanner + AlertRequestID with fire-date/id tests"
```

---

## Task 4: EventKit service + next-event resolver

**Files:**
- Create: `Sources/Countdown/EventKitService.swift`
- Test: `Tests/CountdownTests/NextEventResolverTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CountdownTests/NextEventResolverTests.swift`:

```swift
import XCTest
@testable import Countdown

final class NextEventResolverTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testPicksSoonestFutureTimedEvent() {
        let events = [
            EventInfo(title: "Later", startDate: now.addingTimeInterval(7200), isAllDay: false),
            EventInfo(title: "Soon", startDate: now.addingTimeInterval(600), isAllDay: false),
        ]
        XCTAssertEqual(NextEventResolver.soonestTimedEvent(in: events, now: now)?.title, "Soon")
    }

    func testSkipsAllDayEvents() {
        let events = [
            EventInfo(title: "AllDay", startDate: now.addingTimeInterval(300), isAllDay: true),
            EventInfo(title: "Timed", startDate: now.addingTimeInterval(900), isAllDay: false),
        ]
        XCTAssertEqual(NextEventResolver.soonestTimedEvent(in: events, now: now)?.title, "Timed")
    }

    func testSkipsPastEvents() {
        let events = [
            EventInfo(title: "Past", startDate: now.addingTimeInterval(-300), isAllDay: false),
            EventInfo(title: "Future", startDate: now.addingTimeInterval(300), isAllDay: false),
        ]
        XCTAssertEqual(NextEventResolver.soonestTimedEvent(in: events, now: now)?.title, "Future")
    }

    func testReturnsNilWhenNoCandidates() {
        let events = [EventInfo(title: "AllDay", startDate: now.addingTimeInterval(300), isAllDay: true)]
        XCTAssertNil(NextEventResolver.soonestTimedEvent(in: events, now: now))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter NextEventResolverTests`
Expected: FAIL — "cannot find 'EventInfo' / 'NextEventResolver' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Countdown/EventKitService.swift`:

```swift
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
        guard hasAccess else { nextEvent = nil; return }
        let end = Calendar.current.date(byAdding: .day, value: lookaheadDays, to: now) ?? now
        let events = upcomingEvents(from: now, to: end)
        let resolved = NextEventResolver.soonestTimedEvent(in: events, now: now)
        if resolved != nextEvent { nextEvent = resolved }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter NextEventResolverTests`
Expected: all 4 PASS.

- [ ] **Step 5: Verify the whole module still builds**

Run: `swift build`
Expected: "Build complete!"

- [ ] **Step 6: Commit**

```bash
git add Sources/Countdown/EventKitService.swift Tests/CountdownTests/NextEventResolverTests.swift
git commit -m "feat: add EventKitService + NextEventResolver"
```

---

## Task 5: Notification scheduler

**Files:**
- Create: `Sources/Countdown/NotificationScheduler.swift`

(No new unit test — the planning logic is covered by `AlertPlannerTests`; this class is a thin live wrapper verified in the Task 8 smoke test.)

- [ ] **Step 1: Write the implementation**

Create `Sources/Countdown/NotificationScheduler.swift`:

```swift
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
```

- [ ] **Step 2: Verify the module builds**

Run: `swift build`
Expected: "Build complete!"

- [ ] **Step 3: Commit**

```bash
git add Sources/Countdown/NotificationScheduler.swift
git commit -m "feat: add NotificationScheduler (pre-scheduled UNCalendarNotificationTrigger)"
```

---

## Task 6: Wire services into the app

**Files:**
- Modify: `Sources/Countdown/main.swift:40-82` (AppDelegate)

- [ ] **Step 1: Add Combine import and rescheduling wiring**

At the top of `Sources/Countdown/main.swift`, add after `import ServiceManagement` (line 3):

```swift
import Combine
```

In `AppDelegate`, add a stored property below `var window: FloatingWindow!` (line 41):

```swift
    private var cancellables = Set<AnyCancellable>()

    private func rescheduleNotifications() {
        let svc = EventKitService.shared
        NotificationScheduler.shared.reschedule(
            items: CountdownStore.shared.items,
            nextEventStart: svc.nextEvent?.startDate,
            nextEventTitle: svc.nextEvent?.title)
    }
```

- [ ] **Step 2: Start the services and subscribe**

In `applicationDidFinishLaunching`, immediately before `registerLoginItem()` (line 80), add:

```swift
        EventKitService.shared.start()

        // Reschedule notifications when items, the next event, or time (daily roll) change.
        CountdownStore.shared.$items
            .sink { [weak self] _ in self?.rescheduleNotifications() }
            .store(in: &cancellables)
        EventKitService.shared.$nextEvent
            .sink { [weak self] _ in self?.rescheduleNotifications() }
            .store(in: &cancellables)
        let reschedTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.rescheduleNotifications()
        }
        RunLoop.main.add(reschedTimer, forMode: .common)
        rescheduleNotifications()
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: "Build complete!"

- [ ] **Step 4: Commit**

```bash
git add Sources/Countdown/main.swift
git commit -m "feat: start EventKit service and wire notification rescheduling"
```

---

## Task 7: UI integration (render + settings + lazy auth)

**Files:**
- Modify: `Sources/Countdown/ContentView.swift` (ContentView, CountdownRow, HUDView, CountdownEditor)
- Modify: `Sources/Countdown/MenuBarController.swift:58-85`

- [ ] **Step 1: Observe the event service and pass it into rows (ContentView)**

In `struct ContentView`, add after `@ObservedObject private var settings = AppSettings.shared` (line 6):

```swift
    @ObservedObject private var eventService = EventKitService.shared
```

In `fullStack`, change the `CountdownRow` construction (line 85) from:

```swift
                    CountdownRow(item: item, now: now)
```

to:

```swift
                    CountdownRow(item: item, now: now, nextEvent: eventService.nextEvent)
```

- [ ] **Step 2: Make CountdownRow resolve via CountdownTarget**

In `struct CountdownRow`, add a stored property after `let now: Date` (line 150):

```swift
    var nextEvent: EventInfo?
```

Replace `private var target: Date { item.currentTarget(now: now) }` (line 167) with:

```swift
    private var resolved: ResolvedTarget {
        CountdownTarget.resolve(item, now: now,
                                nextEventStart: nextEvent?.startDate,
                                nextEventTitle: nextEvent?.title)
    }
    private var target: Date { resolved.date }
    private var displayLabel: String { resolved.title ?? item.label }
```

Replace the label `Text` (line 183) from:

```swift
                Text(item.label.uppercased())
```

to:

```swift
                Text(displayLabel.uppercased())
```

Replace the DAILY-badge block (lines 188-199) with one that also handles next-event:

```swift
                if item.mode == .daily {
                    badge("DAILY")
                } else if item.mode == .nextEvent {
                    badge(resolved.title != nil ? "NEXT" : "EOD")
                }
```

And add this helper method inside `CountdownRow` (just before `private var timeDisplay`, line 251):

```swift
    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.nhg(10, .bold))
            .tracking(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.15)))
            .foregroundColor(accent)
    }
```

- [ ] **Step 3: Update the subtitle for next-event**

The `Text(item.subtitle)` line (line 231) stays, but add a `Countdown.subtitle` case for next-event. In `Sources/Countdown/Models.swift`, in the `subtitle` computed property (lines 117-127), add a `.nextEvent` arm so the `switch` reads:

```swift
    var subtitle: String {
        switch mode {
        case .daily:
            return "daily · \(formatHM(resetHour, resetMinute)) → \(formatHM(targetHour, targetMinute))"
        case .fixed:
            let date = Date(timeIntervalSince1970: targetTimestamp)
            let f = DateFormatter()
            f.dateFormat = "EEE MMM d · h:mm a"
            return f.string(from: date).lowercased()
        case .nextEvent:
            return "next event · fallback EOD \(formatHM(targetHour, targetMinute))"
        }
    }
```

- [ ] **Step 4: Update HUDView and the menu bar to resolve too**

In `struct HUDView`, replace `remaining(for:)` (lines 293-298) with:

```swift
    private func remaining(for item: Countdown) -> (d: Int, h: Int, m: Int, s: Int, expired: Bool) {
        let target = CountdownTarget.resolve(item, now: now,
                                             nextEventStart: EventKitService.shared.nextEvent?.startDate,
                                             nextEventTitle: EventKitService.shared.nextEvent?.title).date
        let interval = target.timeIntervalSince(now)
        if interval <= 0 { return (0, 0, 0, 0, true) }
        let total = Int(interval)
        return (total / 86400, (total % 86400) / 3600, (total % 3600) / 60, total % 60, false)
    }
```

In `Sources/Countdown/MenuBarController.swift`, in `tick()`, replace the target/label lines (lines 66-68):

```swift
        let target = primary.currentTarget(now: now)
        let interval = target.timeIntervalSince(now)
        let label = primary.label.uppercased()
```

with:

```swift
        let resolved = CountdownTarget.resolve(primary, now: now,
                                               nextEventStart: EventKitService.shared.nextEvent?.startDate,
                                               nextEventTitle: EventKitService.shared.nextEvent?.title)
        let target = resolved.date
        let interval = target.timeIntervalSince(now)
        let label = (resolved.title ?? primary.label).uppercased()
```

- [ ] **Step 5: Add lookahead + alerts UI and lazy auth (CountdownEditor)**

In `struct CountdownEditor`, the mode `Picker` already includes `.nextEvent` automatically (it uses `CountdownMode.allCases`). Add lazy calendar-access on selection by replacing the `Picker(...).pickerStyle(.segmented).labelsHidden()` block (lines 477-483) with:

```swift
            Picker("Mode", selection: $item.mode) {
                ForEach(CountdownMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: item.mode) { newMode in
                if newMode == .nextEvent && !EventKitService.shared.hasAccess {
                    EventKitService.shared.requestAccess { _ in }
                }
            }

            if item.mode == .nextEvent {
                nextEventControls
            }
            alertControls
```

Add these two computed views and a denied-note helper inside `CountdownEditor` (before `private func hmBinding`, line 561):

```swift
    @ViewBuilder private var nextEventControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !EventKitService.shared.hasAccess {
                Text("Calendar access denied — enable in System Settings ▸ Privacy ▸ Calendars")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else if let ev = EventKitService.shared.nextEvent {
                Text("Next: \(ev.title) · \(Self.timeFmt.string(from: ev.startDate))")
                    .font(.system(size: 11, weight: .medium))
            } else {
                Text("No upcoming event — showing EOD")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Stepper("Imminent within \(item.eventLookaheadHours)h",
                    value: $item.eventLookaheadHours, in: 1...72)
                .font(.system(size: 11))
        }
    }

    @ViewBuilder private var alertControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ALERTS")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary).tracking(1)
            HStack(spacing: 6) {
                ForEach([15, 10, 5, 1], id: \.self) { m in
                    let on = item.alertOffsets.contains(m)
                    Button("\(m)m") { toggleOffset(m) }
                        .buttonStyle(.bordered)
                        .tint(on ? .accentColor : .secondary)
                }
                Spacer()
            }
            Toggle("Notify at zero", isOn: $item.alertAtZero)
                .font(.system(size: 11))
                .onChange(of: item.alertAtZero) { on in if on { requestNotifAuthIfNeeded() } }
        }
    }

    private func toggleOffset(_ m: Int) {
        if let idx = item.alertOffsets.firstIndex(of: m) {
            item.alertOffsets.remove(at: idx)
        } else {
            item.alertOffsets.append(m)
            item.alertOffsets.sort(by: >)
            requestNotifAuthIfNeeded()
        }
    }

    private func requestNotifAuthIfNeeded() {
        NotificationScheduler.shared.requestAuthorization { _ in }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f
    }()
```

- [ ] **Step 6: Build and run a manual UI check**

Run:
```bash
./build-app.sh && open ./Countdown.app
```
Expected: builds, widget appears. In Settings (gear on hover): the mode picker shows **Daily · Fixed date · Next event**; choosing **Next event** prompts for Calendar access and then shows a "Next: …" preview; the **15/10/5/1m** chips toggle and "Notify at zero" prompts for Notification access. The main widget shows the event title + "NEXT" badge when an event is imminent, otherwise "EOD".

- [ ] **Step 7: Commit**

```bash
git add Sources/Countdown/ContentView.swift Sources/Countdown/MenuBarController.swift Sources/Countdown/Models.swift
git commit -m "feat: render next-event mode and add lookahead/alerts settings UI"
```

---

## Task 8: Build script, Info.plist, signing, and smoke test

**Files:**
- Modify: `build-app.sh`

- [ ] **Step 1: Add calendar usage-description keys to the generated Info.plist**

In `build-app.sh`, inside the `cat > "$APP/Contents/Info.plist"` heredoc, add these two keys immediately before the closing `</dict>`:

```xml
    <key>NSCalendarsUsageDescription</key>
    <string>Countdown shows the time remaining until your next calendar event.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Countdown shows the time remaining until your next calendar event.</string>
```

- [ ] **Step 2: Add a Developer ID signing variable**

In `build-app.sh`, near the top (after `cd "$(dirname "$0")"`), add:

```bash
# Set to your Developer ID identity for reliable notifications, e.g.
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
# Leave empty to fall back to ad-hoc signing (notifications may be unreliable).
SIGN_IDENTITY="${SIGN_IDENTITY:-}"
```

Replace the existing signing line:

```bash
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
```

with:

```bash
if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: $SIGN_IDENTITY"
    codesign --force --deep --options runtime --sign "$SIGN_IDENTITY" "$APP"
else
    echo "No SIGN_IDENTITY set — ad-hoc signing (notifications may be unreliable)."
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi
```

- [ ] **Step 3: Detect an available Developer ID (informational)**

Run: `security find-identity -v -p codesigning`
Expected: a list of identities. If a "Developer ID Application" line exists, note it; the user can export `SIGN_IDENTITY=...` before building. If none, ad-hoc is used (acceptable for local testing; notifications may not banner reliably).

- [ ] **Step 4: Full unit-test pass**

Run: `swift test`
Expected: all tests across `ModelCodableTests`, `CountdownTargetTests`, `AlertPlannerTests`, `NextEventResolverTests` PASS.

- [ ] **Step 5: End-to-end smoke test**

Run:
```bash
./build-app.sh && cp -R ./Countdown.app ~/Applications/ && pkill -f 'Applications/Countdown.app'; sleep 1; open ~/Applications/Countdown.app
```
Then, by hand:
1. Grant Calendar access when prompted; confirm a next-event countdown shows your next meeting.
2. Create a throwaway calendar event ~3 minutes out; switch a countdown to Next event; enable the **1m** chip and grant Notification access.
3. Confirm a banner fires ~1 minute before the event.
4. Confirm the widget still opens pinned to its saved position (regression from earlier work).

Expected: notification banner appears at the threshold; widget position unchanged.

- [ ] **Step 6: Commit and push**

```bash
git add build-app.sh
git commit -m "build: add calendar usage keys and Developer ID signing option"
git push origin main
```

---

## Self-review notes

- **Spec coverage:** next-event selection (Task 4 + 2), EOD fallback (Task 2), per-countdown thresholds + at-zero across all modes (Tasks 1, 3, 7), Approach A pre-scheduled triggers (Task 5), three new units + minimal edits (Tasks 2–7), lazy permissions (Task 7), Settings UI (Task 7), test target (Task 1), Info.plist + Developer ID (Task 8) — all mapped.
- **Deferred per spec "Out of scope":** Swift Charts, CloudKit, WidgetKit, AppIntents, chosen-calendar filtering, count-to-end-if-in-meeting.
- **Type consistency:** `CountdownTarget.resolve(_:now:nextEventStart:nextEventTitle:)`, `ResolvedTarget{date,title}`, `EventInfo{title,startDate,isAllDay}`, `AlertRequestID.{make,isOurs,parse}`, `AlertPlanner.{alerts,plannedRequests}`, `PlannedRequest{id,title,body,fireDate}`, `EventKitService.{shared,start,requestAccess,hasAccess,nextEvent}`, `NotificationScheduler.{shared,requestAuthorization,reschedule}` — used consistently across tasks.
