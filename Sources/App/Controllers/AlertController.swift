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
		let alertRoutes = routes.grouped("api", "v3", "alerts")

		// instantiate authentication middleware
		let tokenAuthMiddleware = Token.authenticator()
		let guardAuthMiddleware = User.guardMiddleware()

		// set protected route groups
		let tokenAuthGroup = alertRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])

		// open access endpoints
		alertRoutes.get("notifications", use: globalNotificationHandler)

		// endpoints available only when logged in
		tokenAuthGroup.get("user", "notifications", use: userNotificationHandler)
		tokenAuthGroup.get("usercounts", use: userCountNotificationHandler)
	}
	
	func globalNotificationHandler(_ req: Request) throws -> EventLoopFuture<GlobalNotificationData> {
		
		throw "wut"
	}

	func userNotificationHandler(_ req: Request) throws -> EventLoopFuture<UserNotificationData> {
		
		throw "wut"
	}
	
	func userCountNotificationHandler(_ req: Request) throws -> EventLoopFuture<UserNotificationCountData> {
        let user = try req.auth.require(User.self)
		return user.$joined_fezzes.$pivots.query(on: req.db).with(\.$fez).all().map { pivots in
			// Count the number of fezzes with unread messages
			let newFezCount = pivots.reduce(0) { result, fezParticipant in
				let unreadCount = fezParticipant.fez.postCount - fezParticipant.readCount - fezParticipant.hiddenCount
				return unreadCount > 0 ? result + 1 : result
			}
			let countData = UserNotificationCountData(user: user, newFezCount: newFezCount, highestAnnouncementID: 0)
			return countData
		}
	}
	
	// createAnnouncement
	// editAnnouncement
	// deleteAnnouncement
	// markAnnouncementsRead
	// markTwarrtMentionsViewed
	// get allAnnouncements
	
	// How to do Mention Notifications!
	// When a user posts, process the post text. Find @mentions, increment that user's mentionCount in their User model.
	// When a user views their mentions (calls mentionsHandler), set mentionViewedCount to mentionCount.
	// When a user gets notification info, new mentions are mentionCount - mentionViewedCount. 
	// the actual # of mentions could drift if users edit posts to add/remove @mentions -- but we could adjust on edit to compensate.
	// Even if a (viewed) mention gets edited, the New count will be correct. 
}

// move to controllerStructs

struct GlobalNotificationData: Content {
	/// Always UTC with milliseconds, like "2020-03-07T12:00:00.001Z"
	let serverTime: Date
	/// ISO 8601 time zone offset, like "-05:00"
	let serverTimeOffset: String
	/// Human-readable time zone name, like "EDT"
	let serverTimeZone: String
	/// All active announcements 
//	let activeAnnouncements: [AnnouncementData]
	let latestAnnouncementIndex: Int
}

struct UserNotificationData: Content {
	/// Include all the global notification data
	var globalNotifications: GlobalNotificationData
	/// Any announcements whose `id` is greater than this number are new announcements that haven't been seen by this user.
	var highestReadAnnouncementID: Int
	/// Twarrts that @mention the active user.
	let twarrtMentions: [UUID]
	/// Forum posts that @mention the active user
	let forumPostMentions: [Int]
	/// Count of unseen Fez messages. --or perhaps this should be # of Fezzes with new messages?
	let newFezMessageCount: Int
	/// I see where alert words can be set, but nowhere do I see alert words implemented to actually alert a user.
//	let alertWordNotifications: Int
}

struct UserNotificationCountData: Content {
	//
	var highestAnnouncementID: Int
	/// Any announcements whose `id` is greater than this number are new announcements that haven't been seen by this user.
	var highestReadAnnouncementID: Int
	
	var twarrtMentionCount: Int
	var readTwarrtMentionCount: Int
	
	var forumMentionCount: Int
	var readForumMentionCount: Int
	
	/// Count of unseen Fez messages. --or perhaps this should be # of Fezzes with new messages?
	var newFezMessageCount: Int
	
	/// I see where alert words can be set, but nowhere do I see alert words implemented to actually alert a user.
//	let alertWordNotificationCount: Int
}

extension UserNotificationCountData	{
	init(user: User, newFezCount: Int, highestAnnouncementID: Int) {
		self.highestAnnouncementID = highestAnnouncementID
		self.highestReadAnnouncementID = user.lastReadAnnouncement
		self.twarrtMentionCount = user.twarrtMentions
		self.readTwarrtMentionCount = user.twarrtMentionsViewed
		self.forumMentionCount = user.forumMentions
		self.readForumMentionCount = user.forumMentionsViewed
		self.newFezMessageCount = newFezCount
	}
}

struct AnnouncementData: Content {
	let id: Int
	let author: UUID
	let text: String
	let updatedAt: Date
	let displayUntil: Date
}
