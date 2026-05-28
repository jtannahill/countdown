import XCTest
@testable import Countdown

final class ModelCodableTests: XCTestCase {
    // An old persisted blob with none of the new fields must decode with defaults.
    func testLegacyBlobDecodesWithDefaults() throws {
        let legacy = """
        [{"id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","label":"EOD","mode":"daily",
          "resetHour":9,"resetMinute":0,"targetHour":17,"targetMinute":30,
          "targetTimestamp":0,"color":"orange"}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([Countdown].self, from: legacy)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].alertOffsets, [])
        XCTAssertEqual(items[0].alertAtZero, false)
        XCTAssertEqual(items[0].eventLookaheadHours, 12)
        XCTAssertEqual(items[0].mode, .daily)
    }

    func testRoundTripPreservesNewFields() throws {
        var c = Countdown(label: "EOD")
        c.alertOffsets = [10, 5]
        c.alertAtZero = true
        c.eventLookaheadHours = 6
        c.mode = .nextEvent
        let data = try JSONEncoder().encode([c])
        let back = try JSONDecoder().decode([Countdown].self, from: data)
        XCTAssertEqual(back[0].alertOffsets, [10, 5])
        XCTAssertEqual(back[0].alertAtZero, true)
        XCTAssertEqual(back[0].eventLookaheadHours, 6)
        XCTAssertEqual(back[0].mode, .nextEvent)
    }

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
}
