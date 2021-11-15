import Vapor

struct RequireVerifiedMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.verified) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.verified) {
			isAuthed = true
		}
		guard isAuthed else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct RequireModeratorMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.moderator) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.moderator) {
			isAuthed = true
		}
		guard isAuthed else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct RequireTHOMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.tho) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.tho) {
			isAuthed = true
		}
		guard isAuthed else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}

struct RequireAdminMiddleware: Middleware {

	func respond(to request: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		var isAuthed = false
		if let user = request.auth.get(User.self), user.accessLevel.hasAccess(.admin) {
			isAuthed = true
		}
		if let user = request.auth.get(UserCacheData.self), user.accessLevel.hasAccess(.admin) {
			isAuthed = true
		}
		guard isAuthed else {
			return request.eventLoop.future(error: Abort(.unauthorized))
		}
		return next.respond(to: request)
	}
}
