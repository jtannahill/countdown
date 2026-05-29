import XCTest
@testable import Countdown

final class LocationValidationTests: XCTestCase {
    func testValidCoordinatesAccepted() {
        XCTAssertTrue(LocationProvider.isValid(latitude: 0, longitude: 0))
        XCTAssertTrue(LocationProvider.isValid(latitude: -90, longitude: 180))
        XCTAssertTrue(LocationProvider.isValid(latitude: 51.5, longitude: -0.12))
    }
    func testOutOfRangeCoordinatesRejected() {
        XCTAssertFalse(LocationProvider.isValid(latitude: 91, longitude: 0))
        XCTAssertFalse(LocationProvider.isValid(latitude: 0, longitude: 181))
        XCTAssertFalse(LocationProvider.isValid(latitude: -90.1, longitude: 0))
    }
}
