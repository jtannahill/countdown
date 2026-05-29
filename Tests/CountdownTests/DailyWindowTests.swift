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

    func testDailyWindowBeforeResetAnchorsToPreviousDay() {
        let c = Countdown(label: "EOD")   // reset 9:00, target 17:30
        let now = cal.date(bySettingHour: 7, minute: 0, second: 0, of: Date())!  // before reset
        let win = c.dailyWindow(now: now)!
        // Most-recent reset at/before 7am is yesterday's 9:00 → both edges are in the past.
        XCTAssertLessThan(win.reset, now)
        XCTAssertLessThan(win.target, now)
        XCTAssertEqual(cal.component(.hour, from: win.reset), 9)
        XCTAssertEqual(cal.component(.hour, from: win.target), 17)
        XCTAssertFalse(cal.isDate(win.reset, inSameDayAs: now))
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
        XCTAssertEqual(t, c.dailyWindow(now: now)!.target)
    }
}
