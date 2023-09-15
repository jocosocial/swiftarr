import Vapor

struct SiteRequireVerifiedMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.verified) else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}

struct SiteRequireModeratorMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.moderator) else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}

struct SiteRequireTwitarrTeamMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.twitarrteam) else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}

struct SiteRequireTHOMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.tho) else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}

struct SiteRequireAdminMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.admin) else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}
