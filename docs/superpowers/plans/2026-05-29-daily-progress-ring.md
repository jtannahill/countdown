# Daily Progress Ring Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a small top-right radial ring to the countdown row that fills with the fraction of the daily window (reset→target) elapsed, shown for daily / EOD-fallback countdowns only.

**Architecture:** A pure `DailyProgress.fraction` + a `Countdown.dailyWindow` helper (refactored out of `currentTarget`) compute the fraction (both unit-tested). A native SwiftUI `ProgressRing` (`Circle().trim`, not Swift Charts — macOS 13 target) renders it. `CountdownRow` overlays it top-right when visible.

**Tech Stack:** Swift 5.9, SwiftPM executable, SwiftUI, XCTest. macOS 13.

**Spec:** `docs/superpowers/specs/2026-05-29-daily-progress-ring-design.md`

---

## File map

- Modify `Sources/Countdown/Models.swift` — extract `dailyWindow(now:)` from `currentTarget`.
- Create `Sources/Countdown/DailyProgress.swift` — pure `fraction(now:reset:target:)`.
- Create `Sources/Countdown/ProgressRing.swift` — SwiftUI ring view.
- Modify `Sources/Countdown/ContentView.swift` — `CountdownRow` computes visibility/fraction and overlays the ring.
- Create `Tests/CountdownTests/DailyWindowTests.swift`, `Tests/CountdownTests/DailyProgressTests.swift`.

Test note: `swift test --filter X` prints a swift-testing "0 tests" line separately; the XCTest "Executed N tests" line is what matters.

---

## Task 1: `Countdown.dailyWindow` (refactor out of `currentTarget`)

**Files:**
- Modify: `Sources/Countdown/Models.swift` (the `currentTarget(now:)` method on `struct Countdown`)
- Test: `Tests/CountdownTests/DailyWindowTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CountdownTests/DailyWindowTests.swift`:

```swift
import XCTest
@testable import Countdown

final class DailyWindowTests: XCTestCase {
    private let cal = Calendar.current

    func testDailyWindowResetAndTargetHours() {
        let c = Countdown(label: "EOD")   // .daily, reset 9:00, target 17:30
        let now = cal.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!
        let win = c.dailyWindow(now: now)
        XCTAssertNotNil(win)
        XCTAssertEqual(cal.component(.hour, from: win!.reset), 9)
        XCTAssertEqual(cal.component(.minute, from: win!.reset), 0)
        XCTAssertEqual(cal.component(.hour, from: win!.target), 17)
        XCTAssertEqual(cal.component(.minute, from: win!.target), 30)
        XCTAssertLessThan(win!.reset, now)
        XCTAssertGreaterThan(win!.target, now)
    }

    func testDailyWindowNilForFixed() {
        var c = Countdown(label: "X")
        c.mode = .fixed
        XCTAssertNil(c.dailyWindow(now: Date()))
    }

    func testCurrentTargetUnchangedAfterRefactor() {
        let c = Countdown(label: "EOD")
        let now = cal.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!
        let t = c.currentTarget(now: now)
        XCTAssertEqual(cal.component(.hour, from: t), 17)
        XCTAssertEqual(cal.component(.minute, from: t), 30)
        // For daily mode, currentTarget must equal the window's target.
        XCTAssertEqual(t, c.dailyWindow(now: now)!.target)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter DailyWindowTests`
Expected: FAIL — "value of type 'Countdown' has no member 'dailyWindow'".

- [ ] **Step 3: Refactor `currentTarget` to use a new `dailyWindow`**

In `Sources/Countdown/Models.swift`, replace the entire existing `currentTarget(now:)` method:

```swift
    func currentTarget(now: Date = Date()) -> Date {
        switch mode {
        case .fixed:
            return Date(timeIntervalSince1970: targetTimestamp)
        case .daily, .nextEvent:
            // .nextEvent uses this only as its EOD fallback; the live event
            // target is resolved by CountdownTarget (see Task 2 onward).
            let cal = Calendar.current
            var anchorComps = cal.dateComponents([.year, .month, .day], from: now)
            anchorComps.hour = resetHour
            anchorComps.minute = resetMinute
            anchorComps.second = 0
            let todayReset = cal.date(from: anchorComps) ?? now
            let anchor = todayReset <= now ? todayReset : (cal.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset)
            var targetComps = cal.dateComponents([.year, .month, .day], from: anchor)
            targetComps.hour = targetHour
            targetComps.minute = targetMinute
            targetComps.second = 0
            return cal.date(from: targetComps) ?? now
        }
    }
```

with this (delegates to a new `dailyWindow`, same math, no behavior change):

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

    /// The daily reset→target window for daily / next-event modes (nil for .fixed).
    /// `reset` is the most recent reset time at or before `now`; `target` is the
    /// target time on that same anchor day.
    func dailyWindow(now: Date = Date()) -> (reset: Date, target: Date)? {
        guard mode != .fixed else { return nil }
        let cal = Calendar.current
        var anchorComps = cal.dateComponents([.year, .month, .day], from: now)
        anchorComps.hour = resetHour
        anchorComps.minute = resetMinute
        anchorComps.second = 0
        let todayReset = cal.date(from: anchorComps) ?? now
        let reset = todayReset <= now ? todayReset : (cal.date(byAdding: .day, value: -1, to: todayReset) ?? todayReset)
        var targetComps = cal.dateComponents([.year, .month, .day], from: reset)
        targetComps.hour = targetHour
        targetComps.minute = targetMinute
        targetComps.second = 0
        let target = cal.date(from: targetComps) ?? now
        return (reset, target)
    }
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter DailyWindowTests` → "Executed 3 tests, with 0 failures".
Then run the full suite to confirm no regression: `swift test` → all pass (now 22 total).

- [ ] **Step 5: Commit**

```bash
git add Sources/Countdown/Models.swift Tests/CountdownTests/DailyWindowTests.swift
git commit -m "feat: extract Countdown.dailyWindow from currentTarget"
```

---

## Task 2: `DailyProgress.fraction`

**Files:**
- Create: `Sources/Countdown/DailyProgress.swift`
- Test: `Tests/CountdownTests/DailyProgressTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/CountdownTests/DailyProgressTests.swift`:

```swift
import XCTest
@testable import Countdown

final class DailyProgressTests: XCTestCase {
    private let reset = Date(timeIntervalSince1970: 1000)
    private let target = Date(timeIntervalSince1970: 2000)

    func testMidWindowIsHalf() {
        let f = DailyProgress.fraction(now: Date(timeIntervalSince1970: 1500), reset: reset, target: target)
        XCTAssertEqual(f!, 0.5, accuracy: 0.0001)
    }
    func testAtResetIsZero() {
        XCTAssertEqual(DailyProgress.fraction(now: reset, reset: reset, target: target)!, 0.0, accuracy: 0.0001)
    }
    func testAtTargetIsOne() {
        XCTAssertEqual(DailyProgress.fraction(now: target, reset: reset, target: target)!, 1.0, accuracy: 0.0001)
    }
    func testBeforeResetIsNil() {
        XCTAssertNil(DailyProgress.fraction(now: Date(timeIntervalSince1970: 500), reset: reset, target: target))
    }
    func testAfterTargetIsNil() {
        XCTAssertNil(DailyProgress.fraction(now: Date(timeIntervalSince1970: 2500), reset: reset, target: target))
    }
    func testZeroOrInvertedWindowIsNil() {
        XCTAssertNil(DailyProgress.fraction(now: reset, reset: reset, target: reset))
        XCTAssertNil(DailyProgress.fraction(now: reset, reset: target, target: reset))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter DailyProgressTests`
Expected: FAIL — "cannot find 'DailyProgress' in scope".

- [ ] **Step 3: Write the implementation**

Create `Sources/Countdown/DailyProgress.swift`:

```swift
import Foundation

/// Pure: fraction [0,1] of a reset→target window that has elapsed at `now`,
/// or nil when `now` is outside the window (so the caller hides the indicator).
enum DailyProgress {
    static func fraction(now: Date, reset: Date, target: Date) -> Double? {
        let total = target.timeIntervalSince(reset)
        guard total > 0 else { return nil }
        let elapsed = now.timeIntervalSince(reset)
        guard elapsed >= 0, elapsed <= total else { return nil }
        return elapsed / total
    }
}
```

- [ ] **Step 4: Run to verify pass**

Run: `swift test --filter DailyProgressTests` → "Executed 6 tests, with 0 failures".

- [ ] **Step 5: Commit**

```bash
git add Sources/Countdown/DailyProgress.swift Tests/CountdownTests/DailyProgressTests.swift
git commit -m "feat: add DailyProgress.fraction"
```

---

## Task 3: `ProgressRing` view

**Files:**
- Create: `Sources/Countdown/ProgressRing.swift`

(No unit test — it's a pure SwiftUI view, verified by build + the manual check in Task 4.)

- [ ] **Step 1: Create the view**

Create `Sources/Countdown/ProgressRing.swift`:

```swift
import SwiftUI

/// A small radial progress ring: faint full-circle track with a solid arc that
/// fills clockwise from 12 o'clock to `fraction` (0...1).
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}
```

- [ ] **Step 2: Verify the module builds**

Run: `swift build`
Expected: "Build complete!".

- [ ] **Step 3: Commit**

```bash
git add Sources/Countdown/ProgressRing.swift
git commit -m "feat: add ProgressRing SwiftUI view"
```

---

## Task 4: Show the ring in `CountdownRow`

**Files:**
- Modify: `Sources/Countdown/ContentView.swift` (struct `CountdownRow`)

READ `CountdownRow` first. It has computed properties `accent`, `resolved`, `target`, `displayLabel` near the top, and its `body` ends with:
```swift
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            ...
        }
    }
```

- [ ] **Step 1: Add the `ringFraction` computed property**

In `struct CountdownRow`, add immediately after the existing `private var displayLabel: String { resolved.title ?? item.label }` line:

```swift
    /// Daily-window progress for the ring, or nil when it shouldn't show
    /// (fixed mode, an active next-event, or outside the reset→target window).
    private var ringFraction: Double? {
        guard item.mode != .fixed, resolved.title == nil,
              let win = item.dailyWindow(now: now) else { return nil }
        return DailyProgress.fraction(now: now, reset: win.reset, target: win.target)
    }
```

- [ ] **Step 2: Overlay the ring top-right of the row**

In `CountdownRow.body`, change:

```swift
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
```

to (insert the `.overlay` between the `.frame` and `.contextMenu`):

```swift
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if let f = ringFraction {
                ProgressRing(fraction: f, color: accent)
                    .frame(width: 18, height: 18)
            }
        }
        .contextMenu {
```

- [ ] **Step 3: Build (compile + bundle)**

Run: `swift build` → "Build complete!". IGNORE SourceKit "cannot find in scope" LSP noise; only the real build counts.
Run: `swift test` → all pass (22 tests, 0 failures).
Run: `./build-app.sh` → "Built Countdown.app".

- [ ] **Step 4: Commit**

```bash
git add Sources/Countdown/ContentView.swift
git commit -m "feat: show daily progress ring in the countdown row"
```

- [ ] **Step 5: Manual smoke check (human, after the build is signed/installed)**

Report (do NOT attempt GUI automation) that the human should confirm: a daily countdown shows a small accent ring in the top-right that's partly filled (matching time of day); a fixed-date countdown shows no ring; switching a next-event countdown to an actual upcoming event hides the ring, and it reappears (as the EOD fallback) when no event is imminent.

---

## Self-review notes

- **Spec coverage:** daily-window fraction (Task 2), reset/target derivation reusing `currentTarget` anchoring (Task 1), visibility rule daily + EOD-fallback only / hidden for fixed + active-event + outside-window (Task 4 `ringFraction` + `DailyProgress` nil), top-right accent ring native SwiftUI (Tasks 3+4), unit tests for `DailyProgress` + `dailyWindow` + `currentTarget` regression (Tasks 1+2), no build/entitlement changes. All mapped.
- **Deferred per spec:** percentage label, progress for fixed/active-event, real Swift Charts SectorMark.
- **Type consistency:** `Countdown.dailyWindow(now:) -> (reset: Date, target: Date)?`, `DailyProgress.fraction(now:reset:target:) -> Double?`, `ProgressRing(fraction:color:lineWidth:)`, `CountdownRow.ringFraction: Double?` — used consistently across tasks.
