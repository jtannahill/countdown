# Manual Event Authoring + Calendar Write — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user write a real macOS Calendar event from the widget — both via an "Add to Calendar" action on a Fixed-date countdown (remembering and updating the event) and via a standalone "New event" creator that also makes a matching countdown.

**Architecture:** Extend `EventKitService` (the existing calendar gateway that already holds the `EKEventStore` and full read+write access) with `createEvent`/`updateEvent` plus a pure `EventDraft.end` helper. Store the linked event's identifier + duration on the `Countdown` model. Add SwiftUI controls in `CountdownEditor` (per-countdown) and a `NewEventForm` sheet from `SettingsView` (standalone).

**Tech Stack:** Swift 5.9, SwiftPM executable, SwiftUI + AppKit, EventKit, XCTest. macOS 13 deployment target.

**Spec:** `docs/superpowers/specs/2026-05-28-calendar-event-creation-design.md`

---

## File map

- Modify `Sources/Countdown/Models.swift` — add `calendarEventID`, `eventDurationMinutes` to `Countdown`.
- Modify `Sources/Countdown/EventKitService.swift` — add `EventDraft` pure helper + `createEvent`/`updateEvent`/`withWriteAccess`.
- Modify `Sources/Countdown/ContentView.swift` — `CountdownEditor` calendar controls (fixed mode); new `NewEventForm` sheet + a "New event" button in `SettingsView`.
- Modify `Tests/CountdownTests/ModelCodableTests.swift` — new-field Codable test.
- Create `Tests/CountdownTests/EventDraftTests.swift`.

No `build-app.sh` / Info.plist changes (calendar usage keys already present from the prior feature).

---

## Task 1: Model fields

**Files:**
- Modify: `Sources/Countdown/Models.swift`
- Test: `Tests/CountdownTests/ModelCodableTests.swift`

- [ ] **Step 1: Add the two fields to `Countdown`**

In `struct Countdown`, immediately after `var eventLookaheadHours: Int = 12`, add:

```swift

    // Calendar write: identifier of the linked EKEvent (nil = not added) + its duration.
    var calendarEventID: String? = nil
    var eventDurationMinutes: Int = 60
```

- [ ] **Step 2: Add the keys to `CodingKeys`**

Change the `CodingKeys` enum so the second line reads:

```swift
        case alertOffsets, alertAtZero, eventLookaheadHours
        case calendarEventID, eventDurationMinutes
```

- [ ] **Step 3: Decode them with defaults**

In `init(from decoder:)`, after the `eventLookaheadHours = ...` line, add:

```swift
        calendarEventID = try c.decodeIfPresent(String.self, forKey: .calendarEventID)
        eventDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .eventDurationMinutes) ?? 60
```

- [ ] **Step 4: Write the failing test**

In `Tests/CountdownTests/ModelCodableTests.swift`, add this method inside the `ModelCodableTests` class:

```swift
    func testCalendarFieldsDefaultAndRoundTrip() throws {
        // Legacy blob without the calendar fields decodes to defaults.
        let legacy = """
        [{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","label":"EOD","mode":"fixed",
          "targetTimestamp":12345,"color":"orange"}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([Countdown].self, from: legacy)
        XCTAssertNil(items[0].calendarEventID)
        XCTAssertEqual(items[0].eventDurationMinutes, 60)

        // Round-trip preserves set values.
        var c = Countdown(label: "Launch")
        c.calendarEventID = "ABC-123"
        c.eventDurationMinutes = 90
        let data = try JSONEncoder().encode([c])
        let back = try JSONDecoder().decode([Countdown].self, from: data)
        XCTAssertEqual(back[0].calendarEventID, "ABC-123")
        XCTAssertEqual(back[0].eventDurationMinutes, 90)
    }
```

- [ ] **Step 5: Run the test**

Run: `swift test --filter ModelCodableTests`
Expected: 3 tests pass ("Executed 3 tests, with 0 failures"). (`swift test --filter` prints a separate swift-testing "0 tests" line — ignore it.)

- [ ] **Step 6: Commit**

```bash
git add Sources/Countdown/Models.swift Tests/CountdownTests/ModelCodableTests.swift
git commit -m "feat: add calendarEventID + eventDurationMinutes to Countdown model"
```

---

## Task 2: EventDraft helper + write methods

**Files:**
- Modify: `Sources/Countdown/EventKitService.swift`
- Test: `Tests/CountdownTests/EventDraftTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/CountdownTests/EventDraftTests.swift`:

```swift
import XCTest
@testable import Countdown

final class EventDraftTests: XCTestCase {
    func testEndAddsDuration() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(EventDraft.end(start: start, durationMinutes: 60), start.addingTimeInterval(3600))
        XCTAssertEqual(EventDraft.end(start: start, durationMinutes: 0), start)
        XCTAssertEqual(EventDraft.end(start: start, durationMinutes: 90), start.addingTimeInterval(5400))
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `swift test --filter EventDraftTests`
Expected: FAIL — "cannot find 'EventDraft' in scope".

- [ ] **Step 3: Add the `EventDraft` helper**

In `Sources/Countdown/EventKitService.swift`, add immediately after the `NextEventResolver` enum (the existing `enum NextEventResolver { ... }` block):

```swift

/// Pure helper for event end-time math — unit tested.
enum EventDraft {
    static func end(start: Date, durationMinutes: Int) -> Date {
        start.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter EventDraftTests`
Expected: "Executed 1 test, with 0 failures".

- [ ] **Step 5: Add the write methods to `EventKitService`**

In `Sources/Countdown/EventKitService.swift`, inside `final class EventKitService`, add these methods after the existing `@objc func refresh()` / `setNextEvent` methods (anywhere inside the class body is fine):

```swift
    /// Creates an event in the default calendar. Completion on the main thread with
    /// the new event identifier, or nil on no-access / no-writable-calendar / save failure.
    func createEvent(title: String, start: Date, durationMinutes: Int,
                     completion: @escaping (String?) -> Void) {
        withWriteAccess { granted in
            guard granted, let cal = self.store.defaultCalendarForNewEvents else {
                completion(nil); return
            }
            let event = EKEvent(eventStore: self.store)
            event.title = title
            event.startDate = start
            event.endDate = EventDraft.end(start: start, durationMinutes: durationMinutes)
            event.calendar = cal
            do {
                try self.store.save(event, span: .thisEvent)
                self.refresh()
                completion(event.eventIdentifier)
            } catch {
                completion(nil)
            }
        }
    }

    /// Updates a previously created event. Completion on the main thread: true if updated,
    /// false if the event no longer exists (caller should re-create and relink).
    func updateEvent(id: String, title: String, start: Date, durationMinutes: Int,
                     completion: @escaping (Bool) -> Void) {
        withWriteAccess { granted in
            guard granted, let event = self.store.event(withIdentifier: id) else {
                completion(false); return
            }
            event.title = title
            event.startDate = start
            event.endDate = EventDraft.end(start: start, durationMinutes: durationMinutes)
            do {
                try self.store.save(event, span: .thisEvent)
                self.refresh()
                completion(true)
            } catch {
                completion(false)
            }
        }
    }

    /// Ensures calendar access (requesting lazily), then runs `work` on the main thread.
    private func withWriteAccess(_ work: @escaping (Bool) -> Void) {
        if hasAccess {
            DispatchQueue.main.async { work(true) }
        } else {
            requestAccess { granted in work(granted) }  // requestAccess already calls back on main
        }
    }
```

- [ ] **Step 6: Verify the module builds**

Run: `swift build`
Expected: "Build complete!". (`EKEvent`, `store.save`, `store.event(withIdentifier:)`, `defaultCalendarForNewEvents` are all macOS SDK APIs; the file already `import EventKit`.)

- [ ] **Step 7: Commit**

```bash
git add Sources/Countdown/EventKitService.swift Tests/CountdownTests/EventDraftTests.swift
git commit -m "feat: add EventDraft helper + createEvent/updateEvent to EventKitService"
```

---

## Task 3: CountdownEditor — duration + Add/Update Calendar button

**Files:**
- Modify: `Sources/Countdown/ContentView.swift` (struct `CountdownEditor`)

READ `CountdownEditor` first. It currently has a block:
```swift
            if item.mode == .fixed {
                DatePicker(
                    "Target",
                    selection: Binding( ... ),
                    displayedComponents: [.date, .hourAndMinute]
                )
            } else {
                HStack(spacing: 16) { ... RESETS AT / COUNTS DOWN TO ... }
            }
```

- [ ] **Step 1: Add a state property for the inline note**

In `struct CountdownEditor`, add after `@Binding var item: Countdown`:

```swift
    @State private var calendarNote: String?
```

- [ ] **Step 2: Show the calendar controls in fixed mode**

Inside the `if item.mode == .fixed {` branch, immediately after the closing `)` of the `DatePicker(...)` call (still inside the `if`), add:

```swift
                calendarControls
```

- [ ] **Step 3: Add the `calendarControls` view + actions**

In `struct CountdownEditor`, add these members just before `private func hmBinding(...)`:

```swift
    @ViewBuilder private var calendarControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper("Duration: \(item.eventDurationMinutes / 60)h \(item.eventDurationMinutes % 60)m",
                    value: $item.eventDurationMinutes, in: 15...480, step: 15)
                .font(.system(size: 11))
            HStack(spacing: 8) {
                Button(item.calendarEventID == nil ? "Add to Calendar" : "Update Calendar event") {
                    addOrUpdateCalendarEvent()
                }
                .buttonStyle(.bordered)
                if item.calendarEventID != nil {
                    Text("Added ✓").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if let calendarNote {
                Text(calendarNote).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private func addOrUpdateCalendarEvent() {
        calendarNote = nil
        let start = Date(timeIntervalSince1970: item.targetTimestamp)
        let title = item.label
        let dur = item.eventDurationMinutes
        if let id = item.calendarEventID {
            EventKitService.shared.updateEvent(id: id, title: title, start: start, durationMinutes: dur) { ok in
                if !ok { createAndLink(title: title, start: start, dur: dur) }
            }
        } else {
            createAndLink(title: title, start: start, dur: dur)
        }
    }

    private func createAndLink(title: String, start: Date, dur: Int) {
        EventKitService.shared.createEvent(title: title, start: start, durationMinutes: dur) { newID in
            if let newID {
                item.calendarEventID = newID
            } else {
                calendarNote = EventKitService.shared.hasAccess
                    ? "Couldn't save to Calendar."
                    : "Calendar access denied — enable in System Settings ▸ Privacy ▸ Calendars"
            }
        }
    }
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: "Build complete!".

- [ ] **Step 5: Commit**

```bash
git add Sources/Countdown/ContentView.swift
git commit -m "feat: add per-countdown Add/Update Calendar event controls"
```

---

## Task 4: SettingsView "New event" sheet

**Files:**
- Modify: `Sources/Countdown/ContentView.swift` (struct `SettingsView` + new struct `NewEventForm`)

READ `SettingsView` first. Its header `HStack` currently contains a "Countdowns" `Text`, a `Spacer()`, and a single `Button { store.add() } label: { Label("Add", systemImage: "plus") }`.

- [ ] **Step 1: Add presentation state to `SettingsView`**

In `struct SettingsView`, add after the `@ObservedObject var settings: AppSettings` line:

```swift
    @State private var showingNewEvent = false
```

- [ ] **Step 2: Add the "New event" button**

In the header `HStack`, immediately before the existing `Button { store.add() } ...`, add:

```swift
                Button { showingNewEvent = true } label: { Label("New event", systemImage: "calendar.badge.plus") }
```

- [ ] **Step 3: Attach the sheet**

On `SettingsView`'s outermost `VStack` (the one that ends with `.padding(22)` then `.frame(width: 480)`), add a `.sheet` modifier — put it right after `.frame(width: 480)`:

```swift
        .sheet(isPresented: $showingNewEvent) {
            NewEventForm(store: store)
        }
```

- [ ] **Step 4: Add the `NewEventForm` struct**

In `Sources/Countdown/ContentView.swift`, add this new struct at the end of the file (after `CountdownEditor`):

```swift
struct NewEventForm: View {
    @ObservedObject var store: CountdownStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = "New event"
    @State private var start = Date().addingTimeInterval(3600)
    @State private var durationMinutes = 60
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New event").font(.system(size: 15, weight: .semibold))
            TextField("Title", text: $title).textFieldStyle(.roundedBorder)
            DatePicker("Start", selection: $start, displayedComponents: [.date, .hourAndMinute])
            Stepper("Duration: \(durationMinutes / 60)h \(durationMinutes % 60)m",
                    value: $durationMinutes, in: 15...480, step: 15)
            if let note {
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func create() {
        note = nil
        let t = title
        let s = start
        let dur = durationMinutes
        EventKitService.shared.createEvent(title: t, start: s, durationMinutes: dur) { newID in
            guard let newID else {
                note = EventKitService.shared.hasAccess
                    ? "Couldn't save to Calendar."
                    : "Calendar access denied — enable in System Settings ▸ Privacy ▸ Calendars"
                return
            }
            var c = Countdown(label: t)
            c.mode = .fixed
            c.targetTimestamp = s.timeIntervalSince1970
            c.eventDurationMinutes = dur
            c.calendarEventID = newID
            store.items.append(c)
            dismiss()
        }
    }
}
```

- [ ] **Step 5: Build the app bundle (verifies SwiftUI compiles + bundles)**

Run: `swift build` — expect "Build complete!".
Run: `./build-app.sh` — expect "Built Countdown.app".

- [ ] **Step 6: Commit**

```bash
git add Sources/Countdown/ContentView.swift
git commit -m "feat: add standalone New event creator (writes event + linked countdown)"
```

---

## Task 5: Full verification + smoke-test handoff

**Files:** none (verification only)

- [ ] **Step 1: Full unit-test pass**

Run: `swift test`
Expected: all tests pass, 0 failures (now includes `EventDraftTests` + the extended `ModelCodableTests`, plus the prior 17). Confirm the "Executed N tests, with 0 failures" line.

- [ ] **Step 2: Build the bundle**

Run: `./build-app.sh`
Expected: "Built Countdown.app".

- [ ] **Step 3: Report the smoke-test checklist for the human**

This feature touches the live Calendar and the GUI, so report (do NOT attempt interactive GUI testing yourself) that the human should:
1. Open a Fixed-date countdown in Settings, set a duration, press **Add to Calendar** → confirm the event appears in macOS Calendar with the right title/time/duration; the button becomes **Update Calendar event** with "Added ✓".
2. Change the label/time, press **Update Calendar event** → confirm the SAME event updates (no duplicate).
3. Press **New event** in Settings → fill title/start/duration → **Create** → confirm a Calendar event AND a matching fixed-date countdown both appear.
4. Delete the linked event in Calendar, then press **Update Calendar event** → confirm a fresh event is created and relinked (no stuck error).

- [ ] **Step 4: Commit (no-op if nothing changed)**

No code changes in this task; nothing to commit.

---

## Self-review notes

- **Spec coverage:** both-direction write (Tasks 3 + 4), minimal fields title/start/duration (Tasks 2–4), remember-and-update linkage via `calendarEventID` (Tasks 1, 3), explicit writes / no auto-rewrite (Task 3 button-driven), no permission/build changes (reuses `hasAccess` + existing Info.plist keys), `EventDraft` pure helper tested (Task 2), Codable upgrade tested (Task 1), update-when-deleted → recreate (Task 3 `addOrUpdateCalendarEvent`/`createAndLink`). All mapped.
- **Deferred per spec:** all-day, calendar picker, notes, location, alarms; delete-event-on-countdown-delete; two-way sync.
- **Type consistency:** `Countdown.calendarEventID: String?`, `Countdown.eventDurationMinutes: Int`; `EventDraft.end(start:durationMinutes:)`; `EventKitService.createEvent(title:start:durationMinutes:completion:)` (→ `String?`), `updateEvent(id:title:start:durationMinutes:completion:)` (→ `Bool`), `withWriteAccess(_:)`; UI helpers `calendarControls`, `addOrUpdateCalendarEvent()`, `createAndLink(title:start:dur:)`, `NewEventForm`. Used consistently across tasks.
