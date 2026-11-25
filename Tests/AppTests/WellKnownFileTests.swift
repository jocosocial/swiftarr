import XCTVapor
@testable import swiftarr

class WellKnownFileTests: XCTestCase, SwiftarrBaseTest {

	func testAppleAppSiteAssociationIsServedAsJSON() async throws {
		try await assertServedAsJSON("/.well-known/apple-app-site-association")
	}

	func testAssetLinksIsServedAsJSON() async throws {
		try await assertServedAsJSON("/.well-known/assetlinks.json")
	}

	private func assertServedAsJSON(_ path: String) async throws {
		try await withApp { app in
			try await app.test(.GET, path) { res async throws in
				XCTAssertEqual(res.status, .ok)
				XCTAssertEqual(res.headers.contentType, .json)
				XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(buffer: res.body)))
			}
		}
	}
}
