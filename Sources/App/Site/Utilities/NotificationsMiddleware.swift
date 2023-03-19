import Vapor

/// NotificationsMiddleware gets attached to Site routes, and periodically calls an API notification endpoint to get user notifications.
/// The user notificaiton counts are then attached ot the user's Session.
///
/// This setup is not ideal as a user with multiple Sessions on different devices may see different notificaitons at different times.
///
/// Currently this code breaks the UI/API layer separation somewhat by looking at the authenticated User. If we do need to build separate UI and API
/// servers, we can either:
/// 	* Stop inspecting the `updatedAt `property; notificaitons will be sligihtly less realtime.
///		* Add a webSocket betwen the UI and API, pass usernames that have new notifications as they happen.
///		* Use Redis pub/sub
///		* Really, the communication is one-way -- perhaps build a server endpoint in the UI code and the API layer acts as a client to call it?
/// Via any method, Vapor Sessions aren't set up for finding sessions by user, or accessing any other Session at all, really.
struct NotificationsMiddleware: AsyncMiddleware, SiteControllerUtils {
	func registerRoutes(_ app: Application) throws {}

	func respond(to req: Request, chainingTo next: AsyncResponder) async throws -> Response {
		guard req.method == .GET, let user = req.auth.get(UserCacheData.self) else {
			return try await next.respond(to: req)
		}
		let hasChanges = try await req.redis.testAndClearStateChange(user.userID)
		var isStale = false
		if !hasChanges {
			if let lastCheckTimeStr = req.session.data["lastNotificationCheckTime"],
				let lastCheckInterval = Double(lastCheckTimeStr)
			{
				let lastCheckDate = Date(timeIntervalSince1970: lastCheckInterval)
				if lastCheckDate.timeIntervalSinceNow > -60.0 {
					return try await next.respond(to: req)
				}
			}
			isStale = true
		}
		guard hasChanges || isStale else {
			return try await next.respond(to: req)
		}
		req.session.data["lastNotificationCheckTime"] = String(Date().timeIntervalSince1970)
		let response = try await apiQuery(req, endpoint: "/notification/user", passThroughQuery: false)
		if response.status == .ok {
			// I dislike decoding the response JSON just to re-encode it into a string for session storage.
			// response.body?.getString(at: 0, length: response.body!.capacity)
			let alertCounts = try response.content.decode(UserNotificationData.self)
			let alertCountsJSON = try JSONEncoder().encode(alertCounts)
			let alertCountStr = String(data: alertCountsJSON, encoding: .utf8)
			req.session.data["alertCounts"] = alertCountStr
		}
		return try await next.respond(to: req)
	}
}
