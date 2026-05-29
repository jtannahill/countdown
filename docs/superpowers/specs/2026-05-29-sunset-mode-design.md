# Countdown — Sunset mode (solar-calc, no WeatherKit)

**Date:** 2026-05-29
**Status:** Approved design — ready for implementation plan
**Builds on:** the shipped widget (`main` `153070f`).

## Goal

Add a **Sunset** countdown mode: count down to today's sunset at the user's location
(rolling to tomorrow's after sunset passes).

## Key feasibility decision (locked)

This was filed under "WeatherKit," but WeatherKit (framework) needs the
`com.apple.developer.weatherkit` entitlement + an App ID capability + a provisioning
profile, which this ad-hoc/Apple-Development SwiftPM-bundled app (no Xcode project) can't
readily provide; the REST API needs a `.p8` key + JWT signing + network. Sunset/sunrise are
**purely computable from latitude/longitude + date** via the standard NOAA solar algorithm —
accurate to ~1 minute, no entitlement, no key, no network. **We use a local solar
calculation + CoreLocation.** ("WeatherKit proper" stays parked behind the eventual
Xcode-project migration.)

## Behavioral decisions (locked)

- A new **`CountdownMode.sunset`** (4th mode: Daily / Fixed / Next event / Sunset).
- Counts down to **today's sunset**; after sunset passes, rolls to **tomorrow's**.
- Location via **CoreLocation**, lazily prompted; **manual lat/long fallback** (stored
  app-wide) so it works even if Location is denied.
- Sunset only (no sunrise / golden-hour markers — deferred).

## Architecture

### `Sources/Countdown/SolarCalc.swift` (new — pure, unit-tested)
- `static func sunset(on date: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> Date?`
  — NOAA sunrise/sunset algorithm for the local day of `date`; returns the sunset instant,
  or `nil` for polar no-sunset days.
- `static func nextSunset(after now: Date, latitude: Double, longitude: Double, timeZone: TimeZone = .current) -> Date?`
  — today's sunset if it's still ahead of `now`, otherwise tomorrow's. `nil` if neither has
  a sunset (polar).

### `Sources/Countdown/LocationProvider.swift` (new — ObservableObject singleton)
- Wraps `CLLocationManager` (is its delegate). `@Published private(set) var coordinate: Coordinate?`
  where `Coordinate = (latitude: Double, longitude: Double)`.
- **Precedence:** live CoreLocation (when authorized + a fix is available) → manually-stored
  coordinates (UserDefaults keys `manualLat`/`manualLon`) → `nil`.
- `func requestAccessIfNeeded()` — lazily calls `requestWhenInUseAuthorization()` /
  `requestLocation()`; safe to call repeatedly.
- `func setManualCoordinate(latitude: Double, longitude: Double)` — validates lat ∈ [−90,90],
  lon ∈ [−180,180]; persists to UserDefaults and republishes. `func clearManualCoordinate()`.
- `var authorizationDenied: Bool` for the settings status line.
- The live `CLLocationManager` wrapper is NOT unit-tested (verified manually); coordinate
  precedence/validation logic is simple and may be exercised via the manual setters.

### `Sources/Countdown/Models.swift` (modified)
- `CountdownMode` gains `case sunset` (label "Sunset"). **No new `Countdown` Codable fields**
  (manual coordinates live app-wide in UserDefaults), so old `countdowns.v2` blobs upgrade
  with no migration.
- `dailyWindow(now:)` returns `nil` for `.sunset` (it's not a reset→target window).
- `currentTarget(now:)` gets a `.sunset` case returning `now` (degenerate placeholder — the
  real sunset target is supplied to the resolver; `currentTarget` has no location).

### `Sources/Countdown/CountdownTarget.swift` (modified)
- `resolve(_:now:nextEventStart:nextEventTitle:sunsetTarget:)` gains a `sunsetTarget: Date?`
  parameter (mirroring `nextEventStart`). For a `.sunset` countdown: if `sunsetTarget` is
  non-nil → return it; else → the "no location" fallback (`currentTarget(now:)`, i.e. `now`).
  All existing daily/fixed/next-event behavior unchanged.

### Wiring (`ContentView.swift`, `MenuBarController.swift`, `main.swift`)
- `CountdownRow`/`HUDView`/`MenuBarController`/notification rescheduling compute
  `sunsetTarget = LocationProvider.shared.coordinate.flatMap { SolarCalc.nextSunset(after: now, latitude: $0.latitude, longitude: $0.longitude) }`
  and pass it into `CountdownTarget.resolve`. Same pattern as the EventKit `nextEvent` target.

## UI

### `CountdownRow`
- A **"SUNSET" badge** (same style as DAILY/NEXT) in sunset mode.
- Subtitle: e.g. `sunset · 8:14 pm`.
- **No coordinates** (denied + no manual entry) or polar no-sunset → show the label + a quiet
  `Set location in settings` hint instead of a bogus countdown.

### `CountdownEditor` (settings)
- Mode picker shows the 4th segment automatically (`CountdownMode.allCases`).
- When `.sunset`: a block with a status line (*Using your location* / *Location denied — enter
  coordinates below* / *Set your location below*), **manual latitude/longitude fields** bound to
  `LocationProvider`, and selecting Sunset lazily calls `LocationProvider.requestAccessIfNeeded()`.

## Permissions / build

- `build-app.sh` Info.plist gains `NSLocationWhenInUseUsageDescription`
  ("Countdown uses your location to compute today's sunset time.").
- macOS, non-sandboxed, no hardened runtime → usage string + one-time TCC prompt is all
  CoreLocation needs (no entitlement/provisioning — same as Calendar).

## Error & edge handling

- Polar no-sunset day (`SolarCalc` returns nil) → quiet "no sunset today" state (same as no-location hint).
- Manual coordinates out of range → ignored (not stored).
- After sunset → `nextSunset` rolls to tomorrow's.
- Location denied → manual coordinates used if present, else the hint.

## Testing

- **`SolarCalcTests`**: `sunset(on:latitude:longitude:timeZone:)` vs a known reference
  (fixed date + coordinates, ±2 min tolerance); polar summer latitude → `nil`; `nextSunset`
  returns today's sunset when ahead, tomorrow's when passed.
- **`CountdownTarget` `.sunset` tests**: `sunsetTarget` present → returned; `nil` → fallback;
  existing daily/fixed/next-event resolution unchanged.
- **Coordinate validation test**: out-of-range lat/long rejected by `setManualCoordinate`.
- **Not unit-tested** (build + on-device check): `LocationProvider` live `CLLocationManager`
  wrapper; SwiftUI settings/row rendering.

## Out of scope (deferred)

- Sunrise / golden-hour markers.
- WeatherKit framework or REST API (waits for the Xcode-project migration).
- Per-countdown (vs app-wide) location.
