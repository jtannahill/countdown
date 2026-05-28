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
