import XCTest
@testable import Countdown

final class CountdownTargetTests: XCTestCase {
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
