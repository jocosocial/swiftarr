@testable import swiftarr
import XCTVapor
import Testing

struct RobotsTests: SwiftarrBaseTest {
	@Test("robots.txt lets search engines crawl (to see noindex) but blocks AI crawlers")
	func testRobotsTxt() async throws {
		try await withApp { app in
			try await app.test(.GET, "/robots.txt", afterResponse: { res async throws in
				#expect(res.status == .ok)
				#expect(res.headers.contentType == .plainText)
				let body = res.body.string
				#expect(body.contains("User-agent: *\nAllow: /"))
				#expect(!body.contains("User-agent: *\nDisallow: /"))
				#expect(body.contains("User-agent: GPTBot\n"))
				#expect(body.contains("User-agent: ia_archiver\nDisallow: /\n"))
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
