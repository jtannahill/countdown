# Countdown — Daily progress ring

**Date:** 2026-05-29
**Status:** Approved design — ready for implementation plan
**Builds on:** the shipped widget (`main` `cb3213c`).

## Goal

Add a small radial **progress ring** to the countdown row showing how much of the
daily window (reset → target, e.g. 9am → 5:30pm) has elapsed — a glanceable "how far
through the day" indicator.

> Note on "Swift Charts": this was filed under the Swift Charts idea, but a radial
> arc via Swift Charts (`SectorMark`) requires macOS 14 and the app targets macOS 13.
> So the ring is built with a **native SwiftUI `Circle().trim`**, not the Swift Charts
> framework. Same visual result, no deployment-target change.

## Behavioral decisions (locked)

### What it measures
- Fraction of the **daily window elapsed** = `(now − reset) / (target − reset)`, clamped to 0…1.
  Empty at the reset time, ~half at midday, full at the target.

### When it's visible
- **Daily mode**, and **next-event mode while showing the EOD fallback** (i.e. no imminent
  event — `resolved.title == nil`).
- **Hidden** for fixed-date countdowns, for next-event while an actual event is showing, and
  **outside the active window** (before the reset time / after the target, i.e. while the
  countdown reads WAITING) — so it never displays a misleading 0% or 100% at rest.

### Appearance
- Small ring in the **top-right corner** of the countdown row, in the countdown's **accent
  color** (track at ~15% opacity, fill solid), filling **clockwise from 12 o'clock**.
- **Ring only — no number.** Scales with the widget; updates every tick like the digits.
- It lives in the content layer, so on hover it dims with the rest of the content (the hover
  control buttons overlay it, as they do the digits — acceptable).

## Architecture

### `Sources/Countdown/DailyProgress.swift` (new — pure, unit-tested)
- `enum DailyProgress { static func fraction(now: Date, reset: Date, target: Date) -> Double? }`
  - `total = target − reset`; if `total <= 0` → `nil`.
  - `elapsed = now − reset`; if `elapsed < 0` or `elapsed > total` → `nil` (outside window → hide).
  - else → `elapsed / total`.

### `Countdown.dailyWindow(now:)` (new method on the model, in `Models.swift`)
- `func dailyWindow(now: Date) -> (reset: Date, target: Date)?`
  - Returns `nil` for `.fixed` mode.
  - For `.daily` / `.nextEvent`: compute the same anchor `currentTarget` uses — today's reset
    (`resetHour:resetMinute`) if it's ≤ now, else yesterday's — and the target on that anchor
    day (`targetHour:targetMinute`). Returns `(anchorReset, target)`.
  - (Factor the shared anchoring out of `currentTarget` so both use one helper — no behavior
    change to `currentTarget`.)
- Unit-tested alongside `DailyProgress`.

### `Sources/Countdown/ProgressRing.swift` (new — SwiftUI view)
- `struct ProgressRing: View { let fraction: Double; let color: Color; var lineWidth: CGFloat = 3 }`
  - A faint full-circle track (`color.opacity(0.15)`) under a `Circle().trim(from: 0, to: fraction)`
    stroked in `color`, `rotationEffect(.degrees(-90))` so it starts at 12 o'clock, `.butt`/`.round`
    cap. Fixed small frame (~18pt), scales with the row.

### `CountdownRow` (modified, in `ContentView.swift`)
- Compute ring visibility + fraction:
  - `let ringFraction: Double?` = if `item.mode != .fixed && resolved.title == nil`, and
    `item.dailyWindow(now: now)` is non-nil, then `DailyProgress.fraction(now:reset:target:)`; else `nil`.
- When `ringFraction != nil`, overlay a `ProgressRing(fraction:color:)` in the row's **top-right**
  corner (accent color). No other files change.

## Testing

- **`DailyProgressTests`** (new): mid-window (e.g. 0.5), at-reset (0.0), at-target (1.0),
  before-reset (`nil`), after-target (`nil`), zero/inverted window (`nil`).
- **`Countdown.dailyWindow` tests**: daily mode returns the correct reset/target pair with the
  same anchoring as `currentTarget`; `.fixed` returns `nil`; verify `currentTarget` is unchanged
  after the anchoring refactor.
- `ProgressRing` is a pure SwiftUI view — visual, verified in the build + on-device eyeball.

## Build

No `build-app.sh` / Info.plist / entitlement changes. Native SwiftUI only.

## Out of scope (deferred)

- A percentage label inside/next to the ring.
- Progress for fixed-date or active next-event countdowns (no natural daily window).
- Real Swift Charts `SectorMark` (would require bumping the deployment target to macOS 14).
