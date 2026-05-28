# Countdown — EventKit "Next event" mode + UserNotifications alerts

**Date:** 2026-05-28
**Status:** Approved design — ready for implementation plan
**Scope:** Group A, sub-project 1 of the macOS-frameworks roadmap (see "Roadmap context").

## Roadmap context

The user selected six integrations for the Countdown widget. They split by what the
current build system (SwiftPM executable + `build-app.sh` hand-assembled `.app`,
ad-hoc signed) can support:

- **Group A — works in the current SwiftPM/ad-hoc setup:** EventKit, UserNotifications,
  Swift Charts.
- **Group B — requires migrating to an Xcode project with signing + entitlements +
  provisioning:** CloudKit (iCloud container), WidgetKit (extension target + App Group),
  AppIntents (works in SwiftPM but more reliable in a signed Xcode app).

Agreed sequencing: **Group A first, then the Xcode-project migration as the gateway to
Group B.** This spec covers the first Group A sub-project: the EventKit "Next event"
countdown mode and UserNotifications alerts (the "first two" features). Swift Charts is a
separate later spec.

## Goal

Turn the countdown widget from a static timer into something that (a) can automatically
track the user's next calendar event, and (b) proactively notifies before a countdown
reaches its target.

## Behavioral decisions (locked)

### Next-event mode
- A **third `CountdownMode`: `.nextEvent`**, alongside `.daily` and `.fixed`.
- Target = the **start of the soonest timed event across all calendars** (all-day events
  skipped). **Auto-advances** to the following event once the current one begins.
- **Imminence window** = next event starting within `eventLookaheadHours` (default **12h**,
  configurable per countdown).
- **Empty state:** when no event is within the window (evening, weekend, empty calendar,
  or calendar access denied), the countdown **falls back to the daily EOD countdown**
  using the countdown's existing reset/target hours. It is never blank.
- The widget **label auto-fills with the event's title** while an imminent event is shown;
  it shows the user's label (e.g. "EOD") during fallback.

### Notifications
- **Per-countdown alerts, available in every mode** (daily, fixed, next-event):
  - A multi-select set of **"minutes before" thresholds** — preset chips **15 / 10 / 5 / 1**.
  - An **"at zero"** toggle.
- **Firing strategy = Approach A, pre-scheduled OS triggers.** Each alert is registered as
  a `UNNotificationRequest` with a `UNCalendarNotificationTrigger` at its absolute fire
  date, so macOS delivers it even if the app is busy, the widget is hidden, or the Mac just
  woke. Alerts are rescheduled (clear-then-add) whenever the target or settings change.
- **Content:** title = countdown label / event title; body e.g. "10 minutes until EOD",
  "Standup starts in 5 minutes", at-zero "EOD reached".

## Architecture

Three new small, focused, independently testable units. Existing files change minimally.

### `Sources/Countdown/EventKitService.swift` (new)
- Wraps `EKEventStore`.
- `@Published var nextEvent: EKEvent?` — the soonest imminent timed event, or nil.
- Recomputes on launch, on every `.EKEventStoreChanged` notification, and on a 60-second
  periodic refresh (to catch the lookahead window sliding forward / events rolling past).
- `requestAccess()` — `requestFullAccessToEvents()` on macOS 14+, `requestAccess(to:.event)`
  on macOS 13. Exposes authorization status.
- Resolution logic sits behind an **`EventProviding` protocol** (returns candidate events
  for a time range) so it can be unit-tested against a fake store; the live `EKEventStore`
  wrapper stays dumb.

### `Sources/Countdown/NotificationScheduler.swift` (new)
- Wraps `UNUserNotificationCenter`.
- `requestAuthorization()` — requests alert authorization; exposes status.
- `reschedule(items: [Countdown])` — clears our previously-scheduled requests (matched by an
  id prefix), then for each countdown computes `target − offsetMinutes` for each alert plus
  the at-zero time, **drops any fire date in the past**, and registers one
  `UNNotificationRequest` per future alert.
- **Request id** encodes `countdownID + offset` (and a fixed prefix) so clear-then-reschedule
  is exact and idempotent, and stale alerts (e.g. for a meeting that moved) never linger.
- The notification client is behind a thin seam so the fire-date computation can be unit
  tested with a fake.

### `Sources/Countdown/CountdownTarget.swift` (new)
- A single resolver: `target(for: Countdown, now: Date) -> (date: Date, title: String?)`.
- If `mode == .nextEvent` **and** an imminent event exists → `(event.startDate, event.title)`.
- Otherwise → the daily/fixed target via the existing `Countdown.currentTarget(now:)`.
- **Single source of truth** for "next event vs EOD fallback." Consumed by `ContentView`,
  `HUDView`, `MenuBarController`, and `NotificationScheduler`.

### `Sources/Countdown/Models.swift` (modified)
- `CountdownMode` gains `case nextEvent` (with a `label` "Next event").
- `Countdown` gains:
  - `var alertOffsets: [Int]` — minutes-before values, default `[]`.
  - `var alertAtZero: Bool` — default `false`.
  - `var eventLookaheadHours: Int` — default `12`.
- All new fields are added to `CodingKeys` and decoded with `decodeIfPresent ?? default`,
  so an existing `countdowns.v2` blob upgrades cleanly — **no migration step needed**.

### Existing files — minimal changes
- `ContentView.swift` / `HUDView` / `MenuBarController.swift`: replace direct
  `primary.currentTarget(now:)` calls with `CountdownTarget.target(for:now:)`, and use the
  returned title for the label when present.
- `main.swift` (`AppDelegate`): instantiate the services; wire `EventKitService.nextEvent`
  and `CountdownStore.items` changes to `NotificationScheduler.reschedule`.

## Data flow (steady state)

1. `EventKitService` publishes `nextEvent` (refreshed on launch / store-change / 60s timer).
2. UI renders on the existing 1-second tick via `CountdownTarget` — next-event countdowns
   show the event title + countdown to start, or the EOD fallback when nothing is imminent.
3. `NotificationScheduler.reschedule` runs on: (a) `CountdownStore.items` change,
   (b) `EventKitService.nextEvent` change, (c) daily target roll-over. It clears our
   prefixed requests and registers fresh future alerts.

## Permissions (requested lazily, never at launch)

- **Calendar:** requested the first time a countdown is switched to `.nextEvent`. Denied →
  that countdown shows the EOD fallback; Settings shows a one-line
  "Calendar access denied — open System Settings" note.
- **Notifications:** requested the first time any alert is enabled. Denied → scheduling is
  skipped; Settings shows the same style of note.

## Error & edge handling

- No calendar access, or no imminent event → resolver returns the EOD fallback (never blank).
- Event edited / deleted / moved → `.EKEventStoreChanged` re-resolves and reschedules.
- Always clear our prefixed notification requests before re-adding (idempotent; no lingering
  stale alerts).
- Mac asleep at fire time → OS delivers on wake (inherent to `UNCalendarNotificationTrigger`).

## Settings UI (additions to `SettingsView`)

Per countdown row:
- **Mode picker** gains a third segment: *Daily · Fixed date · Next event*.
- When **Next event** is selected, reveal:
  - Read-only preview: "Next: Standup · 2:00 pm" or "No upcoming event — showing EOD".
  - A **lookahead** stepper (hours, default 12).
  - The existing reset/target time fields, relabeled as the **EOD fallback**.
- **Alerts** subsection (all modes): multi-select chips **15 / 10 / 5 / 1 min** +
  **"Notify at zero"** toggle. Inline note if calendar or notification access was denied.

## Testing

Add an `XCTest` target to `Package.swift` (`Tests/CountdownTests`). Cover the pure logic with
EventKit/UN abstracted behind protocols (no system access needed in tests):
- `CountdownTarget` resolution: event-within-window → event; nothing imminent → EOD fallback;
  access-denied → EOD fallback.
- Alert fire-date computation: correct dates per offset; past alerts dropped; at-zero included.
- Request-id encode/decode round-trip.
- `Codable` upgrade: an old `countdowns.v2` blob (no new fields) decodes with correct defaults.

The live `EKEventStore` / `UNUserNotificationCenter` wrappers stay dumb and untested.

## Build / Info.plist changes

- `build-app.sh` generates Info.plist — add:
  - `NSCalendarsUsageDescription`
  - `NSCalendarsFullAccessUsageDescription` (macOS 14+)
- **Signing:** the bundle is currently ad-hoc signed (`codesign --sign -`). Calendar access
  works ad-hoc, but `UserNotifications` banners are unreliable without a stable signing
  identity. Switch `build-app.sh` to sign with a **Developer ID** via a `SIGN_IDENTITY`
  variable at the top of the script (clearly-marked placeholder; falls back to ad-hoc if
  unset). User has an Apple Developer Team; identity to be supplied or auto-detected
  (`security find-identity -v -p codesigning`) during implementation.

## Risks / open items

- **Notification reliability under ad-hoc signing** — mitigated by Developer ID signing
  (above). This is the only item not fully de-riskable in code alone.
- No iOS/watchOS surface here — Live Activities / Lock Screen widgets are out of scope
  (macOS only) and only relevant if a companion mobile app is added later.

## Out of scope (later specs)

- Swift Charts progress arc (Group A, separate spec).
- CloudKit sync, WidgetKit widget, AppIntents (Group B, after the Xcode-project migration).
- Chosen-calendar filtering, count-to-end-if-in-meeting (deferred refinements of next-event
  selection).
