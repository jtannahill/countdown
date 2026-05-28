import XCTest
@testable import Countdown

final class AlertPlannerTests: XCTestCase {
    func testRequestIDRoundTrip() {
        let id = UUID()
        let s = AlertRequestID.make(countdownID: id, offsetMinutes: 5)
        XCTAssertTrue(AlertRequestID.isOurs(s))
        let parsed = AlertRequestID.parse(s)
        XCTAssertEqual(parsed?.countdownID, id)
        XCTAssertEqual(parsed?.offsetMinutes, 5)
    }

    func testForeignIDNotOurs() {
        XCTAssertFalse(AlertRequestID.isOurs("some.other.notification"))
        XCTAssertNil(AlertRequestID.parse("some.other.notification"))
    }

    func testThresholdAndZeroFireDates() {
        var c = Countdown(label: "EOD")
        c.alertOffsets = [10, 5]
        c.alertAtZero = true
        let now = Date(timeIntervalSince1970: 1_000_000)
        let target = now.addingTimeInterval(3600) // 60 min away
        let alerts = AlertPlanner.alerts(for: c, targetDate: target, displayLabel: "EOD", isEvent: false, now: now)
        XCTAssertEqual(alerts.count, 3)
        XCTAssertEqual(alerts[0].fireDate, target.addingTimeInterval(-600))
        XCTAssertEqual(alerts[1].fireDate, target.addingTimeInterval(-300))
        XCTAssertEqual(alerts[2].fireDate, target) // at-zero
        XCTAssertEqual(alerts[0].body, "10 minutes until EOD")
        XCTAssertEqual(alerts[2].body, "EOD reached")
    }

    func testPastThresholdsDropped() {
        var c = Countdown(label: "EOD")
        c.alertOffsets = [10, 5]
        c.alertAtZero = true
        let now = Date(timeIntervalSince1970: 1_000_000)
        let target = now.addingTimeInterval(7 * 60) // 7 min away: 10-min alert is in the past
        let alerts = AlertPlanner.alerts(for: c, targetDate: target, displayLabel: "EOD", isEvent: false, now: now)
        XCTAssertEqual(alerts.map(\.offsetMinutes), [5, 0])
    }

    func testEventPhrasingAndSingularMinute() {
        var c = Countdown(label: "EOD")
        c.alertOffsets = [1]
        let now = Date(timeIntervalSince1970: 1_000_000)
        let target = now.addingTimeInterval(3600)
        let alerts = AlertPlanner.alerts(for: c, targetDate: target, displayLabel: "Standup", isEvent: true, now: now)
        XCTAssertEqual(alerts.count, 1)
        XCTAssertEqual(alerts[0].body, "Standup starts in 1 minute")
    }

    func testPlannedRequestsUsesResolver() {
        var c = Countdown(label: "EOD")
        c.mode = .nextEvent
        c.alertOffsets = [5]
        let now = Date(timeIntervalSince1970: 1_000_000)
        let eventStart = now.addingTimeInterval(1800) // 30 min away, within default 12h
        let reqs = AlertPlanner.plannedRequests(items: [c], nextEventStart: eventStart, nextEventTitle: "Standup", now: now)
        XCTAssertEqual(reqs.count, 1)
        XCTAssertEqual(reqs[0].fireDate, eventStart.addingTimeInterval(-300))
        XCTAssertEqual(reqs[0].title, "Standup")
        XCTAssertEqual(reqs[0].body, "Standup starts in 5 minutes")
        XCTAssertTrue(AlertRequestID.isOurs(reqs[0].id))
    }
}
