import XCTVapor
@testable import swiftarr

class DateExtensionTests: XCTestCase {

	// MARK: - Date.iso8601ms encoding

	func testDateIso8601ms_IncludesFractionalSeconds() {
		let date = Date(timeIntervalSince1970: 1_710_000_000.123)
		let str = date.iso8601ms
		// The "ms" formatter must include a "." with fractional seconds.
		XCTAssertTrue(str.contains("."), "got \(str)")
		XCTAssertTrue(str.hasSuffix("Z"), "got \(str)")
	}

	// MARK: - String.iso8601ms parsing

	func testStringIso8601ms_ParsesValidString() {
		let parsed = "2024-03-12T15:00:00.000Z".iso8601ms
		XCTAssertNotNil(parsed)
	}

	func testStringIso8601ms_RejectsStringWithoutMilliseconds() {
		// Strict format — without fractional seconds, parser returns nil.
		let parsed = "2024-03-12T15:00:00Z".iso8601ms
		XCTAssertNil(parsed)
	}

	func testStringIso8601ms_RejectsGarbage() {
		XCTAssertNil("not a date".iso8601ms)
	}

	// MARK: - Round-trip

	func testIso8601ms_RoundTrip() {
		let original = Date(timeIntervalSince1970: 1_710_000_000.123)
		let str = original.iso8601ms
		let parsed = str.iso8601ms
		XCTAssertNotNil(parsed)
		// Equality at millisecond precision.
		XCTAssertEqual(parsed!.timeIntervalSince1970, original.timeIntervalSince1970, accuracy: 0.001)
	}
}
