import Vapor

struct NotificationsMiddleware: Middleware, SiteControllerUtils {
	func registerRoutes(_ app: Application) throws {}
	
	func respond(to req: Request, chainingTo next: Responder) -> EventLoopFuture<Response> {
		guard req.method == .GET else {
			return next.respond(to: req)
		}
		if let lastCheckTimeStr = req.session.data["lastNotificationCheckTime"], 
				let lastCheckInterval = Double(lastCheckTimeStr),
				Date(timeIntervalSince1970: lastCheckInterval).timeIntervalSinceNow > -60.0 {
			return next.respond(to: req)
		}
		if let _ = req.auth.get(User.self) {
			req.session.data["lastNotificationCheckTime"] = String(Date().timeIntervalSince1970)
			return apiQuery(req, endpoint: "/alerts/usercounts").throwingFlatMap { response in
				if response.status == .ok {
					// I dislike decoding the response JSON just to re-encode it into a string for session storage.
					// response.body?.getString(at: 0, length: response.body!.capacity)
					let alertCounts = try response.content.decode(UserNotificationCountData.self)
					let alertCountsJSON = try JSONEncoder().encode(alertCounts)
					let alertCountStr = String(data: alertCountsJSON, encoding: .utf8)
					req.session.data["alertCounts"] = alertCountStr
				}
				return next.respond(to: req)
			}
		}
		else {
			// TODO: get global alerts struct, add to session
			return next.respond(to: req)
		}
	}
}
