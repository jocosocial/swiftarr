import Vapor
import Crypto
import FluentSQL
import Redis

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
struct AlertController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
        
		// convenience route group for all /api/v3/notification endpoints
		let alertRoutes = app.grouped("api", "v3", "notification")
		alertRoutes.get("hashtags", searchStringParam, use: getHashtagsHandler)

		// Flexible access endpoints -- login not required, although calls may act differently if logged in
		let flexAuthGroup = addFlexCacheAuthGroup(to: alertRoutes)
		flexAuthGroup.get("global", use: globalNotificationHandler)
		flexAuthGroup.get("user", use: globalNotificationHandler)
		flexAuthGroup.get("announcements", use: getAnnouncements)
		flexAuthGroup.get("dailythemes", use: getDailyThemes)

		// endpoints available only when logged in
		let tokenAuthGroup = addTokenCacheAuthGroup(to: alertRoutes)
		tokenAuthGroup.webSocket("socket", onUpgrade: createNotificationSocket) // shouldUpgrade: (Request) -> Headers
		
		// endpoints available only when logged in as THO or above
		let thoAuthGroup = addTokenCacheAuthGroup(to: alertRoutes).grouped(RequireTHOMiddleware())
		thoAuthGroup.get("announcement", announcementIDParam, use: getSingleAnnouncement)
		thoAuthGroup.post("announcement", "create", use: createAnnouncement)
		thoAuthGroup.post("announcement", announcementIDParam, "edit", use: editAnnouncement)
		thoAuthGroup.post("announcement", announcementIDParam, "delete", use: deleteAnnouncement)
		thoAuthGroup.delete("announcement", announcementIDParam, use: deleteAnnouncement)

	}
	
	// MARK: - Hashtags
	
	func getHashtagsHandler(_ req: Request) throws -> EventLoopFuture<[String]> {
		guard var paramVal = req.parameters.get(searchStringParam.paramString), paramVal.count >= 1 else {
            throw Abort(.badRequest, reason: "Request parameter \(searchStringParam.paramString) is missing.")
        }
        if paramVal.hasPrefix("#") {
        	paramVal = String(paramVal.dropFirst())
        }
		guard paramVal.count >= 1, paramVal.count < 50, paramVal.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            throw Abort(.badRequest, reason: "Request parameter \(searchStringParam.paramString) is malformed.")
		}
		return req.redis.zrangebylex(from: "hashtags", withValuesBetween: (min: .inclusive(paramVal), max: .inclusive("\(paramVal)\u{FF}")), 
				limitBy: (offset: 0, count: 10)).map { respvalues in
			let strings = respvalues.map { $0.description }
			return strings
		}
	}



	// MARK: - Notifications
		
    /// `GET /api/v3/notification/global`
    /// `GET /api/v3/notification/user`
    ///
    /// Retrieve info on the number of each type of notification supported by Swiftarr. 
	/// 
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: <doc:UserNotificationData>
	func globalNotificationHandler(_ req: Request) throws -> EventLoopFuture<UserNotificationData> {
        guard let user = req.auth.get(UserCacheData.self) else {
        	return getActiveAnnouncementIDs(on: req).map { activeAnnouncementIDs in
				var result = UserNotificationData()
				result.activeAnnouncementIDs = activeAnnouncementIDs
				result.disabledFeatures = Settings.shared.disabledFeatures.buildDisabledFeatureArray()
				return result
			}
        }
		// Get the number of fezzes with unread messages
		return req.redis.hvals(in: NotificationType.fezUnreadMsg(user.userID).redisKeyName(userID: user.userID), as: Int.self)
				.and(req.redis.hvals(in: NotificationType.seamailUnreadMsg(user.userID).redisKeyName(userID: user.userID), 
				as: Int.self)).flatMap { (fezHash, seamailHash) in
			let unreadFezCount = fezHash.reduce(0) { $1 ?? 0 > 0 ? $0 + 1 : $0 }
			let unreadSeamailCount = seamailHash.reduce(0) { $1 ?? 0 > 0 ? $0 + 1 : $0 }
			return getActiveAnnouncementIDs(on: req).flatMap { actives in 
				return req.redis.hgetall(from: NotificationType.redisHashKeyForUser(user.userID)).flatMap { hash in
					let userHighestReadAnnouncement = hash["announcement_viewed"]?.int ?? 0
					let newAnnouncements = actives.reduce(0) { $1 > userHighestReadAnnouncement ? $0 + 1 : $0 }
					var nextEventFuture: EventLoopFuture<Date?> = req.eventLoop.future(nil)
					if let nextEventStr = hash[NotificationType.nextFollowedEventTime(nil, nil).redisFieldName()]?.string, 
							let doubleDate = Double(nextEventStr) {
						let eventDate = Date(timeIntervalSince1970: doubleDate)
						if Date() > eventDate {
							nextEventFuture = storeNextEventTime(userID: user.userID, eventBarrel: nil, on: req)
						}
						else {
							nextEventFuture = req.eventLoop.future(eventDate)
						}
					}
					return nextEventFuture.flatMap { nextEventDate in
						var result = UserNotificationData(newFezCount: unreadFezCount, newSeamailCount: unreadSeamailCount,
								activeAnnouncementIDs: actives, newAnnouncementCount: newAnnouncements, nextEvent: nextEventDate)
						result.twarrtMentionCount = hash["twarrtMention"]?.int ?? 0
						result.newTwarrtMentionCount = max(result.twarrtMentionCount - (hash["twarrtMention_viewed"]?.int ?? 0), 0)
						result.forumMentionCount = hash["forumMention"]?.int ?? 0
						result.newForumMentionCount = max(result.forumMentionCount - (hash["forumMention_viewed"]?.int ?? 0), 0)
						result.alertWords = getNewAlertWordCounts(hash: hash)
						return getModeratorNotifications(for: user, on: req).map { modNotificationData in
							result.moderatorData = modNotificationData
							return result
						}
					}
				}
			}
		}
	}
	
	// Pulls an array of active announcement IDs from Redis, from a key that expires every minute. If the key is expired,
	// rebuilds it by querying Announcements. Could be optimized a bit by setting expire time to the first expiring announcement,
	// and making sure we delete the key when announcements are added/edited/deleted. 
	func getActiveAnnouncementIDs(on req: Request) -> EventLoopFuture<[Int]> {
		return req.redis.get("ActiveAnnouncementIDs", as: String.self).flatMap { alertIDStr in
			if let idStr = alertIDStr {
				return req.eventLoop.future(idStr.split(separator: " ").compactMap { Int($0) })
			}
			else {
				return Announcement.query(on: req.db).filter(\.$displayUntil > Date()).all().flatMapThrowing() { activeAnnouncements in
					let ids = try activeAnnouncements.map { try $0.requireID() }
					let idStr = ids.map { String($0) }.joined(separator: " ")
					_ = req.redis.set("ActiveAnnouncementIDs", to: idStr, onCondition: .none, expiration: .seconds(60))
					return ids 
				}
			}
		}
	}
	
	func getNewAlertWordCounts(hash: [String : RESPValue]) -> [UserNotificationAlertwordData] {
	//	return req.redis.hgetall(from: NotificationType.redisHashKeyForUser(userID), as: Int.self).map { hash in
		var resultDict: [String : UserNotificationAlertwordData] = [:]
		hash.forEach { (key, value) in
			if key.hasSuffix("_viewed") {
				return
			}
			var word: String
			var isTweet = true
			if key.hasPrefix("alertwordTweet-") {
				word = String(key.dropFirst("alertwordTweet-".count))
			}
			else if key.hasPrefix("alertwordPost-") {
				word = String(key.dropFirst("alertwordPost-".count))
				isTweet = false
			}
			else {
				return
			}
			let viewedCount = hash[key + "_viewed"]?.int ?? 0
			var entry = resultDict[word] ?? UserNotificationAlertwordData(word)
			if isTweet {
				entry.twarrtMentionCount = value.int ?? 0
				entry.newTwarrtMentionCount = max(0, entry.twarrtMentionCount - viewedCount)
			}
			else {
				entry.forumMentionCount = value.int ?? 0
				entry.newForumMentionCount = max(0, entry.forumMentionCount - viewedCount)
			}
			resultDict[word] = entry
		}
		return Array(resultDict.values)
	}
	
	/// Returns a ModeratorNotificationData structure containing counts for open reports, seamails to @moderator with unread messages, and (if user is in TwitarrTeam) 
	/// seamails to @TwitarrTeam with unread messages. If the user is not a moderator, returns nil.
	func getModeratorNotifications(for user: UserCacheData, on req: Request) -> EventLoopFuture<UserNotificationData.ModeratorNotificationData?> {
		guard user.accessLevel.hasAccess(.moderator) else {
			return req.eventLoop.future(nil)
		}
		return Report.query(on: req.db).filter(\.$isClosed == false).filter(\.$actionGroup == nil).count().flatMap { reportCount in
			return req.redis.hvals(in: "UnreadModSeamails-\(user.userID)", as: Int.self).flatMap { seamailHash in
				let moderatorUnreadCount = seamailHash.reduce(0) { $1 ?? 0 > 0 ? $0 + 1 : $0 }
				var twittarTeamFuture: EventLoopFuture<Int?> = req.eventLoop.future(nil)
				if user.accessLevel.hasAccess(.twitarrteam) {
					twittarTeamFuture = req.redis.hvals(in: "UnreadTTSeamails-\(user.userID)", as: Int.self).map { ttSeamailHash in
						return ttSeamailHash.reduce(0) { $1 ?? 0 > 0 ? $0 + 1 : $0 }
					}
				}
				return twittarTeamFuture.map { ttUnreadCount in
					return UserNotificationData.ModeratorNotificationData(openReportCount: reportCount, 
							newModeratorSeamailMessageCount: moderatorUnreadCount, newTTSeamailMessageCount: ttUnreadCount)
				}
			}
		}
	}
	
	/// `WS /api/v3/notification/socket`
	/// 
	/// Creates a notification socket for the user. The client of this socket will receive <doc:SocketNotificationData> updates,
	/// generally when an event happens that would change a value in the user's <doc:UserNotificationData> struct.
	/// 
	/// This socket only sends <doc:SocketNotificationData> messages from the server to the client; there are no client-initiated
	/// messages defined for this socket.
	func createNotificationSocket(_ req: Request, _ ws: WebSocket) {
		guard let user = try? req.auth.require(UserCacheData.self) else {
			_ = ws.close()
			return
		}
		let userSocket = UserSocket(userID: user.userID, socket: ws)
		req.webSocketStore.storeSocket(userSocket)
		ws.onClose.whenComplete { result in
			req.webSocketStore.removeSocket(userSocket)
		}
	}
	
	// MARK: - Announcements

    /// `POST /api/v3/announcement/create`
    ///
    /// Create a new announcement. Requires THO access and above. When a new announcement is created the notification endpoints will start 
	/// indicating the new announcement to all users.
	/// 
    /// - Parameter requestBody: <doc:AnnouncementCreateData>
    /// - Returns: `HTTPStatus` 201 on success.
	func createAnnouncement(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO only")
		}
		let announcementData = try ValidatingJSONDecoder().decode(AnnouncementCreateData.self, fromBodyOf: req)
		let announcement = Announcement(authorID: user.userID, text: announcementData.text, displayUntil: announcementData.displayUntil)
			
		return announcement.save(on: req.db).throwingFlatMap {
			return User.query(on: req.db).field(\.$id).all().throwingFlatMap { allUsers in
				let userIDs = try allUsers.map { try $0.requireID() }
				return try addNotifications(users: userIDs, type: .announcement(announcement.requireID()),
						info: announcement.text, on: req).transform(to: .created)
			}
		}
	}
	
    /// `GET /api/v3/notification/announcements`
    ///
    /// Returns all active announcements, sorted by creation time, by default. 
	/// 
	/// **URL Query Parameters**
	/// 
	/// - `?inactives=true` Also return expired and deleted announcements. THO and admins only. 
	/// 		
	/// The purpose if the inactives flag is to allow for finding an expired announcement and re-activating it by changing its expire time. Remember that doing so
	/// doesn't re-alert users who have already read it.
    ///
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: Array of <doc:AnnouncementData>
	func getAnnouncements(_ req: Request) throws -> EventLoopFuture<[AnnouncementData]> {
		let user = req.auth.get(UserCacheData.self)
		let includeInactives: Bool = req.query[String.self, at: "inactives"] == "true"
		guard !includeInactives || (user?.accessLevel.hasAccess(.tho) ?? false) else {
			throw Abort(.forbidden, reason: "Inactive announcements are THO only")
		}
		let query = Announcement.query(on: req.db).sort(\.$id, .descending)
		if includeInactives {
			query.withDeleted()
		}
		else {
			query.filter(\.$displayUntil > Date())
		}
		return query.all().flatMapThrowing { announcements in
			var maxID = 0
			let result: [AnnouncementData] = try announcements.map { 
				let authorHeader = try req.userCache.getHeader($0.$author.id)
				if let annID = $0.id, annID > maxID { maxID = annID }
				return try AnnouncementData(from: $0, authorHeader: authorHeader) 
			}
			if let user = user, includeInactives == false {
				_ = markNotificationViewed(user: user, type: .announcement(maxID), on: req)
			}
			return result
		}
	}
	
    /// `GET /api/v3/notification/announcement/ID`
    ///
    /// Returns a single announcement, identified by its ID. THO and admins only. Others should just use `/api/v3/notification/announcements`.
	/// 
	/// Announcements shouldn't be large, and there shouldn't be many of them active at once (Less than 1KB each, if there's more than 5 active 
	/// at once people likely won't read them). This endpoint really exists to support admins editing announcements.
	/// 
    /// - Parameter announcementID: The announcement to find
    /// - Throws: 403 error if the user doesn't have THO-level access. 404 if no announcement with the given ID is found.
    /// - Returns: <doc:AnnouncementData>
	func getSingleAnnouncement(_ req: Request) throws -> EventLoopFuture<AnnouncementData> {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO only")
		}
  		guard let paramVal = req.parameters.get(announcementIDParam.paramString), let announcementID = Int(paramVal) else {
            throw Abort(.badRequest, reason: "Request parameter \(announcementIDParam.paramString) is missing.")
        }
		return Announcement.query(on: req.db).filter(\.$id == announcementID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "Announcement not found")).flatMapThrowing { announcement in
			let authorHeader = try req.userCache.getHeader(announcement.$author.id)
			return try AnnouncementData(from: announcement, authorHeader: authorHeader) 
		}
	}
	
    /// `POST /api/v3/notification/announcement/ID/edit`
    ///
    /// Edits an existing announcement. Editing a deleted announcement will un-delete it. Editing an announcement does not change any user's notification status for that
	/// announcement: if a user has seen the announcement already, editing it will not cause the user to be notified that they should read it again.
    ///
    /// - Parameter announcementID: The announcement to edit. Must exist.
    /// - Parameter requestBody: <doc:AnnouncementCreateData>
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: The updated <doc:AnnouncementCreateData>
	func editAnnouncement(_ req: Request) throws -> EventLoopFuture<AnnouncementData> {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO only")
		}
		let announcementData = try ValidatingJSONDecoder().decode(AnnouncementCreateData.self, fromBodyOf: req)
		guard let announcementIDStr = req.parameters.get(announcementIDParam.paramString), let announcementID = Int(announcementIDStr) else {
			throw Abort(.badRequest, reason: "Announcement ID is missing.")
		}
		return Announcement.query(on: req.db).filter(\.$id == announcementID).withDeleted().first()
				.unwrap(or: Abort(.notFound, reason: "Announcement not found.")).throwingFlatMap { announcement in
			if let deleteTime = announcement.deletedAt, deleteTime < Date() {
				return announcement.restore(on: req.db).transform(to: announcement)
			}
			return req.eventLoop.future(announcement)
		}.flatMap { (announcement: Announcement) in
			announcement.text = announcementData.text
			announcement.displayUntil = announcementData.displayUntil
			return announcement.save(on: req.db).flatMapThrowing {
				let authorHeader = try req.userCache.getHeader(announcement.$author.id)
				return try AnnouncementData(from: announcement, authorHeader: authorHeader)
			}
		}
	}
	
    /// `POST /api/v3/notification/announcement/ID/delete`
    /// `DELETE /api/v3/notification/announcement/ID`
    ///
    /// Deletes an existing announcement. Editing a deleted announcement will un-delete it.
    ///
    /// - Parameter announcementIDParam: The announcement to delete. 
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 NoContent on success.
	func deleteAnnouncement(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.tho) else {
			throw Abort(.forbidden, reason: "THO only")
		}
		return Announcement.findFromParameter(announcementIDParam, on: req).throwingFlatMap { announcement in
			return announcement.delete(on: req.db).flatMap {
				return User.query(on: req.db).field(\.$id).all().throwingFlatMap { allUsers in
					let userIDs = try allUsers.map { try $0.requireID() }
					return try subtractNotifications(users: userIDs, type: .announcement(announcement.requireID()), on: req)
							.transform(to: .noContent)
				}
			}
		}
	}
	
	// MARK: - Daily Themes

    /// `GET /api/v3/notification/dailythemes`
	/// 
	///  Returns information about all the daily themes currently registered.
    ///
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: An array of <doc:DailyThemeData> on success.
	func getDailyThemes(_ req: Request) throws -> EventLoopFuture<[DailyThemeData]> {
		return DailyTheme.query(on: req.db).sort(\.$cruiseDay, .ascending).all().flatMapThrowing { themes in
			return try themes.map { try DailyThemeData($0) }
		}
	}
}
