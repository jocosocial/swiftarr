import XCTVapor
@testable import swiftarr

// Tests for the Quartermaster Phase 1 schema foundation.
//
// The DB-touching tests (table existence) rely on SwiftarrBaseTest which runs autoMigrate()
// against the test Postgres instance (port 5433). The pure-Swift tests (enum round-trips,
// feature flag) don't need a live DB and are plain XCTestCase functions.
class QuartermasterSchemaTests: XCTestCase, SwiftarrBaseTest {

	// MARK: - Schema / boot

	/// Verifies that the new migrations apply cleanly: if the app boots and autoMigrate()
	/// succeeds inside withApp, the quartermaster_item table exists.
	///
	/// The test DB is shared across the whole test run (not reset per-test), so this can't assert
	/// the table is empty -- it only asserts the table is queryable, which is proof enough that the
	/// migration created it (a query against a missing table throws before returning).
	func testSchema_TablesExistAfterMigration() async throws {
		try await withApp { app in
			let count = try await QuartermasterItem.query(on: app.db).count()
			XCTAssertGreaterThanOrEqual(count, 0, "Expected quartermaster_item table to exist and be queryable after migration")
		}
	}

	/// Verifies the edit table also exists. See `testSchema_TablesExistAfterMigration` for why this
	/// doesn't assert emptiness.
	func testSchema_EditTableExistsAfterMigration() async throws {
		try await withApp { app in
			let count = try await QuartermasterItemEdit.query(on: app.db).count()
			XCTAssertGreaterThanOrEqual(count, 0, "Expected quartermaster_item_edit table to exist and be queryable after migration")
		}
	}

	// MARK: - Feature flag

	func testFeatureFlag_RawValueDecodes() {
		XCTAssertEqual(SwiftarrFeature(rawValue: "quartermaster"), .quartermaster)
	}

	func testFeatureFlag_PresentInAllCases() {
		XCTAssertTrue(SwiftarrFeature.allCases.contains(.quartermaster),
			"quartermaster must appear in CaseIterable so admin UI can enable/disable it")
	}

	// MARK: - ReportType round-trip

	func testReportType_QuartermasterItemRoundTrips() throws {
		let encoder = JSONEncoder()
		let decoder = JSONDecoder()
		let data = try encoder.encode(ReportType.quartermasterItem)
		let decoded = try decoder.decode(ReportType.self, from: data)
		XCTAssertEqual(decoded, .quartermasterItem)
	}

	func testReportType_QuartermasterItemRawValue() {
		XCTAssertEqual(ReportType.quartermasterItem.rawValue, "quartermasterItem")
	}

	// MARK: - QuartermasterCategory

	func testCategory_HaveFromAPIString() throws {
		XCTAssertEqual(try QuartermasterCategory.fromAPIString("have"), .have)
	}

	func testCategory_NeedFromAPIString() throws {
		XCTAssertEqual(try QuartermasterCategory.fromAPIString("need"), .need)
	}

	func testCategory_CaseInsensitive() throws {
		XCTAssertEqual(try QuartermasterCategory.fromAPIString("HAVE"), .have)
		XCTAssertEqual(try QuartermasterCategory.fromAPIString("Need"), .need)
	}

	func testCategory_UnknownThrows() {
		XCTAssertThrowsError(try QuartermasterCategory.fromAPIString("want")) { error in
			guard let abortError = error as? Abort else {
				XCTFail("Expected Abort error, got \(type(of: error))")
				return
			}
			XCTAssertEqual(abortError.status, .badRequest)
		}
	}

	func testCategory_Labels() {
		XCTAssertEqual(QuartermasterCategory.have.label, "Have")
		XCTAssertEqual(QuartermasterCategory.need.label, "Need")
	}
}
