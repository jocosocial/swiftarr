import Vapor

/// Adds an `X-Robots-Tag` header to every response, asking search engines, archivers, and AI crawlers not to index or reuse
/// the content. Complements `GET /robots.txt` and the robots `<meta>` tag in trunk.html; well-behaved crawlers honor all three.
/// robots.txt must NOT disallow search engines: a crawler blocked by robots.txt never sees this header, so already-known URLs stay listed.
struct RobotsTagMiddleware: AsyncMiddleware {
	// Keep this list consistent with the robots <meta> tag in Resources/Views/trunk.html.
	static let directives = "noindex, nofollow, noarchive, nosnippet, noai, noimageai"

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		let response = try await next.respond(to: request)
		response.headers.replaceOrAdd(name: "X-Robots-Tag", value: Self.directives)
		return response
	}
}
