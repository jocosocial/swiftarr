import Vapor

struct RequireVerifiedMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(User.self), user.accessLevel.hasAccess(.verified) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct RequireModeratorMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(User.self), user.accessLevel.hasAccess(.moderator) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct RequireTHOMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(User.self), user.accessLevel.hasAccess(.tho) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct RequireAdminMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard let user = request.auth.get(User.self), user.accessLevel.hasAccess(.admin) else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}
