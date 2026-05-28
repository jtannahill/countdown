# Countdown — Manual event authoring + Calendar write

**Date:** 2026-05-28
**Status:** Approved design — ready for implementation plan
**Builds on:** `2026-05-28-eventkit-notifications-design.md` (EventKit read + notifications, already shipped to `main`).

## Goal

Let the user (1) manually create a named, dated countdown (already largely supported by Fixed-date mode + the label field) and (2) write a real event into macOS Calendar via EventKit — in **both directions**: an "Add to Calendar" action on a Fixed-date countdown, and a standalone "New event" creator that writes the event and creates a matching countdown.

## Behavioral decisions (locked)

- **Both directions:** per-countdown "Add to Calendar" AND a standalone "New event" creator.
- **Minimal event fields:** title + start date/time + duration (default 60 min), saved to the default calendar. No all-day / calendar-picker / notes / location / alarm (deferred).
- **Remember & update linkage:** a countdown stores the identifier of the event it created; the button becomes "Update Calendar event" and updates the existing event rather than duplicating.
- **Explicit writes:** editing a linked countdown's label/date does NOT auto-rewrite the event; the user presses "Update Calendar event" to push changes.
- **No new permission/build changes:** write reuses the existing full calendar access (`requestFullAccessToEvents` / `requestAccess(to:.event)` grant read+write) and the `NSCalendarsUsageDescription` / `NSCalendarsFullAccessUsageDescription` keys already in `build-app.sh`.

## Architecture

### `Sources/Countdown/Models.swift` (modified)
Add to `struct Countdown`:
- `var calendarEventID: String? = nil` — `EKEvent.eventIdentifier` of the linked event (nil = never added).
- `var eventDurationMinutes: Int = 60` — duration used when writing the event.

Both added to `CodingKeys` and decoded with `decodeIfPresent ?? default` — no migration. Existing `countdowns.v2` blobs upgrade cleanly.

### `Sources/Countdown/EventKitService.swift` (modified — extend the existing calendar gateway)
Add a tiny pure helper and two live write methods:

- `enum EventDraft { static func end(start: Date, durationMinutes: Int) -> Date }` — pure (`start + durationMinutes * 60`); unit-tested.
- `func createEvent(title: String, start: Date, durationMinutes: Int, completion: @escaping (String?) -> Void)` — ensures access (requests lazily if needed); builds an `EKEvent` on `store.defaultCalendarForNewEvents` with `startDate = start`, `endDate = EventDraft.end(...)`; `try store.save(event, span: .thisEvent)`; calls back on the main thread with `event.eventIdentifier`, or `nil` on no-access / no-writable-calendar / save failure.
- `func updateEvent(id: String, title: String, start: Date, durationMinutes: Int, completion: @escaping (Bool) -> Void)` — `store.event(withIdentifier: id)`; if found, update title/start/end and save → `true`; if not found (deleted externally) → `false` so the caller re-creates and relinks. Main-thread completion.

Write requires full calendar access, which `hasAccess` already represents. The methods guard on `hasAccess` and request access if needed before writing.

### `Sources/Countdown/ContentView.swift` (modified)
- **`CountdownEditor`** (when `mode == .fixed`): a duration `Stepper` bound to `item.eventDurationMinutes` (range 15...480, step 15, shown as "Duration: Xh Ym"); a calendar button:
  - `item.calendarEventID == nil` → "Add to Calendar". On tap: ensure access, then `createEvent(title: item.label, start: Date(timeIntervalSince1970: item.targetTimestamp), durationMinutes: item.eventDurationMinutes)`, storing the returned id into `item.calendarEventID`.
  - non-nil → "Update Calendar event" + an "Added ✓" indicator. On tap: `updateEvent(id:…)`; if it returns `false`, transparently `createEvent(…)` again and replace the stored id.
  - Inline "Calendar access denied …" / "Couldn't save to Calendar" notes on failure.
- **`SettingsView`**: a "New event" button next to the existing "Add". Presents a sheet (`NewEventForm`) with a title field, a start `DatePicker([.date, .hourAndMinute])`, and a duration `Stepper` (default 60). **Create** → ensure access → `createEvent(…)` → on success append a `Countdown(label: title)` with `mode = .fixed`, `targetTimestamp = start`, `eventDurationMinutes`, `calendarEventID = newID`, then dismiss; on failure show an inline error and stay open. **Cancel** dismisses.

## Data flow

1. User triggers a write (per-countdown button or the New event sheet).
2. UI ensures access via `EventKitService` (lazy request), then calls `createEvent`/`updateEvent`.
3. On success: per-countdown flow stores `calendarEventID` on the item (which persists via `CountdownStore`); the New event flow appends a linked fixed-date countdown.
4. `EventKitService.refresh()` will pick up the new event in its next-event scan as usual (no special wiring needed).

## Permissions & error handling

- Both flows request access lazily if `!hasAccess`; proceed only if granted, else show the one-line denied note.
- `defaultCalendarForNewEvents == nil` (no writable calendar) → "Couldn't save to Calendar"; no id stored.
- `store.save`/`store.remove` throwing → caught; surfaced as the same inline note; no id stored.
- `updateEvent` on a since-deleted event → `false` → caller re-creates and relinks (no orphaned button state).

## Testing

- **`EventDraftTests`** (new): `EventDraft.end(start:durationMinutes:)` returns `start + durationMinutes*60` for representative inputs (incl. 0 and large durations).
- **`ModelCodableTests`** (extended): legacy blob → `calendarEventID == nil`, `eventDurationMinutes == 60`; round-trip preserves a set `calendarEventID` and a non-default duration.
- `createEvent`/`updateEvent` hit the live `EKEventStore` and are NOT unit-tested — verified by the manual smoke test (consistent with the rest of `EventKitService`).

## Build

No `build-app.sh` / Info.plist changes — the calendar usage-description keys added in the previous feature already authorize write access.

## Manual smoke test (human)

1. Fixed-date countdown → set duration → "Add to Calendar" → event appears in Calendar with correct title/time/duration.
2. Change the label/time → "Update Calendar event" → the SAME event updates (no duplicate).
3. "New event" sheet → Create → a Calendar event AND a matching fixed-date countdown both appear.
4. Delete the linked event in Calendar, press "Update Calendar event" → a fresh event is created and relinked (no error state).

## Out of scope (deferred)

- All-day events, calendar picker, notes, location, alarms/alerts on created events.
- Deleting the Calendar event when the countdown is deleted (one-way create/update only).
- Two-way sync (editing the countdown does not auto-update the event; user presses Update).
