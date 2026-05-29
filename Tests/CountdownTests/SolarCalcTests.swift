import XCTest
@testable import Countdown

final class SolarCalcTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c
    }
    private func utcDate(_ y: Int, _ m: Int, _ d: Int) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d))!
    }
    private func minutesUTC(_ date: Date) -> Int {
        utc.component(.hour, from: date) * 60 + utc.component(.minute, from: date)
    }
    private let utcTZ = TimeZone(identifier: "UTC")!

    // London (51.4769N, 0E), summer solstice 2024 — sunset ~20:21 UTC (21:21 BST).
    func testLondonSummerSolsticeSunset() {
        let s = SolarCalc.sunset(on: utcDate(2024, 6, 21), latitude: 51.4769, longitude: 0, timeZone: utcTZ)!
        XCTAssertGreaterThanOrEqual(minutesUTC(s), 20 * 60)
        XCTAssertLessThanOrEqual(minutesUTC(s), 20 * 60 + 40)
    }

    // London winter solstice 2024 — sunset ~15:53 UTC (GMT).
    func testLondonWinterSolsticeSunset() {
        let s = SolarCalc.sunset(on: utcDate(2024, 12, 21), latitude: 51.4769, longitude: 0, timeZone: utcTZ)!
        XCTAssertGreaterThanOrEqual(minutesUTC(s), 15 * 60 + 40)
        XCTAssertLessThanOrEqual(minutesUTC(s), 16 * 60 + 5)
    }

    // High Arctic (Svalbard ~78N) at summer solstice — midnight sun, no sunset.
    func testPolarNoSunsetIsNil() {
        XCTAssertNil(SolarCalc.sunset(on: utcDate(2024, 6, 21), latitude: 78, longitude: 15, timeZone: utcTZ))
    }

    func testNextSunsetTodayThenTomorrow() {
        let day = utcDate(2024, 6, 21)
        let todays = SolarCalc.sunset(on: day, latitude: 51.4769, longitude: 0, timeZone: utcTZ)!
        XCTAssertEqual(
            SolarCalc.nextSunset(after: todays.addingTimeInterval(-3600), latitude: 51.4769, longitude: 0, timeZone: utcTZ),
            todays)
        let next = SolarCalc.nextSunset(after: todays.addingTimeInterval(3600), latitude: 51.4769, longitude: 0, timeZone: utcTZ)!
        XCTAssertGreaterThan(next, todays.addingTimeInterval(3600))
        XCTAssertGreaterThan(next, todays)
    }
}
