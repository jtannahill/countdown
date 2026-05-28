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
