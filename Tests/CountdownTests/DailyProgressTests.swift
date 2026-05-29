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
