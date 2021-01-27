import Vapor
import Crypto
import FluentSQL

// rcf Contents of this file are still being baked.
//
// What I want to try to do is make a single endpoint that returns server time, announcements,
// and user notifications, ideally with very low overhead. Perhaps we could just return "highest 
// announcement index #", and store notification numbers in UserCache? 
// That is, we'd store in UserCache that a user had 15 total @mentions, and clients could calc the # unseen.

/// The collection of alert endpoints, with routes for:
/// 	- getting server time,,
///		- getting public address-style announcements,,
///		- getting notifications on alertwords,
///		- getting notificaitons on incoming Fez messages.
struct AlertController: RouteCollection {
 
    /// Required. Registers routes to the incoming router.
    func boot(routes: RoutesBuilder) throws {
        
        // convenience route group for all /api/v3/auth endpoints
        let alertRoutes = routes.grouped("api", "v3", "alert")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthMiddleware = Token.authenticator()
        
        // set protected route groups
 //		let basicAuthGroup = alertRoutes.grouped([basicAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = alertRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
		// open access endpoints
//   	alertRoutes.get("time", use: timeHandler)

        // endpoints available only when logged in
        tokenAuthGroup.get("notifications", use: notificationHandler)
	}
	
	func notificationHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		
		return req.eventLoop.future(.ok)
	}
}

// move to controllerStructs
struct NotificationData: Content {
	/// Always UTC with milliseconds, like "2020-03-07T12:00:00.001Z"
	let serverTime: Date
	/// ISO 8601 time zone offset, like "-05:00"
	let serverTimeOffset: String
	/// Human-readable time zone name, like "EDT"
	let serverTimeZone: String
	/// All active announcements 
	let activeAnnouncements: [Announcement]
	/// Twarrts that @mention the active user.
	let twarrtMentions: [UUID]
	/// Count of unseen Fez messages. --or perhaps this should be # of Fezzes with new messages?
	let newFezMessageCount: Int
	/// I see where alert words can be set, but nowhere do I see alert words implemented to actually alert a user.
//	let alertWordNotifications: Int
}

struct Announcement: Content {
	let id: Int
	let author: UUID
	let text: String
	let endTime: Date
}
