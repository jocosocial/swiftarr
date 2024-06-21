import Vapor

/// All of these middleware must be inserted into the middlewaire chain AFTER the auth middleware.

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

struct MinUserAccessLevelMiddleware: AsyncMiddleware {
	var requireAuth: Bool
	var requireAccessLevel: UserAccessLevel

	// Set requireAuth to TRUE to make this middleware act like an auth guard, returning a HTTP 401 if no user was authed.
	// This makes this middleware act like guard middleware.
	// Set a min accessLevel for routes that have one (like admin-only routes)
	init(requireAuth: Bool = true, requireAccessLevel: UserAccessLevel? = nil) {
		self.requireAuth = requireAuth
		self.requireAccessLevel = requireAccessLevel ?? .banned
	}

	func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
		// If someone authed on this request, either via a token or (for some routes) basic auth
		if let user = request.auth.get(UserCacheData.self) {
			// We throw forbidden here because the user authed but they're not allowed access either because 
			// the route is permanently restricted (like a mod-only route) or the server is temporarily restricted.
			if !user.accessLevel.hasAccess(requireAccessLevel) {
				throw Abort(.forbidden, reason: "Access is restricted to \(requireAccessLevel.visibleName()) or higher.")
			}
			if !user.accessLevel.hasAccess(Settings.shared.minAccessLevel) {
				if !Settings.shared.enablePreregistration || request.route?.usedForPreregistration() != true {
				throw Abort(.forbidden, reason: "Access is restricted to \(Settings.shared.minAccessLevel) or higher.")
				}
			}
		}
		else if requireAuth {
			throw Abort(.unauthorized, reason: "User not authenticated.")
		}
		else if Settings.shared.minAccessLevel > .banned, 
				!Settings.shared.enablePreregistration || request.route?.usedForPreregistration() != true {
			throw Abort(.unauthorized, reason: "Server is in maintenance mode; authorization required.")
		}
		return try await next.respond(to: request)
	}
}
