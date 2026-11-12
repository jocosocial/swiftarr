@testable import swiftarr
import XCTVapor
import Testing

struct RobotsTests: SwiftarrBaseTest {
	@Test("robots.txt disallows all crawlers without auth")
	func testRobotsTxt() async throws {
		try await withApp { app in
			try await app.test(.GET, "/robots.txt", afterResponse: { res async throws in
				#expect(res.status == .ok)
				#expect(res.headers.contentType == .plainText)
				let body = res.body.string
				#expect(body.contains("User-agent: *\nDisallow: /"))
			})
		}
	}

	@Test("X-Robots-Tag is set on success and error responses")
	func testRobotsTagHeader() async throws {
		try await withApp { app in
			try await app.test(.GET, "/robots.txt", afterResponse: { res async throws in
				#expect(res.headers.first(name: "X-Robots-Tag") == RobotsTagMiddleware.directives)
			})
			try await app.test(.GET, "/api/v3/nonexistent", afterResponse: { res async throws in
				#expect(res.status == .notFound)
				#expect(res.headers.first(name: "X-Robots-Tag") == RobotsTagMiddleware.directives)
			})
		}
	}
}
