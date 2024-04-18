import Crypto
import FluentSQL
import Redis
import Vapor

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
		
		// Open access routes--no login required
		alertRoutes.get("hashtags", searchStringParam, use: getHashtagsHandler)

		// Flexible access endpoints -- login not required, although calls may act differently if logged in
		let flexAuthGroup = alertRoutes.addFlexAuth()
		flexAuthGroup.get("global", use: globalNotificationHandler)
		flexAuthGroup.get("user", use: globalNotificationHandler)
		flexAuthGroup.get("announcements", use: getAnnouncements)
		flexAuthGroup.get("dailythemes", use: getDailyThemes)

		// endpoints available only when logged in
		let tokenAuthGroup = alertRoutes.addTokenAuthRequirement()
		tokenAuthGroup.webSocket("socket", onUpgrade: createNotificationSocket)  // shouldUpgrade: (Request) -> Headers

		// endpoints available only when logged in as TwitarrTeam or above
		let ttAuthGroup = alertRoutes.addTokenAuthRequirement().grouped(RequireTwitarrTeamMiddleware())
		ttAuthGroup.get("announcement", announcementIDParam, use: getSingleAnnouncement)
		ttAuthGroup.post("announcement", "create", use: createAnnouncement)
		ttAuthGroup.post("announcement", announcementIDParam, "edit", use: editAnnouncement)
		ttAuthGroup.post("announcement", announcementIDParam, "delete", use: deleteAnnouncement)
		ttAuthGroup.delete("announcement", announcementIDParam, use: deleteAnnouncement)
	}

	// MARK: - Hashtags

	/// `GET /api/v3/notification/hashtags`
	///
	/// Retrieve info on hashtags that have been used.
	///
	/// - Parameter searchString: Partial Hashtag string. Must have at least 1 character.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns:
	func getHashtagsHandler(_ req: Request) async throws -> [String] {
		guard var paramVal = req.parameters.get(searchStringParam.paramString), paramVal.count >= 1 else {
			throw Abort(.badRequest, reason: "Request parameter \(searchStringParam.paramString) is missing.")
		}
		if paramVal.hasPrefix("#") {
			paramVal = String(paramVal.dropFirst())
		}
		guard paramVal.count >= 1, paramVal.count < 50, paramVal.allSatisfy({ $0.isLetter || $0.isNumber }) else {
			throw Abort(.badRequest, reason: "Request parameter \(searchStringParam.paramString) is malformed.")
		}
		let strings = try await req.redis.getHashtags(matching: paramVal)
		return strings
	}

	// MARK: - Notifications

	/// `GET /api/v3/notification/global`
	/// `GET /api/v3/notification/user`
	///
	/// Retrieve info on the number of each type of notification supported by Swiftarr.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `UserNotificationData`
	func globalNotificationHandler(_ req: Request) async throws -> UserNotificationData {
		guard let user = req.auth.get(UserCacheData.self) else {
			let activeAnnouncementIDs = try await getActiveAnnouncementIDs(on: req)
			var result = UserNotificationData()
			result.activeAnnouncementIDs = activeAnnouncementIDs
			result.disabledFeatures = Settings.shared.disabledFeatures.buildDisabledFeatureArray()
			return result
		}
		// Get the number of fezzes with unread messages
		async let userHash = try req.redis.getUserHash(userID: user.userID)
		async let unreadSeamailCount = try req.redis.getSeamailUnreadCounts(userID: user.userID, inbox: .seamail)
		async let unreadLFGCount = try req.redis.getSeamailUnreadCounts(userID: user.userID, inbox: .lfgMessages)
		async let actives = try getActiveAnnouncementIDs(on: req)
		async let modData = try getModeratorNotifications(for: user, on: req)
		let finishedSongCount = try await max(0, req.redis.getIntFromUserHash(userHash, field: .microKaraokeSongReady(0)) -
				req.redis.getIntFromUserHash(userHash, field: .microKaraokeSongReady(0), viewed: true))

		let userHighestReadAnnouncement = try await req.redis.getIntFromUserHash(userHash, field: .announcement(0))
		let newAnnouncements = try await actives.reduce(0) { $1 > userHighestReadAnnouncement ? $0 + 1 : $0 }
		// Get the next event this user's following or lfg this user has joined, if any
		var nextEvent = try await req.redis.getNextEventFromUserHash(userHash)
		let eventDateNow = Settings.shared.getScheduleReferenceDate(Settings.shared.upcomingEventNotificationSetting)
		if let validDate = nextEvent?.0, eventDateNow > validDate {
			// The previously cached event already happend; figure out what's next
			nextEvent = try await storeNextFollowedEvent(userID: user.userID, on: req)
		}
		let lfgDateNow = Settings.shared.getScheduleReferenceDate(Settings.shared.upcomingLFGNotificationSetting)
		var nextLFG = try await req.redis.getNextLFGFromUserHash(userHash)
		if let validDate = nextLFG?.0, lfgDateNow > validDate {
			// The previously cached LFG already happend; figure out what's next
			nextLFG = try await storeNextJoinedLFG(userID: user.userID, on: req)
		}
		var result = try await UserNotificationData(
			newFezCount: unreadLFGCount,
			newSeamailCount: unreadSeamailCount,
			activeAnnouncementIDs: actives,
			newAnnouncementCount: newAnnouncements,
			nextEventTime: nextEvent?.0,
			nextEvent: nextEvent?.1,
			nextLFGTime: nextLFG?.0,
			nextLFG: nextLFG?.1,
			microKaraokeFinishedSongCount: finishedSongCount
		)
		result.twarrtMentionCount = try await req.redis.getIntFromUserHash(userHash, field: .twarrtMention(0))
		result.newTwarrtMentionCount = try await max(
			result.twarrtMentionCount - req.redis.getIntFromUserHash(userHash, field: .twarrtMention(0), viewed: true),
			0
		)
		result.forumMentionCount = try await req.redis.getIntFromUserHash(userHash, field: .forumMention(0))
		result.newForumMentionCount = try await max(
			result.forumMentionCount - req.redis.getIntFromUserHash(userHash, field: .forumMention(0), viewed: true),
			0
		)
		result.alertWords = try await getNewAlertWordCounts(hash: userHash)
		result.moderatorData = try await modData
		return result
	}

	// Pulls an array of active announcement IDs from Redis, from a key that expires every minute. If the key is expired,
	// rebuilds it by querying Announcements. Could be optimized a bit by setting expire time to the first expiring announcement,
	// and making sure we delete the key when announcements are added/edited/deleted.
	func getActiveAnnouncementIDs(on req: Request) async throws -> [Int] {
		if let alertIDs = try await req.redis.getActiveAnnouncementIDs() {
			return alertIDs
		}
		else {
			let portTZDate = Settings.shared.timeZoneChanges.displayTimeToPortTime()
			let activeAnnouncements = try await Announcement.query(on: req.db).filter(\.$displayUntil > portTZDate)
				.all()
			let ids = try activeAnnouncements.map { try $0.requireID() }
			try await req.redis.setActiveAnnouncementIDs(ids)
			return ids
		}
	}

	func getNewAlertWordCounts(hash: [String: RESPValue]) -> [UserNotificationAlertwordData] {
		//	let hash = try await req.redis.hgetall(from: NotificationType.redisHashKeyForUser(userID), as: Int.self)
		var resultDict: [String: UserNotificationAlertwordData] = [:]
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
	func getModeratorNotifications(for user: UserCacheData, on req: Request) async throws -> UserNotificationData
		.ModeratorNotificationData?
	{
		guard user.accessLevel.hasAccess(.moderator) else {
			return nil
		}
		let userHash = try await req.redis.getUserHash(userID: user.userID)
		let reportCount = try await Report.query(on: req.db).filter(\.$isClosed == false).filter(\.$actionGroup == nil)
			.count()
		let seamailHash = try await req.redis.hvals(in: "UnreadModSeamails-\(user.userID)", as: Int.self).get()
		let moderatorUnreadCount = seamailHash.reduce(0) { $1 ?? 0 > 0 ? $0 + 1 : $0 }
		let moderatorForumMentionCount = req.redis.getIntFromUserHash(userHash, field: .moderatorForumMention(0)) - req.redis.getIntFromUserHash(userHash, field: .moderatorForumMention(0), viewed: true)
		var ttUnreadCount = 0
		var ttForumMentionCount = 0
		if user.accessLevel.hasAccess(.twitarrteam) {
			let ttSeamailHash = try await req.redis.hvals(in: "UnreadTTSeamails-\(user.userID)", as: Int.self).get()
			ttUnreadCount = ttSeamailHash.reduce(0) { $1 ?? 0 > 0 ? $0 + 1 : $0 }
			ttForumMentionCount = req.redis.getIntFromUserHash(userHash, field: .twitarrTeamForumMention(0)) - req.redis.getIntFromUserHash(userHash, field: .twitarrTeamForumMention(0), viewed: true)
		}
		return UserNotificationData.ModeratorNotificationData(
			openReportCount: reportCount,
			newModeratorSeamailMessageCount: moderatorUnreadCount,
			newTTSeamailMessageCount: ttUnreadCount,
			newModeratorForumMentionCount: moderatorForumMentionCount,
			newTTForumMentionCount: ttForumMentionCount
		)
	}

	/// `WS /api/v3/notification/socket`
	///
	/// Creates a notification socket for the user. The client of this socket will receive `SocketNotificationData` updates,
	/// generally when an event happens that would change a value in the user's `UserNotificationData` struct.
	///
	/// This socket only sends `SocketNotificationData` messages from the server to the client; there are no client-initiated
	/// messages defined for this socket.
	func createNotificationSocket(_ req: Request, _ ws: WebSocket) {
		guard let user = try? req.auth.require(UserCacheData.self) else {
			_ = ws.close()
			return
		}
		let userSocket = UserSocket(userID: user.userID, socket: ws)
		req.webSocketStore.storeSocket(userSocket)
		req.logger.log(level: .info, "Created notification socket for user \(user.username)")
		ws.onClose.whenComplete { result in
			req.webSocketStore.removeSocket(userSocket)
		}
	}

	// MARK: - Announcements

	/// `POST /api/v3/notification/announcement/create`
	///
	/// Create a new announcement. Requires TwitarrTeam access and above. When a new announcement is created the notification endpoints will start
	/// indicating the new announcement to all users.
	///
	/// - Parameter requestBody: `AnnouncementCreateData`
	/// - Returns: `HTTPStatus` 201 on success.
	func createAnnouncement(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.twitarrteam) else {
			throw Abort(.forbidden, reason: "TwitarrTeam and THO only")
		}
		let announcementData = try ValidatingJSONDecoder().decode(AnnouncementCreateData.self, fromBodyOf: req)
		let announcement = Announcement(
			authorID: user.userID,
			text: announcementData.text,
			displayUntil: announcementData.displayUntil
		)
		try await announcement.save(on: req.db)
		let allUsers = try await User.query(on: req.db).field(\.$id).all()
		let userIDs = try allUsers.map { try $0.requireID() }
		try await addNotifications(
			users: userIDs,
			type: .announcement(announcement.requireID()),
			info: announcement.text,
			on: req
		)
		return .created
	}

	/// `GET /api/v3/notification/announcements`
	///
	/// Returns all active announcements, sorted by creation time, by default.
	///
	/// **URL Query Parameters**
	///
	/// - `?inactives=true` Also return expired and deleted announcements. TwitarrTeam and above only.
	///
	/// The purpose of the inactives flag is to allow for finding an expired announcement and re-activating it by changing its expire time. Doing so
	/// does not re-alert users who have already read it.
	///
	/// - Returns: Array of `AnnouncementData`
	func getAnnouncements(_ req: Request) async throws -> [AnnouncementData] {
		let user = req.auth.get(UserCacheData.self)
		let query = Announcement.query(on: req.db).sort(\.$id, .descending)

		// Prevent users with access levels below TwitarrTeam from loading inactive annoucnements
		let includeInactives: Bool =
			(user?.accessLevel.hasAccess(.twitarrteam) ?? false) && req.query[String.self, at: "inactives"] == "true"
		if includeInactives {
			query.withDeleted()
		}
		else {
			let portTZDate = Settings.shared.timeZoneChanges.displayTimeToPortTime()
			query.filter(\.$displayUntil > portTZDate)
		}
		let announcements = try await query.all()
		var maxID = 0
		let result: [AnnouncementData] = try announcements.map {
			let authorHeader = try req.userCache.getHeader($0.$author.id)
			if let annID = $0.id, annID > maxID { maxID = annID }
			return try AnnouncementData(from: $0, authorHeader: authorHeader)
		}
		if let user = user, includeInactives == false {
			try await markNotificationViewed(user: user, type: .announcement(maxID), on: req)
		}
		return result
	}

	/// `GET /api/v3/notification/announcement/ID`
	///
	/// Returns a single announcement, identified by its ID. TwitarrTeam and above only. Others should just use `/api/v3/notification/announcements`.
	/// Will return AnnouncementData for deleted announcements.
	///
	/// Announcements shouldn't be large, and there shouldn't be many of them active at once (Less than 1KB each, if there's more than 5 active
	/// at once people likely won't read them). This endpoint really exists to support admins editing announcements.
	///
	/// - Parameter announcementID: The announcement to find
	/// - Throws: 403 error if the user doesn't have TwitarrTeam or higher access. 404 if no announcement with the given ID is found.
	/// - Returns: `AnnouncementData`
	func getSingleAnnouncement(_ req: Request) async throws -> AnnouncementData {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.twitarrteam) else {
			throw Abort(.forbidden, reason: "TwitarrTeam and THO only")
		}
		guard let paramVal = req.parameters.get(announcementIDParam.paramString), let announcementID = Int(paramVal)
		else {
			throw Abort(.badRequest, reason: "Request parameter \(announcementIDParam.paramString) is missing.")
		}
		let announcement = try await Announcement.query(on: req.db).filter(\.$id == announcementID).withDeleted()
			.first()
		guard let announcement = announcement else {
			throw Abort(.notFound, reason: "Announcement not found")
		}
		let authorHeader = try req.userCache.getHeader(announcement.$author.id)
		return try AnnouncementData(from: announcement, authorHeader: authorHeader)
	}

	/// `POST /api/v3/notification/announcement/ID/edit`
	///
	/// Edits an existing announcement. Editing a deleted announcement will un-delete it. Editing an announcement does not change any user's notification status for that
	/// announcement: if a user has seen the announcement already, editing it will not cause the user to be notified that they should read it again.
	///
	/// - Parameter announcementID: The announcement to edit. Must exist.
	/// - Parameter requestBody: `AnnouncementCreateData`
	/// - Throws: 403 error if the user is not permitted to edit.
	/// - Returns: The updated `AnnouncementCreateData`
	func editAnnouncement(_ req: Request) async throws -> AnnouncementData {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.twitarrteam) else {
			throw Abort(.forbidden, reason: "TwitarrTeam and THO only")
		}
		let announcementData = try ValidatingJSONDecoder().decode(AnnouncementCreateData.self, fromBodyOf: req)
		guard let announcementIDStr = req.parameters.get(announcementIDParam.paramString),
			let announcementID = Int(announcementIDStr)
		else {
			throw Abort(.badRequest, reason: "Announcement ID is missing.")
		}
		let announcement = try await Announcement.query(on: req.db).filter(\.$id == announcementID).withDeleted()
			.first()
		guard let announcement = announcement else {
			throw Abort(.notFound, reason: "Announcement not found.")
		}
		if let deleteTime = announcement.deletedAt, deleteTime < Date() {
			try await announcement.restore(on: req.db)
		}
		announcement.text = announcementData.text
		announcement.displayUntil = announcementData.displayUntil
		try await announcement.save(on: req.db)
		let authorHeader = try req.userCache.getHeader(announcement.$author.id)
		return try AnnouncementData(from: announcement, authorHeader: authorHeader)
	}

	/// `POST /api/v3/notification/announcement/ID/delete`
	/// `DELETE /api/v3/notification/announcement/ID`
	///
	/// Deletes an existing announcement. Editing a deleted announcement will un-delete it TwitarrTeam and above only.
	///
	/// - Parameter announcementIDParam: The announcement to delete.
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 NoContent on success.
	func deleteAnnouncement(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard user.accessLevel.hasAccess(.twitarrteam) else {
			throw Abort(.forbidden, reason: "TwitarrTeam and THO only")
		}
		let announcement = try await Announcement.findFromParameter(announcementIDParam, on: req)
		try await announcement.delete(on: req.db)
		let allUsers = try await User.query(on: req.db).field(\.$id).all()
		let userIDs = try allUsers.map { try $0.requireID() }
		try await subtractNotifications(users: userIDs, type: .announcement(announcement.requireID()), on: req)
		return .noContent
	}

	// MARK: - Daily Themes

	/// `GET /api/v3/notification/dailythemes`
	///
	///  Returns information about all the daily themes currently registered.
	///
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: An array of `DailyThemeData` on success.
	func getDailyThemes(_ req: Request) async throws -> [DailyThemeData] {
		let themes = try await DailyTheme.query(on: req.db).sort(\.$cruiseDay, .ascending).all()
		return try themes.map { try DailyThemeData($0) }
	}
}
