import Vapor

struct SiteRequireVerifiedMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(User.self), user.accessLevel.hasAccess(.verified) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct SiteRequireModeratorMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.moderator) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct SiteRequireTwitarrTeamMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.twitarrteam) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct SiteRequireTHOMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.tho) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct SiteRequireAdminMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.admin) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}
