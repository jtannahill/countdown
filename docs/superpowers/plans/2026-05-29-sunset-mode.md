# Sunset Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `.sunset` countdown mode that counts down to today's sunset (rolling to tomorrow after) computed locally from the user's coordinates, with a manual lat/long fallback.

**Architecture:** A pure `SolarCalc` (NOAA/Almanac sunset algorithm) + a `LocationProvider` (CoreLocation wrapper with manual fallback) feed a `sunsetTarget` into the existing `CountdownTarget.resolve` (same way `nextEventStart` already flows). `CountdownMode` gains `.sunset`; no new `Countdown` Codable fields. Pure logic is unit-tested; the CoreLocation/SwiftUI layers are verified by build + manual check.

**Tech Stack:** Swift 5.9, SwiftPM executable, SwiftUI + AppKit, CoreLocation, XCTest. macOS 13.

**Spec:** `docs/superpowers/specs/2026-05-29-sunset-mode-design.md`

Test note: `swift test --filter X` prints a swift-testing "0 tests" line separately; the XCTest "Executed N tests" line is what matters. IGNORE SourceKit "cannot find in scope" LSP noise — only `swift build` counts.

---

## File map

- Create `Sources/Countdown/SolarCalc.swift` — pure sunset/nextSunset.
- Create `Sources/Countdown/LocationProvider.swift` — CoreLocation + manual fallback + `isValid`.
- Modify `Sources/Countdown/Models.swift` — `CountdownMode.sunset`; `currentTarget`/`dailyWindow`/`subtitle` handle it.
- Modify `Sources/Countdown/CountdownTarget.swift` — `sunsetTarget` param.
- Modify `Sources/Countdown/ContentView.swift` — render sunset (row/HUD/settings).
- Modify `Sources/Countdown/MenuBarController.swift` — sunset target in menu bar.
- Modify `Sources/Countdown/main.swift` — pass sunsetTarget into notification rescheduling.
- Modify `build-app.sh` — `NSLocationWhenInUseUsageDescription`.
- Create `Tests/CountdownTests/SolarCalcTests.swift`, `Tests/CountdownTests/LocationValidationTests.swift`; extend `CountdownTargetTests`.

---

## Task 1: `SolarCalc` (pure sunset algorithm)

**Files:**
- Create: `Sources/Countdown/SolarCalc.swift`
- Test: `Tests/CountdownTests/SolarCalcTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CountdownTests/SolarCalcTests.swift`:

```swift
import XCTest
@testable import Countdown

final class SolarCalcTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func utcDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func minutesUTC(_ date: Date) -> Int {
        utc.component(.hour, from: date) * 60 + utc.component(.minute, from: date)
    }
    private let utcTZ = TimeZone(identifier: "UTC")!

    // London (51.4769N, 0E), summer solstice 2024 — sunset ~20:21 UTC (21:21 BST).
    func testLondonSummerSolsticeSunset() {
        let s = SolarCalc.sunset(on: utcDate(2024, 6, 21), latitude: 51.4769, longitude: 0, timeZone: utcTZ)!
        XCTAssertGreaterThanOrEqual(minutesUTC(s), 20 * 60)
        XCTAssertLessThanOrEqual(minutesUTC(s), 20 * 60 + 40)
    }

    // London winter solstice 2024 — sunset ~15:53 UTC (GMT).
    func testLondonWinterSolsticeSunset() {
        let s = SolarCalc.sunset(on: utcDate(2024, 12, 21), latitude: 51.4769, longitude: 0, timeZone: utcTZ)!
        XCTAssertGreaterThanOrEqual(minutesUTC(s), 15 * 60 + 40)
        XCTAssertLessThanOrEqual(minutesUTC(s), 16 * 60 + 5)
    }

    // High Arctic (Svalbard ~78N) at summer solstice — midnight sun, no sunset.
    func testPolarNoSunsetIsNil() {
        XCTAssertNil(SolarCalc.sunset(on: utcDate(2024, 6, 21), latitude: 78, longitude: 15, timeZone: utcTZ))
    }

    func testNextSunsetTodayThenTomorrow() {
        let day = utcDate(2024, 6, 21)
        let todays = SolarCalc.sunset(on: day, latitude: 51.4769, longitude: 0, timeZone: utcTZ)!
        // One hour before today's sunset → returns today's.
        XCTAssertEqual(
            SolarCalc.nextSunset(after: todays.addingTimeInterval(-3600), latitude: 51.4769, longitude: 0, timeZone: utcTZ),
            todays)
        // One hour after today's sunset → returns a later (tomorrow's) sunset.
        let next = SolarCalc.nextSunset(after: todays.addingTimeInterval(3600), latitude: 51.4769, longitude: 0, timeZone: utcTZ)!
        XCTAssertGreaterThan(next, todays.addingTimeInterval(3600))
        XCTAssertGreaterThan(next, todays)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter SolarCalcTests`
Expected: FAIL — "cannot find 'SolarCalc' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Countdown/SolarCalc.swift`:

```swift
import Foundation

/// Pure sunset computation via the Almanac-for-Computers / NOAA sunrise-sunset
/// algorithm. Accurate to ~1-2 minutes; no network, no entitlement.
enum SolarCalc {
    /// Sunset instant for the local day of `date` at the given coordinates, or
    /// nil for polar days with no sunset. `longitude` is East-positive.
    static func sunset(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> Date? {
        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = timeZone
        let comps = localCal.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }

        var utcCal = Calendar(identifier: .gregorian)
        utcCal.timeZone = TimeZone(identifier: "UTC")!
        guard let dayDate = utcCal.date(from: DateComponents(year: year, month: month, day: day)),
              let dayOfYear = utcCal.ordinality(of: .day, in: .year, for: dayDate) else { return nil }

        let D2R = Double.pi / 180, R2D = 180 / Double.pi
        let zenith = 90.833   // official sunset (accounts for refraction + solar radius)

        let lngHour = longitude / 15.0
        let t = Double(dayOfYear) + ((18.0 - lngHour) / 24.0)   // 18 = sunset approximation

        let M = (0.9856 * t) - 3.289                            // sun mean anomaly
        var L = M + (1.916 * sin(M * D2R)) + (0.020 * sin(2 * M * D2R)) + 282.634
        L = mod(L, 360)                                         // sun true longitude

        var RA = R2D * atan(0.91764 * tan(L * D2R))             // right ascension
        RA = mod(RA, 360)
        RA += (floor(L / 90) * 90) - (floor(RA / 90) * 90)      // same quadrant as L
        RA /= 15

        let sinDec = 0.39782 * sin(L * D2R)
        let cosDec = cos(asin(sinDec))

        let cosH = (cos(zenith * D2R) - (sinDec * sin(latitude * D2R))) / (cosDec * cos(latitude * D2R))
        if cosH > 1 || cosH < -1 { return nil }                 // no sunset (polar)

        var H = R2D * acos(cosH)                                // sunset hour angle
        H /= 15
        let localT = H + RA - (0.06571 * t) - 6.622
        let ut = mod(localT - lngHour, 24)                      // UTC hours

        let hour = Int(ut)
        let minF = (ut - Double(hour)) * 60
        let minute = Int(minF)
        let second = Int((minF - Double(minute)) * 60)
        return utcCal.date(from: DateComponents(year: year, month: month, day: day,
                                                hour: hour, minute: minute, second: second))
    }

    /// Today's sunset if still ahead of `now`, otherwise tomorrow's. nil if neither exists.
    static func nextSunset(after now: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> Date? {
        if let today = sunset(on: now, latitude: latitude, longitude: longitude, timeZone: timeZone), today > now {
            return today
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        guard let tomorrow = cal.date(byAdding: .day, value: 1, to: now) else { return nil }
        return sunset(on: tomorrow, latitude: latitude, longitude: longitude, timeZone: timeZone)
    }

    private static func mod(_ x: Double, _ m: Double) -> Double {
        let r = x.truncatingRemainder(dividingBy: m)
        return r < 0 ? r + m : r
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter SolarCalcTests` → "Executed 4 tests, with 0 failures".

- [ ] **Step 5: Commit**

```bash
git add Sources/Countdown/SolarCalc.swift Tests/CountdownTests/SolarCalcTests.swift
git commit -m "feat: add SolarCalc (pure sunset/nextSunset)"
```

---

## Task 2: `.sunset` mode + resolver support

**Files:**
- Modify: `Sources/Countdown/Models.swift` (`CountdownMode`, `Countdown.currentTarget`/`dailyWindow`/`subtitle`)
- Modify: `Sources/Countdown/CountdownTarget.swift`
- Test: extend `Tests/CountdownTests/CountdownTargetTests.swift`

- [ ] **Step 1: Add the `.sunset` case to `CountdownMode`**

In `Sources/Countdown/Models.swift`, change the `CountdownMode` enum to add the case + label:

```swift
enum CountdownMode: String, Codable, CaseIterable, Identifiable {
    case daily
    case fixed
    case nextEvent
    case sunset
    var id: String { rawValue }
    var label: String {
        switch self {
        case .daily: return "Daily"
        case .fixed: return "Fixed date"
        case .nextEvent: return "Next event"
        case .sunset: return "Sunset"
        }
    }
}
```

- [ ] **Step 2: Handle `.sunset` in `currentTarget`, `dailyWindow`, `subtitle`**

In `Countdown.currentTarget(now:)`, add a `.sunset` case (degenerate — real target comes from the resolver). It currently reads:

```swift
    func currentTarget(now: Date = Date()) -> Date {
        switch mode {
        case .fixed:
            return Date(timeIntervalSince1970: targetTimestamp)
        case .daily, .nextEvent:
            // .nextEvent uses this only as its EOD fallback; the live event
            // target is resolved by CountdownTarget.
            return dailyWindow(now: now)?.target ?? now
        }
    }
```

Change it to:

```swift
    func currentTarget(now: Date = Date()) -> Date {
        switch mode {
        case .fixed:
            return Date(timeIntervalSince1970: targetTimestamp)
        case .daily, .nextEvent:
            // .nextEvent uses this only as its EOD fallback; the live event
            // target is resolved by CountdownTarget.
            return dailyWindow(now: now)?.target ?? now
        case .sunset:
            // No location here — the real sunset target is supplied to the resolver.
            return now
        }
    }
```

`dailyWindow(now:)` already starts with `guard mode != .fixed else { return nil }` — change that guard so `.sunset` is also excluded (it is not a reset→target window):

```swift
        guard mode == .daily || mode == .nextEvent else { return nil }
```

In `Countdown.subtitle`, add a `.sunset` case so the `switch mode` stays exhaustive:

```swift
        case .sunset:
            return "sunset"
```

- [ ] **Step 3: Add `sunsetTarget` to `CountdownTarget.resolve`**

Read `Sources/Countdown/CountdownTarget.swift`. It currently is:

```swift
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

Replace it with (adds a defaulted `sunsetTarget` param so existing callers compile unchanged):

```swift
enum CountdownTarget {
    static func resolve(_ countdown: Countdown,
                        now: Date,
                        nextEventStart: Date?,
                        nextEventTitle: String?,
                        sunsetTarget: Date? = nil) -> ResolvedTarget {
        if countdown.mode == .nextEvent,
           let start = nextEventStart,
           start > now {
            let windowEnd = now.addingTimeInterval(TimeInterval(countdown.eventLookaheadHours) * 3600)
            if start <= windowEnd {
                return ResolvedTarget(date: start, title: nextEventTitle)
            }
        }
        if countdown.mode == .sunset, let s = sunsetTarget {
            return ResolvedTarget(date: s, title: nil)
        }
        // daily, fixed, next-event EOD fallback, or sunset-with-no-location
        return ResolvedTarget(date: countdown.currentTarget(now: now), title: nil)
    }
}
```

- [ ] **Step 4: Write the tests**

In `Tests/CountdownTests/CountdownTargetTests.swift`, add these methods inside the existing `CountdownTargetTests` class:

```swift
    func testSunsetModeUsesSunsetTarget() {
        var c = Countdown(label: "Sunset"); c.mode = .sunset
        let now = Date(timeIntervalSince1970: 1_000_000)
        let sunset = now.addingTimeInterval(7200)
        let r = CountdownTarget.resolve(c, now: now, nextEventStart: nil, nextEventTitle: nil, sunsetTarget: sunset)
        XCTAssertEqual(r.date, sunset)
        XCTAssertNil(r.title)
    }

    func testSunsetModeNoTargetFallsBackToCurrentTarget() {
        var c = Countdown(label: "Sunset"); c.mode = .sunset
        let now = Date(timeIntervalSince1970: 1_000_000)
        let r = CountdownTarget.resolve(c, now: now, nextEventStart: nil, nextEventTitle: nil, sunsetTarget: nil)
        XCTAssertEqual(r.date, c.currentTarget(now: now))   // == now (degenerate)
        XCTAssertNil(r.title)
    }

    func testSunsetDoesNotAffectDailyResolution() {
        let c = Countdown(label: "EOD")   // .daily
        let now = Date(timeIntervalSince1970: 1_000_000)
        let r = CountdownTarget.resolve(c, now: now, nextEventStart: nil, nextEventTitle: nil, sunsetTarget: now.addingTimeInterval(99))
        XCTAssertEqual(r.date, c.currentTarget(now: now))   // daily ignores sunsetTarget
    }
```

- [ ] **Step 5: Run to verify pass**

Run: `swift build` → Build complete.
Run: `swift test` → all pass (the 3 new + existing; the `.sunset` case must not break `CountdownTargetTests`/`AlertPlannerTests`).

- [ ] **Step 6: Commit**

```bash
git add Sources/Countdown/Models.swift Sources/Countdown/CountdownTarget.swift Tests/CountdownTests/CountdownTargetTests.swift
git commit -m "feat: add .sunset mode + sunsetTarget resolver support"
```

---

## Task 3: `LocationProvider`

**Files:**
- Create: `Sources/Countdown/LocationProvider.swift`
- Test: `Tests/CountdownTests/LocationValidationTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CountdownTests/LocationValidationTests.swift`:

```swift
import XCTest
@testable import Countdown

final class LocationValidationTests: XCTestCase {
    func testValidCoordinatesAccepted() {
        XCTAssertTrue(LocationProvider.isValid(latitude: 0, longitude: 0))
        XCTAssertTrue(LocationProvider.isValid(latitude: -90, longitude: 180))
        XCTAssertTrue(LocationProvider.isValid(latitude: 51.5, longitude: -0.12))
    }
    func testOutOfRangeCoordinatesRejected() {
        XCTAssertFalse(LocationProvider.isValid(latitude: 91, longitude: 0))
        XCTAssertFalse(LocationProvider.isValid(latitude: 0, longitude: 181))
        XCTAssertFalse(LocationProvider.isValid(latitude: -90.1, longitude: 0))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter LocationValidationTests`
Expected: FAIL — "cannot find 'LocationProvider' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Countdown/LocationProvider.swift`:

```swift
import Foundation
import CoreLocation

/// App-wide location source for sunset mode. Precedence: live CoreLocation fix →
/// manually-entered coordinates (persisted) → none. The live wrapper is not unit
/// tested; `isValid` and the manual setters are simple/pure.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationProvider()

    struct Coordinate: Equatable { let latitude: Double; let longitude: Double }

    @Published private(set) var coordinate: Coordinate?

    private let manager = CLLocationManager()
    private var liveCoordinate: Coordinate? { didSet { recompute() } }

    private let latKey = "manualLat", lonKey = "manualLon"

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        recompute()
    }

    static func isValid(latitude: Double, longitude: Double) -> Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }

    var authorizationDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Lazily request authorization + a one-shot location fix. Safe to call repeatedly.
    func requestAccessIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func setManualCoordinate(latitude: Double, longitude: Double) {
        guard Self.isValid(latitude: latitude, longitude: longitude) else { return }
        UserDefaults.standard.set(latitude, forKey: latKey)
        UserDefaults.standard.set(longitude, forKey: lonKey)
        recompute()
    }

    func clearManualCoordinate() {
        UserDefaults.standard.removeObject(forKey: latKey)
        UserDefaults.standard.removeObject(forKey: lonKey)
        recompute()
    }

    var manualCoordinate: Coordinate? {
        let d = UserDefaults.standard
        guard d.object(forKey: latKey) != nil, d.object(forKey: lonKey) != nil else { return nil }
        let lat = d.double(forKey: latKey), lon = d.double(forKey: lonKey)
        return Self.isValid(latitude: lat, longitude: lon) ? Coordinate(latitude: lat, longitude: lon) : nil
    }

    private func recompute() {
        let next = liveCoordinate ?? manualCoordinate
        if next != coordinate { coordinate = next }
    }

    // MARK: CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            manager.requestLocation()
        }
        recompute()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        liveCoordinate = Coordinate(latitude: loc.coordinate.latitude, longitude: loc.coordinate.longitude)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        recompute()   // fall back to manual
    }
}
```

- [ ] **Step 4: Run to verify pass + module builds**

Run: `swift test --filter LocationValidationTests` → "Executed 2 tests, with 0 failures".
Run: `swift build` → Build complete (CoreLocation is in the macOS SDK; no package dependency).

- [ ] **Step 5: Commit**

```bash
git add Sources/Countdown/LocationProvider.swift Tests/CountdownTests/LocationValidationTests.swift
git commit -m "feat: add LocationProvider (CoreLocation + manual fallback)"
```

---

## Task 4: Render sunset mode (row / HUD / menu bar / notifications)

**Files:**
- Modify: `Sources/Countdown/ContentView.swift` (`ContentView`, `CountdownRow`, `HUDView`)
- Modify: `Sources/Countdown/MenuBarController.swift`
- Modify: `Sources/Countdown/main.swift`

READ each function first to confirm anchors.

- [ ] **Step 1: Observe LocationProvider in ContentView**

In `struct ContentView`, add after `@ObservedObject private var eventService = EventKitService.shared`:

```swift
    @ObservedObject private var locationProvider = LocationProvider.shared
```

- [ ] **Step 2: CountdownRow — sunset target, badge, subtitle, hint**

In `struct CountdownRow`, add a helper after the existing `private var displayLabel: String { resolved.title ?? item.label }` (and before `ringFraction`):

```swift
    private var sunsetTarget: Date? {
        guard item.mode == .sunset, let c = LocationProvider.shared.coordinate else { return nil }
        return SolarCalc.nextSunset(after: now, latitude: c.latitude, longitude: c.longitude)
    }
```

Change `resolved` to pass `sunsetTarget`. It currently is:

```swift
    private var resolved: ResolvedTarget {
        CountdownTarget.resolve(item, now: now,
                                nextEventStart: nextEvent?.startDate,
                                nextEventTitle: nextEvent?.title)
    }
```

to:

```swift
    private var resolved: ResolvedTarget {
        CountdownTarget.resolve(item, now: now,
                                nextEventStart: nextEvent?.startDate,
                                nextEventTitle: nextEvent?.title,
                                sunsetTarget: sunsetTarget)
    }

    /// True for a sunset countdown that has no usable coordinates yet.
    private var sunsetNeedsLocation: Bool { item.mode == .sunset && sunsetTarget == nil }

    /// Subtitle override: sunset shows the resolved sunset time.
    private var rowSubtitle: String {
        if item.mode == .sunset {
            guard !sunsetNeedsLocation else { return "set location in settings" }
            let f = DateFormatter(); f.dateFormat = "'sunset ·' h:mm a"
            return f.string(from: resolved.date).lowercased()
        }
        return item.subtitle
    }
```

In `CountdownRow.body`, the badge block currently reads:

```swift
                if item.mode == .daily {
                    badge("DAILY")
                } else if item.mode == .nextEvent {
                    badge(resolved.title != nil ? "NEXT" : "EOD")
                }
```

Change to add the sunset badge:

```swift
                if item.mode == .daily {
                    badge("DAILY")
                } else if item.mode == .nextEvent {
                    badge(resolved.title != nil ? "NEXT" : "EOD")
                } else if item.mode == .sunset {
                    badge("SUNSET")
                }
```

Replace the subtitle `Text(item.subtitle)` line (in `CountdownRow.body`) with:

```swift
            Text(rowSubtitle)
```

(Note: `ringFraction`'s guard `item.mode != .fixed, resolved.title == nil` would also fire for `.sunset` — but `item.dailyWindow(now:)` returns nil for `.sunset` (Task 2), so `ringFraction` is nil and no ring shows for sunset. No change needed.)

- [ ] **Step 3: HUDView and MenuBar — resolve with sunset target**

In `struct HUDView`, `remaining(for:)` currently resolves with nextEvent only. Replace its `CountdownTarget.resolve(...)` call so it also passes the sunset target:

```swift
    private func remaining(for item: Countdown) -> (d: Int, h: Int, m: Int, s: Int, expired: Bool) {
        let coord = LocationProvider.shared.coordinate
        let sunset = (item.mode == .sunset) ? coord.flatMap { SolarCalc.nextSunset(after: now, latitude: $0.latitude, longitude: $0.longitude) } : nil
        let target = CountdownTarget.resolve(item, now: now,
                                             nextEventStart: EventKitService.shared.nextEvent?.startDate,
                                             nextEventTitle: EventKitService.shared.nextEvent?.title,
                                             sunsetTarget: sunset).date
        let interval = target.timeIntervalSince(now)
        if interval <= 0 { return (0, 0, 0, 0, true) }
        let total = Int(interval)
        return (total / 86400, (total % 86400) / 3600, (total % 3600) / 60, total % 60, false)
    }
```

Also update `HUDView.timeBody(for:)` and `hudLabel(for:)` the same way — wherever they call `CountdownTarget.resolve(...)`, add:
```swift
                                             sunsetTarget: (item.mode == .sunset) ? LocationProvider.shared.coordinate.flatMap { SolarCalc.nextSunset(after: now, latitude: $0.latitude, longitude: $0.longitude) } : nil
```
as the final argument of the resolve call.

In `Sources/Countdown/MenuBarController.swift`, `tick()` calls `CountdownTarget.resolve(primary, now: now, nextEventStart: ..., nextEventTitle: ...)`. Add the sunset arg:

```swift
        let sunset = (primary.mode == .sunset) ? LocationProvider.shared.coordinate.flatMap { SolarCalc.nextSunset(after: now, latitude: $0.latitude, longitude: $0.longitude) } : nil
        let resolved = CountdownTarget.resolve(primary, now: now,
                                               nextEventStart: EventKitService.shared.nextEvent?.startDate,
                                               nextEventTitle: EventKitService.shared.nextEvent?.title,
                                               sunsetTarget: sunset)
```
(Insert the `let sunset = ...` line immediately before the existing `let resolved = CountdownTarget.resolve(...)` and add `sunsetTarget: sunset` to that call.)

- [ ] **Step 4: main.swift — sunset target in notification rescheduling**

In `AppDelegate.rescheduleNotifications()`, the body currently calls `NotificationScheduler.shared.reschedule(items:nextEventStart:nextEventTitle:)`. Sunset alerts need a target too, but `reschedule`/`AlertPlanner.plannedRequests` only resolve one shared nextEvent/sunset. For YAGNI, sunset countdowns won't get pre-scheduled alerts in this pass (alerts already work for daily/fixed/next-event). **No change to main.swift** — leave a code comment in `rescheduleNotifications` documenting that sunset alerts are deferred:

Find `rescheduleNotifications()` and add a comment line at its top:

```swift
    private func rescheduleNotifications() {
        // Sunset-mode alerts are deferred: AlertPlanner resolves without a sunset
        // target, so sunset countdowns simply schedule no notifications for now.
        let svc = EventKitService.shared
        ...
    }
```

- [ ] **Step 5: Build + tests + bundle**

Run: `swift build` → Build complete.
Run: `swift test` → all pass.
Run: `./build-app.sh` → Built Countdown.app.

- [ ] **Step 6: Commit**

```bash
git add Sources/Countdown/ContentView.swift Sources/Countdown/MenuBarController.swift Sources/Countdown/main.swift
git commit -m "feat: render sunset mode in row/HUD/menu bar"
```

---

## Task 5: Sunset settings UI (`CountdownEditor`)

**Files:**
- Modify: `Sources/Countdown/ContentView.swift` (`CountdownEditor`)

READ `CountdownEditor` first. Its mode `Picker` has an `.onChange(of: item.mode)` that requests calendar access for `.nextEvent`. There are existing `@ViewBuilder` blocks (`nextEventControls`, `alertControls`, `calendarControls`).

- [ ] **Step 1: Request location lazily when Sunset is chosen**

In `CountdownEditor`, the mode picker's `.onChange(of: item.mode)` currently handles `.nextEvent`. Extend it:

```swift
            .onChange(of: item.mode) { newMode in
                if newMode == .nextEvent && !EventKitService.shared.hasAccess {
                    EventKitService.shared.requestAccess { _ in }
                }
                if newMode == .sunset {
                    LocationProvider.shared.requestAccessIfNeeded()
                }
            }
```

- [ ] **Step 2: Show sunset controls when in sunset mode**

In `CountdownEditor`'s body, where it conditionally shows `nextEventControls` (e.g. `if item.mode == .nextEvent { nextEventControls }`), add right after it:

```swift
            if item.mode == .sunset {
                sunsetControls
            }
```

- [ ] **Step 3: Add the `sunsetControls` view + manual-entry state**

In `struct CountdownEditor`, add a state property near the top (after `@Binding var item: Countdown`):

```swift
    @ObservedObject private var location = LocationProvider.shared
    @State private var manualLat: String = ""
    @State private var manualLon: String = ""
```

Add this `@ViewBuilder` before `private func hmBinding(`:

```swift
    @ViewBuilder private var sunsetControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if location.coordinate != nil && !location.authorizationDenied {
                Text("Using your location")
                    .font(.system(size: 11, weight: .medium))
            } else if location.authorizationDenied {
                Text("Location denied — enter coordinates below")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            } else {
                Text("Set your location below (or allow Location access)")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                TextField("Latitude", text: $manualLat).textFieldStyle(.roundedBorder).frame(width: 90)
                TextField("Longitude", text: $manualLon).textFieldStyle(.roundedBorder).frame(width: 90)
                Button("Set") {
                    if let la = Double(manualLat), let lo = Double(manualLon) {
                        location.setManualCoordinate(latitude: la, longitude: lo)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(Double(manualLat) == nil || Double(manualLon) == nil)
                Spacer()
            }
        }
    }
```

- [ ] **Step 4: Build + bundle**

Run: `swift build` → Build complete.
Run: `swift test` → all pass.
Run: `./build-app.sh` → Built Countdown.app.

- [ ] **Step 5: Commit**

```bash
git add Sources/Countdown/ContentView.swift
git commit -m "feat: add sunset-mode settings (location status + manual coordinates)"
```

---

## Task 6: Info.plist key, full verification, smoke-test handoff

**Files:**
- Modify: `build-app.sh`

- [ ] **Step 1: Add the location usage-description key**

In `build-app.sh`, inside the generated Info.plist heredoc, immediately before the existing `NSCalendarsUsageDescription` key, add:

```xml
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Countdown uses your location to compute today's sunset time.</string>
```

- [ ] **Step 2: Full unit-test pass**

Run: `swift test`
Expected: all pass, 0 failures (now includes SolarCalcTests, LocationValidationTests, and the new CountdownTargetTests sunset cases).

- [ ] **Step 3: Bundle**

Run: `bash -n build-app.sh` (syntax ok), then `./build-app.sh` → "Built Countdown.app".

- [ ] **Step 4: Commit**

```bash
git add build-app.sh
git commit -m "build: add NSLocationWhenInUseUsageDescription for sunset mode"
```

- [ ] **Step 5: Smoke-test checklist (human)**

Report (do NOT attempt GUI automation) that the human should: switch a countdown to **Sunset** mode → grant Location when prompted (or enter manual lat/long) → confirm a "SUNSET" badge + a countdown to a plausible sunset time + subtitle "sunset · H:MM pm"; deny location and confirm the manual lat/long entry makes it work; confirm a fixed/daily/next-event countdown is unaffected.

---

## Self-review notes

- **Spec coverage:** solar calc (Task 1), `.sunset` mode + resolver + no-new-Codable-fields (Task 2), CoreLocation + manual fallback + validation (Task 3), row/HUD/menu rendering + badge + subtitle + no-location hint (Task 4), settings with location status + manual entry + lazy permission (Task 5), Info.plist key + tests + bundle (Task 6). All mapped.
- **Deferred per spec:** sunrise/golden-hour, WeatherKit, per-countdown location. Also: pre-scheduled **sunset alerts** are explicitly deferred (Task 4 Step 4 comment) — daily/fixed/next-event alerts unaffected.
- **Type consistency:** `SolarCalc.sunset(on:latitude:longitude:timeZone:) -> Date?`, `SolarCalc.nextSunset(after:latitude:longitude:timeZone:) -> Date?`, `LocationProvider.shared.coordinate: Coordinate?` (`.latitude`/`.longitude`), `LocationProvider.isValid(latitude:longitude:)`, `LocationProvider.requestAccessIfNeeded()`, `setManualCoordinate(latitude:longitude:)`, `CountdownMode.sunset`, `CountdownTarget.resolve(_:now:nextEventStart:nextEventTitle:sunsetTarget:)` — used consistently across tasks.
```
