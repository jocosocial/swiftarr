import Fluent
import Testing
import XCTVapor
@testable import swiftarr

// MARK: - Pure tests (no DB)

class ClientAppValidationTests: XCTestCase {

	private let decoder = ValidatingJSONDecoder()

	private func validationErrors(_ json: String) throws -> [String] {
		let result = try decoder.validate(ClientAppUploadData.self, from: json.data(using: .utf8)!)
		return result?.validationFailures.map { $0.errorString } ?? []
	}

	func testValid_PassesValidation() throws {
		let json = #"{"name":"App","description":"d","developer":"dev","links":[{"platform":"ios","url":"https://x"},{"platform":"android","url":"https://y"}]}"#
		XCTAssertEqual(try validationErrors(json), [])
	}

	func testNoLinks_Fails() throws {
		let json = #"{"name":"App","description":"d","developer":"dev","links":[]}"#
		XCTAssertTrue(try validationErrors(json).contains("At least one link is required"))
	}

	func testDuplicatePlatform_Fails() throws {
		let json = #"{"name":"App","description":"d","developer":"dev","links":[{"platform":"ios","url":"a"},{"platform":"ios","url":"b"}]}"#
		XCTAssertTrue(try validationErrors(json).contains("Each platform may only have one link"))
	}

	func testEmptyURL_Fails() throws {
		let json = #"{"name":"App","description":"d","developer":"dev","links":[{"platform":"web","url":" "}]}"#
		XCTAssertTrue(try validationErrors(json).contains("Link URLs cannot be empty"))
	}

	func testEmptyName_Fails() throws {
		let json = #"{"name":" ","description":"d","developer":"dev","links":[{"platform":"web","url":"/"}]}"#
		XCTAssertTrue(try validationErrors(json).contains("Name cannot be empty"))
	}
}

class ClientAppPlatformTests: XCTestCase {
	func testAllAndAbsentMeanNoFilter() throws {
		XCTAssertNil(try ClientAppPlatform.fromAPIString(nil))
		XCTAssertNil(try ClientAppPlatform.fromAPIString(""))
		XCTAssertNil(try ClientAppPlatform.fromAPIString("all"))
		XCTAssertNil(try ClientAppPlatform.fromAPIString("ALL"))
	}

	func testKnownPlatforms() throws {
		XCTAssertEqual(try ClientAppPlatform.fromAPIString("iOS"), .ios)
		XCTAssertEqual(try ClientAppPlatform.fromAPIString("other"), .other)
	}

	func testUnknownPlatformThrows() {
		XCTAssertThrowsError(try ClientAppPlatform.fromAPIString("windows"))
	}
}

// MARK: - Controller tests (live Postgres/Redis, like the other controller tests)

struct ClientAppControllerTests: SwiftarrBaseTest {

	@Test("Open client list has seeds and filters")
	func openListHasSeedsAndFilters() async throws {
		try await withApp { app in
			try await app.test(.GET, "/api/v3/admin/clients") { res async throws in
				XCTAssertEqual(res.status, .ok)
				let all = try res.content.decode([ClientAppData].self)
				let names = all.map { $0.name }
				XCTAssertTrue(names.contains("Tricordarr"))
				XCTAssertTrue(names.contains("The Kraken"))
				XCTAssertTrue(names.contains("Twitarr Web UI"))
				let tric = try XCTUnwrap(all.first { $0.name == "Tricordarr" })
				XCTAssertEqual(Set(tric.platforms), [.ios, .android])
				XCTAssertEqual(tric.swiftarrClient, .tricordarr)
			}
			try await app.test(.GET, "/api/v3/admin/clients?platform=all") { res async throws in
				XCTAssertEqual(res.status, .ok)
				XCTAssertGreaterThanOrEqual(try res.content.decode([ClientAppData].self).count, 3)
			}
			try await app.test(.GET, "/api/v3/admin/clients?platform=web") { res async throws in
				let web = try res.content.decode([ClientAppData].self)
				XCTAssertTrue(web.allSatisfy { $0.platforms.contains(.web) })
				XCTAssertTrue(web.contains { $0.name == "Twitarr Web UI" })
			}
			try await app.test(.GET, "/api/v3/admin/clients?platform=bogus") { res async throws in
				XCTAssertEqual(res.status, .badRequest)
			}
		}
	}

	@Test("Creating a client app requires auth")
	func createRequiresAuth() async throws {
		try await withApp { app in
			try await app.test(.POST, "/api/v3/admin/clients/create") { res async throws in
				XCTAssertEqual(res.status, .unauthorized)
			}
		}
	}
}
