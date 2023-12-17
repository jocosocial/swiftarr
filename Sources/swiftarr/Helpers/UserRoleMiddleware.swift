import Vapor

struct RequireVerifiedMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.verified) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.verified) {
			isAuthed = true
		}
		guard isAuthed else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}

struct RequireModeratorMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.moderator) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.moderator) {
			isAuthed = true
		}
		guard isAuthed else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}

struct RequireTwitarrTeamMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.twitarrteam) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.twitarrteam) {
			isAuthed = true
		}
		guard isAuthed else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}

struct RequireTHOMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.tho) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.tho) {
			isAuthed = true
		}
		guard isAuthed else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}

struct RequireAdminMiddleware: AsyncMiddleware {

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.admin) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.admin) {
			isAuthed = true
		}
		guard isAuthed else {
			throw Abort(.unauthorized)
		}
		return try await next.respond(to: request)
	}
}
