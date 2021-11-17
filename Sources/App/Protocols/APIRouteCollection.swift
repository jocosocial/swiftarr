import Vapor
import Crypto
import FluentSQL
import Redis

protocol APIRouteCollection {
	func registerRoutes(_ app: Application) throws
}

extension APIRouteCollection {

	var categoryIDParam: PathComponent { PathComponent(":category_id") }
	var twarrtIDParam: PathComponent { PathComponent(":twarrt_id") }
	var forumIDParam: PathComponent { PathComponent(":forum_id") }
	var postIDParam: PathComponent { PathComponent(":post_id") }
	var fezIDParam: PathComponent { PathComponent(":fez_id") }
	var fezPostIDParam: PathComponent { PathComponent(":fezPost_id") }
	var userIDParam: PathComponent { PathComponent(":user_id") }
	var eventIDParam: PathComponent { PathComponent(":event_id") }
	var reportIDParam: PathComponent { PathComponent(":report_id") }
	var modStateParam: PathComponent { PathComponent(":mod_state") }
	var announcementIDParam: PathComponent { PathComponent(":announcement_id") }
	var barrelIDParam: PathComponent { PathComponent(":barrel_id") }
	var alertwordParam: PathComponent { PathComponent(":alert_word") }
	var mutewordParam: PathComponent { PathComponent(":mute_word") }
	var searchStringParam: PathComponent { PathComponent(":search_string") }
	var dailyThemeIDParam: PathComponent { PathComponent(":daily_theme_id") }
	var accessLevelParam: PathComponent { PathComponent(":access_level") }
	var boardgameIDParam: PathComponent { PathComponent(":boardgame_id") }
	var songIDParam: PathComponent { PathComponent(":karaoke_song+id") }
	 
	/// Adds Flexible Auth to a route. This route can be accessed without a token (while not logged in), but `req.auth.get(User.self)` will still
	/// return a user if one is logged in. Route handlers for these routes should not call `req.auth.require(User.self)`. A route with no auth 
	/// middleware will not auth any user and `.get(User.self)` will always return nil. The Basic and Token auth groups will throw an error if 
	/// no user gets authenticated (specifically:` User.guardMiddleware` throws).
	///
	/// So, use this auth group for routes that can be accessed while not logged in, but which provide more (or different) data when a logged-in user
	/// accesses the route.
	func addFlexAuthGroup(to: RoutesBuilder) -> RoutesBuilder {
		return to.grouped([Token.authenticator()])
	}
	
	/// I'm moving auth over to UserCache, so that you'll auth a UserCacheData struct instead of a User model. Functionally, this means a `UserCacheData`
	/// gets added to `req.auth` instead of a `User`. And, we avoid a SQL call per API call.
	func addFlexCacheAuthGroup(to: RoutesBuilder) -> RoutesBuilder {
		return to.grouped([UserCacheData.TokenAuthenticator()])
	}

	/// For routes that require HTTP Basic Auth. Tokens won't work. Generally, this is only for the login route.
	func addBasicAuthGroup(to: RoutesBuilder) -> RoutesBuilder {
		return to.grouped([User.authenticator(), User.guardMiddleware()])
	}

	/// For routes that require a logged-in user. Applying this auth group to a route will make requests that don't have a valid token fail with a HTTP 401 error.
	func addTokenAuthGroup(to: RoutesBuilder) -> RoutesBuilder {
		return to.grouped([Token.authenticator(), User.guardMiddleware()])
	}
	func addTokenCacheAuthGroup(to: RoutesBuilder) -> RoutesBuilder {
		return to.grouped([UserCacheData.TokenAuthenticator(), UserCacheData.guardMiddleware()])
	}

	/// Transforms a string that might represent a date (either a `Double` or an ISO 8601
	/// representation) into a `Date`, if possible.
	///
	/// - Note: The representation is expected to be either a string literal `Double`, or a
	///   string in UTC `yyyy-MM-dd'T'HH:mm:ssZ` format.
	///
	/// - Parameter string: The string to be transformed.
	/// - Returns: A `Date` if the conversion was successful, otherwise `nil`.
	static func dateFromParameter(string: String) -> Date? {
		var date: Date?
		if let timeInterval = TimeInterval(string) {
			date = Date(timeIntervalSince1970: timeInterval)
		} else {
			if #available(OSX 10.13, *) {
				if let msDate = string.iso8601ms {
					date = msDate
//				if let dateFromISO8601ms = ISO8601DateFormatter().date(from: string) {
//					date = dateFromISO8601ms
				}
			} else {
				let dateFormatter = DateFormatter()
				dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
				dateFormatter.locale = Locale(identifier: "en_US_POSIX")
				dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
				if let dateFromDateFormatter = dateFormatter.date(from: string) {
					date = dateFromDateFormatter
				}
			}
		}
		return date
	}
	
// MARK: Notification Management
	
	// When we detect a twarrt or post with an alertword in it, call this method to find the users that are looking
	// for that alertword and increment each of their hit counts. Differs from addNotifications because the list
	// of users to notify is itself stored in Redis.
	@discardableResult func addAlertwordNotifications(type: NotificationType, minAccess: UserAccessLevel = .quarantined,
			info: String, on req: Request) -> EventLoopFuture<Void> {
		switch type {
		case .alertwordTwarrt(let word):
			return req.redis.smembers(of: "alertwordUsers-\(word)", as: UUID.self).flatMap { userIDOptionals in
				let userIDs = userIDOptionals.compactMap { $0 }
				return addNotifications(users: userIDs, type: type, info: "Your alert word '\(word)", on: req)
			}
		case .alertwordPost(let word):
			return req.redis.smembers(of: "alertwordUsers-\(word)", as: UUID.self).flatMap { userIDOptionals in
				let userIDs = userIDOptionals.compactMap { $0 }
				let validUserIDs = req.userCache.getUsers(userIDs).compactMap { $0.accessLevel >= minAccess ? $0.userID : nil }
				return addNotifications(users: validUserIDs, type: type, info: info, on: req)
			}
		default:
			return req.eventLoop.future()
		}
	}
	
	// When an event happens that could change notification counts for someone (e.g. a user posts a Twarrt with an @mention) 
	// call this method to do the notification bookkeeping.
	// 
	// The users array should be pre-filtered to include only those who can actually see the new content (that is, not
	// blocking or muting it, or not in the group that receives the content).
	//
	// Adding a new notification will also send out an update to all relevant users who are listening on notification sockets. 
	@discardableResult func addNotifications(users: [UUID], type: NotificationType, info: String, on req: Request) -> EventLoopFuture<Void> {
		var hashFutures: [EventLoopFuture<Int>]
		var forwardToSockets = true	
		switch type {
		case .announcement:
			// Force cache of active announcementIDs to get rebuilt
			hashFutures = [req.redis.delete("ActiveAnnouncementIDs")]
		case .nextFollowedEventTime(let date):
			// Force cache of active announcementIDs to get rebuilt
			hashFutures = users.map { userID in
				if let doubleDate = date?.timeIntervalSince1970 {
					return req.redis.hset(type.redisFieldName(), to: doubleDate, in: type.redisKeyName(userID: userID)).transform(to: 0)
				}
				else {
					return req.redis.hdel(type.redisFieldName(), from: type.redisKeyName(userID: userID))
				}
			}
			forwardToSockets = false
		default:
			hashFutures = users.map { userID in
				req.redis.hincrby(1, field: type.redisFieldName(), in: type.redisKeyName(userID: userID))
			}
		}

		if forwardToSockets {
			// Send a message to all involved users with open websockets.
			let socketeers = req.webSocketStore.getSockets(users)
			if socketeers.count > 0 {
				let msgStruct = SocketNotificationData(type, info: info)
				if let jsonData = try? JSONEncoder().encode(msgStruct), let jsonDataStr = String(data: jsonData, encoding: .utf8) {
					socketeers.forEach { userSocket in
						userSocket.socket.send(jsonDataStr)
					}
				}
			}
		}

		hashFutures.append(req.redis.sadd(users, to: "UsersWithNotificationStateChange"))
		return hashFutures.flatten(on: req.eventLoop).transform(to: ())
		
	}
	
	// When a twarrt or post with an alertword in it gets edited/deleted and the alertword is removed,
	// you'll need to call this method to find the users that are looking for that alertword and decreemnt their hit counts.
	// Differs from subtractNotifications because the list of users to notify is itself stored in Redis.	
	@discardableResult func subtractAlertwordNotifications(type: NotificationType, minAccess: UserAccessLevel = .quarantined,
			on req: Request) -> EventLoopFuture<Void> {
		switch type {
		case .alertwordTwarrt(let word):
			return req.redis.smembers(of: "alertwordUsers-\(word)", as: UUID.self).flatMap { userIDOptionals in
				let userIDs = userIDOptionals.compactMap { $0 }
				return subtractNotifications(users: userIDs, type: type, on: req)
			}
		case .alertwordPost(let word):
			return req.redis.smembers(of: "alertwordUsers-\(word)", as: UUID.self).flatMap { userIDOptionals in
				let userIDs = userIDOptionals.compactMap { $0 }
				let validUserIDs = req.userCache.getUsers(userIDs).compactMap { $0.accessLevel >= minAccess ? $0.userID : nil }
				return subtractNotifications(users: validUserIDs, type: type, on: req)
			}
		default:
			return req.eventLoop.future()
		}
	}
	
	// When an event happens that could reduce notification counts for someone (e.g. a user deletes a Twarrt with an @mention) 
	// call this method to do the notification bookkeeping.
	@discardableResult func subtractNotifications(users: [UUID], type: NotificationType, subtractCount: Int = 1, on req: Request) -> EventLoopFuture<Void> {
		var hashFutures: [EventLoopFuture<Int>] = []
		switch type {
		case .announcement:
			// Force cache of active announcementIDs to get rebuilt
			hashFutures.append(req.redis.delete("ActiveAnnouncementIDs"))
		default:
			hashFutures = users.map { userID in
				req.redis.hincrby(0 - subtractCount, field: type.redisFieldName(), in: type.redisKeyName(userID: userID))
			}
		}
		hashFutures.append(req.redis.sadd(users, to: "UsersWithNotificationStateChange"))
		return hashFutures.flatten(on: req.eventLoop).transform(to: ())
	}
	
	// When a user leaves a fez or the fez is deleted, delete the unread count for that fez for all participants; it no longer applies.
	@discardableResult func deleteFezNotifications(userIDs: [UUID], fez: FriendlyFez, on req: Request) throws -> EventLoopFuture<Void> {
		let futures = try userIDs.map { userID in
			try req.redis.hdel(fez.requireID().uuidString, from: NotificationType.redisKeyForFez(fez, userID: userID))
		}
		return futures.flatten(on: req.eventLoop).transform(to: ())
	}
	
	// Call this when a user adds a new alertword to watch for.
	@discardableResult func addAlertwordForUser(_ word: String, userID: UUID, on req: Request) -> EventLoopFuture<Void> {
		req.redis.sadd(userID, to: "alertwordUsers-\(word)").transform(to: ())
	}
	
	// Call this when a user removes one of their alertwords.
	@discardableResult func removeAlertwordForUser(_ word: String, userID: UUID, on req: Request) -> EventLoopFuture<Void> {
		req.redis.srem(userID, from: "alertwordUsers-\(word)").transform(to: ())
	}
	
	// When a user does an action that might clear a notification call this to handle bookkeeping.
	// Actions that could clear notifications: Viewing their @mentions (clears @mention notifications), viewing alert word hits,
	// viewing announcements, reading seamails.
	@discardableResult func markNotificationViewed(userID: UUID, type: NotificationType, on req: Request) -> EventLoopFuture<Void> {
		var hashFuture: EventLoopFuture<Void>
		switch type {
		case .announcement(let id): 
			hashFuture = req.redis.hset(type.redisViewedFieldName(), to: id, in: type.redisKeyName(userID: userID)).transform(to: ())
		case .twarrtMention: fallthrough
		case .forumMention: fallthrough		
		case .alertwordTwarrt: fallthrough
		case .alertwordPost:
			hashFuture = req.redis.hget(type.redisFieldName(), from: type.redisKeyName(userID: userID), as: Int.self).flatMap { hitCount in
				if hitCount == 0 {
					return req.eventLoop.future()
				}
				return req.redis.hset(type.redisViewedFieldName(), to: hitCount, in: type.redisKeyName(userID: userID)).transform(to: ())
			}
		case .fezUnreadMsg: fallthrough
		case .seamailUnreadMsg:
			hashFuture = req.redis.hset(type.redisFieldName(), to: 0, in: type.redisKeyName(userID: userID)).transform(to: ())
		case .nextFollowedEventTime: 
			return req.eventLoop.future()	// Can't be cleared
		}
		return hashFuture.and(req.redis.sadd(userID, to: "UsersWithNotificationStateChange")).transform(to: ())
	}
	
	// Calculates the start time of the earliest future followed event. Caches the value in Redis for quick access.
	func storeNextEventTime(userID: UUID, eventBarrel: Barrel?, on req: Request) -> EventLoopFuture<Date?> {
		let futureBarrel: EventLoopFuture<Barrel?> = eventBarrel != nil ?  req.eventLoop.future(eventBarrel) :
				Barrel.query(on: req.db).filter(\.$ownerID == userID).filter(\.$barrelType == .taggedEvent).first()
		return futureBarrel.flatMap { barrel in
			guard let eventBarrel = barrel else {
				return req.eventLoop.future(nil)
			}
			let cruiseStartDate = Settings.shared.cruiseStartDate
			var filterDate = Date()
			// If the cruise is in the future or more than 10 days in the past, construct a fake date during the cruise week
			let secondsPerDay = 24 * 60 * 60.0
			if cruiseStartDate.timeIntervalSinceNow > 0 ||
				cruiseStartDate.timeIntervalSinceNow < 0 - Double(Settings.shared.cruiseLengthInDays) * secondsPerDay {
				var filterDateComponents = Calendar.autoupdatingCurrent.dateComponents(in: TimeZone(abbreviation: "EST")!, 
						from: cruiseStartDate)
				let currentDateComponents = Calendar.autoupdatingCurrent.dateComponents(in: TimeZone(abbreviation: "EST")!, 
						from: Date())
				filterDateComponents.hour = currentDateComponents.hour
				filterDateComponents.minute = currentDateComponents.minute
				filterDateComponents.second = currentDateComponents.second
				filterDate = Calendar.autoupdatingCurrent.date(from: filterDateComponents) ?? Date()
				if let currentDayOfWeek = currentDateComponents.weekday {
					let daysToAdd = (7 + currentDayOfWeek - Settings.shared.cruiseStartDayOfWeek) % 7 
					if let adjustedDate = Calendar.autoupdatingCurrent.date(byAdding: .day, value: daysToAdd, to: filterDate) {
						filterDate = adjustedDate
					}
				}
			}			
			return Event.query(on: req.db).filter(\.$id ~~ eventBarrel.modelUUIDs)
					.filter(\.$startTime > filterDate)
					.sort(\.$startTime, .ascending)
					.first()
					.map { event in
				addNotifications(users: [userID], type: .nextFollowedEventTime(event?.startTime), info: "", on: req)
				return event?.startTime
			}
		}
	}
}
