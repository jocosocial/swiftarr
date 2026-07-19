import XCTVapor
@testable import swiftarr

class PaginationTests: XCTestCase {

	func testStartDefaultsToZero() {
		XCTAssertEqual(Pagination.start(nil), 0)
	}

	func testStartClampsNegativeValues() {
		XCTAssertEqual(Pagination.start(-1), 0)
		XCTAssertEqual(Pagination.start(nil, default: -5), 0)
	}

	func testStartPreservesPositiveValues() {
		XCTAssertEqual(Pagination.start(12), 12)
	}

	func testLimitDefaultsToFifty() {
		XCTAssertEqual(Pagination.limit(nil, maximum: 200), 50)
	}

	func testLimitClampsToNonzeroLowerBound() {
		XCTAssertEqual(Pagination.limit(0, maximum: 200), 1)
		XCTAssertEqual(Pagination.limit(-10, maximum: 200), 1)
		XCTAssertEqual(Pagination.limit(nil, default: 0, maximum: 200), 1)
	}

	func testLimitClampsToConfiguredMaximum() {
		XCTAssertEqual(Pagination.limit(201, maximum: 200), 200)
	}

	func testLimitStaysNonzeroWhenMaximumIsMisconfigured() {
		XCTAssertEqual(Pagination.limit(10, maximum: 0), 1)
	}

	func testLimitPreservesInRangeValues() {
		XCTAssertEqual(Pagination.limit(25, maximum: 200), 25)
	}
}
