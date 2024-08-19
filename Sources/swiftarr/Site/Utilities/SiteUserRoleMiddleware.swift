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

struct SiteMinUserAccessLevelMiddleware: AsyncMiddleware {
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
			if requireAuth, !user.accessLevel.hasAccess(Settings.shared.minAccessLevel) {
				if Settings.shared.enablePreregistration {
					if request.route?.usedForPreregistration() != true {
						throw Abort(.forbidden, reason: "Thanks for creating an account! Parts of Twitarr aren't available until we're on the ship as we're currently busy \(pirateErrorExplanation()).")
					}
				}
				else {
					throw Abort(.forbidden, reason: "Twitarr is down for maintenance; we're busy \(pirateErrorExplanation()).")
				}
			}
		}
		else if requireAuth {
			throw Abort(.unauthorized, reason: "User not authenticated.")
		}
		// TODO: We could add an `else if Settings.shared.minAccessLevel > .banned` clause here, making flex routes
		// fail when not logged in and the server is in a restricted state. Or, we might think about de-authing users
		// if they don't meet the min access levels, above (and it's a flex route).
		return try await next.respond(to: request)
	}
	
	func pirateErrorExplanation() -> String {
		return [
				"swabbing the decks",
				"cleaning out the bilge",
				"weighing anchor",
				"unfurling the sails",
				"scraping off the barnacles",
				"heaving down",
				"trimming the mainsail",
				"rigging the mizzenmast",
				"clewing up the topsail",
				"flaking the dock lines",
				"tacking starboard",
				"dropping the kedge",
				"stocking the lazarette",
				"sailing by the lee",
				"splicing the mainbrace",
				"stepping the foremast",
				"swinging the lamp",
				
		].randomElement() ?? "splicing the mainbrace"
	}
}
