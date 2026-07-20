import XCTVapor
@testable import swiftarr

class PaginationTests: XCTestCase {

	func testDefaults() {
		let pagination = Pagination(start: nil, limit: nil, maxPageSize: 200)
		XCTAssertEqual(pagination.start, 0)
		XCTAssertEqual(pagination.limit, 50)
		XCTAssertEqual(pagination.range, 0..<50)
	}

	func testStartClampsNegativeValues() {
		XCTAssertEqual(Pagination(start: -1, limit: nil, maxPageSize: 200).start, 0)
		XCTAssertEqual(Pagination(start: nil, limit: nil, defaultStart: -5, maxPageSize: 200).start, 0)
	}

	func testPreservesValuesAndBuildsRange() {
		let pagination = Pagination(start: 12, limit: 25, maxPageSize: 200)
		XCTAssertEqual(pagination.start, 12)
		XCTAssertEqual(pagination.limit, 25)
		XCTAssertEqual(pagination.range, 12..<37)
	}

	func testLimitClampsToNonzeroBounds() {
		XCTAssertEqual(Pagination(start: nil, limit: 0, maxPageSize: 200).limit, 1)
		XCTAssertEqual(Pagination(start: nil, limit: -10, maxPageSize: 200).limit, 1)
		XCTAssertEqual(Pagination(start: nil, limit: nil, defaultLimit: 0, maxPageSize: 200).limit, 1)
		XCTAssertEqual(Pagination(start: nil, limit: 201, maxPageSize: 200).limit, 200)
		XCTAssertEqual(Pagination(start: nil, limit: 10, maxPageSize: 0).limit, 1)
	}

	func testDecodesRequestQuery() {
		let app = Application(.testing)
		defer { app.shutdown() }
		let req = Request(
			application: app,
			method: .GET,
			url: URI(string: "/?start=12&limit=201"),
			on: app.eventLoopGroup.next()
		)
		let pagination = Pagination(on: req, defaultLimit: 30, maxPageSize: 200)
		XCTAssertEqual(pagination.start, 12)
		XCTAssertEqual(pagination.limit, 200)
		XCTAssertEqual(pagination.range, 12..<212)
	}
}
