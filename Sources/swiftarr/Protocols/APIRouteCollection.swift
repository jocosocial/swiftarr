import FluentSQL
import Redis
import Vapor

// only API routes should use the RoutesBuilder extensions. Site routes have different requirements.
extension RoutesBuilder {
	/// Adds Flexible Auth to a route. This route can be accessed without a token (while not logged in), but `req.auth.get(User.self)` will still
	/// return a user if one is logged in. Route handlers for these routes should not call `req.auth.require(User.self)`. A route with no auth
	/// middleware will not auth any user and `.get(User.self)` will always return nil. The Basic and Token auth groups will throw an error if
	/// no user gets authenticated (specifically:` User.guardMiddleware` throws).
	///
	/// So, use this auth group for routes that can be accessed while not logged in, but which provide more (or different) data when a logged-in user
	/// accesses the route.
	func addFlexAuth() -> RoutesBuilder {
		return self.grouped([UserCacheData.TokenAuthenticator()])
	}

	/// For routes that require HTTP Basic Auth. Tokens won't work. Generally, this is only for the login route.
	func addBasicAuthRequirement() -> RoutesBuilder {
		return self.grouped([
			UserCacheData.BasicAuth(),
			MinUserAccessLevelMiddleware(requireAuth: true),
		])
	}

	/// For routes that require a logged-in user. Applying this auth group to a route will make requests that don't have a valid token fail with a HTTP 401 error.
	func addTokenAuthRequirement() -> RoutesBuilder {
		return self.grouped([
			UserCacheData.TokenAuthenticator(),
			UserCacheData.guardMiddleware(throwing: Abort(.unauthorized, reason: "User not authenticated.")),
		])
	}

	func flexRoutes(feature: SwiftarrFeature? = nil, path: PathComponent...) -> RoutesBuilder {
		var builder = self.addFlexAuth().grouped(path)
			.grouped([
				UserCacheData.TokenAuthenticator(),
				MinUserAccessLevelMiddleware(requireAuth: false),
			])
		if let feature = feature {
			builder = builder.grouped(DisabledAPISectionMiddleware(feature: feature))
		}
		return builder
	}

	func tokenRoutes(feature: SwiftarrFeature? = nil, minAccess: UserAccessLevel = .banned, path: PathComponent...)
		-> RoutesBuilder
	{
		var builder = self.grouped(path)
			.grouped([
				UserCacheData.TokenAuthenticator(),
				MinUserAccessLevelMiddleware(requireAuth: true, requireAccessLevel: minAccess),
			])
		if let feature = feature {
			builder = builder.grouped(DisabledAPISectionMiddleware(feature: feature))
		}
		return builder
	}
}

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
	var alertwordParam: PathComponent { PathComponent(":alert_word") }
	var mutewordParam: PathComponent { PathComponent(":mute_word") }
	var searchStringParam: PathComponent { PathComponent(":search_string") }
	var dailyThemeIDParam: PathComponent { PathComponent(":daily_theme_id") }
	var accessLevelParam: PathComponent { PathComponent(":access_level") }
	var boardgameIDParam: PathComponent { PathComponent(":boardgame_id") }
	var songIDParam: PathComponent { PathComponent(":karaoke_song+id") }
	var mkSongIDParam: PathComponent { PathComponent(":micro_karaoke_song_id") }
	var mkSnippetIDParam: PathComponent { PathComponent(":micro_karaoke_snippet_id") }
	var userRoleParam: PathComponent { PathComponent(":user_role") }
	var phonecallParam: PathComponent { PathComponent(":phone_call") }
	var scheduleLogIDParam: PathComponent { PathComponent(":schedule_log_id") }
	var filenameParam: PathComponent { PathComponent(":filename") }
	var imageFilenameParam: PathComponent { PathComponent(":image_filename") }
	var streamPhotoIDParam: PathComponent { PathComponent(":stream_photoID") }
	var performerIDParam: PathComponent { PathComponent(":performer_id") }
	var personalEventIDParam: PathComponent { PathComponent(":personal_event_id") }

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
		}
		else {
			if #available(OSX 10.13, *) {
				if let msDate = string.iso8601ms {
					date = msDate
					//				if let dateFromISO8601ms = ISO8601DateFormatter().date(from: string) {
					//					date = dateFromISO8601ms
				}
			}
			else {
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

	// MARK: - Guards
	// Throws an error if the given user is a 'special' account that cannot have its username or userAccessLevel changed.
	func guardNotSpecialAccount(_ targetUser: User) throws {
		guard targetUser.username != "moderator" else {
			throw Abort(.badRequest, reason: "Cannot change name or access level of @moderator account.")
		}
		guard targetUser.username != "TwitarrTeam" else {
			throw Abort(.badRequest, reason: "Cannot change name or  access level of @TwitarrTeam account.")
		}
		guard targetUser.username != "THO" else {
			throw Abort(.badRequest, reason: "Cannot change name or  access level of @THO account.")
		}
		guard targetUser.username != "admin" else {
			throw Abort(.badRequest, reason: "Cannot change name or  access level of @admin account.")
		}
		// Can't change access level of Clients
		guard targetUser.accessLevel != .client else {
			throw Abort(.badRequest, reason: "Cannot change name or  access level of Client accounts.")
		}
	}

	// MARK: - Notification Management

	// When an event happens that could change notification counts for someone (e.g. a user posts a Twarrt with an @mention)
	// call this method to do the notification bookkeeping.
	//
	// The users array should be pre-filtered to include only those who can actually see the new content (that is, not
	// blocking or muting it, or not in the group that receives the content).
	//
	// Adding a new notification will also send out an update to all relevant users who are listening on notification sockets.
	func addNotifications(users: [UUID], type: NotificationType, info: String, excludeUsers: [UUID] = [], on req: Request) async throws {
		try await withThrowingTaskGroup(of: Void.self) { group -> Void in
			var forwardToSockets = true
			// Members of `users` get push notifications
			// `stateChangeUsers` includes users that had their notification counts change, but don't send push notifications
			var stateChangeUsers = users
			switch type {
			case .announcement:
				// Force cache of active announcementIDs to get rebuilt
				group.addTask { try await req.redis.resetActiveAnnouncementIDs() }

			case .addedToChat(let msgID, let chatType):
				stateChangeUsers = bookkeepUserAddedToChat(req: req, msgID: msgID, chatType: chatType, users: users, group: &group)
			
			case .chatUnreadMsg(let msgID, let chatType):
				stateChangeUsers = bookkeepNewChatMessage(req: req, msgID: msgID, chatType: chatType, users: users, group: &group, excludeUsers: excludeUsers)

			case .nextFollowedEventTime(let date, let id):
				for userID in users {
					group.addTask {
						try await req.redis.setNextEventInUserHash(date: date, eventID: id, userID: userID)
					}
				}
				forwardToSockets = false
			case .nextJoinedLFGTime(let date, let id):
				for userID in users {
					group.addTask {
						try await req.redis.setNextLFGInUserHash(date: date, lfgID: id, userID: userID)
					}
				}
				forwardToSockets = false
			case .alertwordTwarrt(let alertword, _):
				for userID in users {
					group.addTask {
						try await req.redis.incrementAlertwordTwarrtInUserHash(word: alertword, userID: userID)
					}
				}
			case .alertwordPost(let alertword, _):
				for userID in users {
					group.addTask {
						try await req.redis.incrementAlertwordPostInUserHash(word: alertword, userID: userID)
					}
				}
			case .twarrtMention(_):
				for userID in users {
					group.addTask { try await req.redis.incrementIntInUserHash(field: type, userID: userID) }
				}
			case .forumMention(_), .twitarrTeamForumMention(_), .moderatorForumMention(_):
				for userID in users {
					group.addTask { try await req.redis.incrementIntInUserHash(field: type, userID: userID) }
				}
			case .followedEventStarting(_), .joinedLFGStarting(_), .personalEventStarting(_):
				break
			case .microKaraokeSongReady(_):
				for userID in users {
					group.addTask { try await req.redis.incrementIntInUserHash(field: type, userID: userID) }
				}
			}

			if forwardToSockets {
				// Send a message to all involved users with open websockets.
				await req.application.notificationSockets.forwardToSockets(app: req.application, idList: users, type: type, info: info)
			}

			let stateChangeUsersCopy = stateChangeUsers
			group.addTask { try await req.redis.addUsersWithStateChange(stateChangeUsersCopy) }

			// I believe this line is required to let subtasks propagate thrown errors by rethrowing.
			for try await _ in group {}
		}
	}

	func bookkeepUserAddedToChat(req: Request, msgID: UUID, chatType: FezType, users: [UUID],
			group: inout ThrowingTaskGroup<Void, Error>) -> [UUID] {
		var updateCountsUsers = users
		// For seamail msgs with "moderator" or "TwitarrTeam" in the memberlist, add all team members to the
		// update counts list. This is so all team members have individual read counts.
		if let mod = req.userCache.getUser(username: "moderator"), users.contains(mod.userID) {
			let modList = req.userCache.allUsersWithAccessLevel(.moderator).map { $0.userID }
			updateCountsUsers.append(contentsOf: modList)
			for modUserID in modList {
				group.addTask {
					try await req.redis.userAddedToChat(chatID: msgID, userID: modUserID, inbox: .moderatorSeamail)
				}
			}
		}
		if let ttUser = req.userCache.getUser(username: "TwitarrTeam"), users.contains(ttUser.userID) {
			let ttList = req.userCache.allUsersWithAccessLevel(.twitarrteam).map { $0.userID }
			updateCountsUsers.append(contentsOf: ttList)
			for ttUserID in ttList {
				group.addTask {
					try await req.redis.userAddedToChat(chatID: msgID, userID: ttUserID, inbox: .twitarrTeamSeamail)
				}
			}
		}
		// Users who aren't "moderator" and are in the thread see it as a normal thread.
		let inbox = Request.Redis.MailInbox.mailboxForChatType(type: chatType)
		for userID in users {
			group.addTask { try await req.redis.userAddedToChat(chatID: msgID, userID: userID, inbox: inbox) }
		}
		return updateCountsUsers
	}

	func bookkeepNewChatMessage(req: Request, msgID: UUID, chatType: FezType, users: [UUID],
			group: inout ThrowingTaskGroup<Void, Error>, excludeUsers: [UUID] = []) -> [UUID] {
		var updateCountsUsers = users
		// For seamail msgs with "moderator" or "TwitarrTeam" in the memberlist, add all team members to the
		// update counts list. This is so all team members have individual read counts.
		//
		// To avoid generating notifications for the user who created the new chat message,
		// pass their ID in via the excludeUsers array to omit them from generating the messages.
		if let mod = req.userCache.getUser(username: "moderator"), users.contains(mod.userID) {
			let allModList = req.userCache.allUsersWithAccessLevel(.moderator).map { $0.userID }
			let modList: [UUID] = allModList.filter { !excludeUsers.contains($0) }
			updateCountsUsers.append(contentsOf: modList)
			for modUserID in modList {
				group.addTask {
					try await req.redis.newUnreadMessage(chatID: msgID, userID: modUserID, inbox: .moderatorSeamail)
				}
			}
		}
		if let ttUser = req.userCache.getUser(username: "TwitarrTeam"), users.contains(ttUser.userID) {
			let allTTList = req.userCache.allUsersWithAccessLevel(.twitarrteam).map { $0.userID }
			let ttList: [UUID] = allTTList.filter { !excludeUsers.contains($0) }
			updateCountsUsers.append(contentsOf: ttList)
			for ttUserID in ttList {
				group.addTask {
					try await req.redis.newUnreadMessage(chatID: msgID, userID: ttUserID, inbox: .twitarrTeamSeamail)
				}
			}
		}
		// Users who aren't "moderator" and are in the thread see it as a normal thread.
		let inbox = Request.Redis.MailInbox.mailboxForChatType(type: chatType)
		let actualUsers = users.filter { !excludeUsers.contains($0) }
		for userID in actualUsers {
			group.addTask { try await req.redis.newUnreadMessage(chatID: msgID, userID: userID, inbox: inbox) }
		}
		return updateCountsUsers
	}

	// When an event happens that could reduce notification counts for someone (e.g. a user deletes a Twarrt with an @mention)
	// call this method to do the notification bookkeeping. DON'T call this to mark notifications as "seen".
	func subtractNotifications(users: [UUID], type: NotificationType, subtractCount: Int = 1, on req: Request)
		async throws
	{
		try await withThrowingTaskGroup(of: Void.self) { group -> Void in
			switch type {
			case .announcement:
				// Force cache of active announcementIDs to get rebuilt
				group.addTask { try await req.redis.resetActiveAnnouncementIDs() }

			case .addedToChat(let msgID, _), .chatUnreadMsg(let msgID, _):
				// For chat msgs with "moderator" or "TwitarrTeam" in the memberlist, add all team members to the
				// notify list. This is so all team members have individual read counts.
				if let mod = req.userCache.getUser(username: "moderator"), users.contains(mod.userID) {
					let modList = req.userCache.allUsersWithAccessLevel(.moderator).map { $0.userID }
					for modUserID in modList {
						group.addTask {
							try await req.redis.deletedUnreadMessage(
								msgID: msgID,
								userID: modUserID,
								inbox: .moderatorSeamail
							)
						}
					}
				}
				if let ttUser = req.userCache.getUser(username: "TwitarrTeam"), users.contains(ttUser.userID) {
					let ttList = req.userCache.allUsersWithAccessLevel(.twitarrteam).map { $0.userID }
					for ttUserID in ttList {
						group.addTask {
							try await req.redis.deletedUnreadMessage(
								msgID: msgID,
								userID: ttUserID,
								inbox: .twitarrTeamSeamail
							)
						}
					}
				}
				// Users who aren't "moderator" and are in the thread see it as a normal thread.
				for userID in users {
					group.addTask {
						try await req.redis.deletedUnreadMessage(msgID: msgID, userID: userID, inbox: .seamail)
					}
				}

			case .twarrtMention(_):
				for userID in users {
					group.addTask {
						try await req.redis.incrementIntInUserHash(
							field: type,
							userID: userID,
							incAmount: 0 - subtractCount
						)
					}
				}
			case .forumMention(_), .twitarrTeamForumMention(_), .moderatorForumMention(_):
				for userID in users {
					group.addTask {
						try await req.redis.incrementIntInUserHash(
							field: type,
							userID: userID,
							incAmount: 0 - subtractCount
						)
					}
				}
			case .alertwordTwarrt(let word, _):
				for userID in users {
					try await req.redis.incrementAlertwordTwarrtInUserHash(
						word: word,
						userID: userID,
						incAmount: 0 - subtractCount
					)
				}
			case .alertwordPost(let word, _):
				for userID in users {
					try await req.redis.incrementAlertwordPostInUserHash(
						word: word,
						userID: userID,
						incAmount: 0 - subtractCount
					)
				}
			case .nextFollowedEventTime, .followedEventStarting, .nextJoinedLFGTime, .joinedLFGStarting,
				.personalEventStarting:
				break
			case .microKaraokeSongReady(_):
				// There is currently no method by which songs become not-ready. But,
				for userID in users {
					group.addTask {
						try await req.redis.incrementIntInUserHash(
							field: type,
							userID: userID,
							incAmount: 0 - subtractCount
						)
					}
				}
			}
			group.addTask { try await req.redis.addUsersWithStateChange(users) }

			// I believe this line is required to let subtasks propagate thrown errors by rethrowing.
			try await group.waitForAll()
		}
	}

	// When a user leaves a fez or the fez is deleted, delete the unread count for that fez for all participants; it no longer applies.
	// Also recalculate the next joined LFG for each former participant.
	func deleteFezNotifications(userIDs: [UUID], fez: FriendlyFez, on req: Request) async throws {
		for userID in userIDs {
			try await req.redis.markLFGDeleted(msgID: fez.requireID(), userID: userID)
			_ = try await storeNextJoinedAppointment(userID: userID, on: req)
		}
	}

	// When a user does an action that might clear a notification call this to handle bookkeeping.
	// Actions that could clear notifications: Viewing their @mentions (clears @mention notifications), viewing alert word hits,
	// viewing announcements, reading seamails.
	func markNotificationViewed(user: UserCacheData, type: NotificationType, on req: Request) async throws {
		switch type {
		case .announcement(let id):
			try await req.redis.setIntInUserHash(to: id, field: type, userID: user.userID)
		case .addedToChat, .chatUnreadMsg:
			try await req.redis.markChatRead(type: type, userID: user.userID)
			// It's possible this is a mod viewing mail to @moderator, not their own. We can't tell from here.
			// But, we can just clear the modmail hash for this thread ID.
			if user.accessLevel.hasAccess(.moderator) {
				try await req.redis.markChatRead(type: type, in: .moderatorSeamail, userID: user.userID)
			}
			if user.accessLevel.hasAccess(.twitarrteam) {
				try await req.redis.markChatRead(type: type, in: .twitarrTeamSeamail, userID: user.userID)
			}

		case .twarrtMention, .forumMention, .alertwordTwarrt, .alertwordPost:
			try await req.redis.markAllViewedInUserHash(field: type, userID: user.userID)
		case .moderatorForumMention:
			if user.accessLevel.hasAccess(.moderator) {
				try await req.redis.markAllViewedInUserHash(field: type, userID: user.userID)
			}
		case .twitarrTeamForumMention:
			if user.accessLevel.hasAccess(.twitarrteam) {
				try await req.redis.markAllViewedInUserHash(field: type, userID: user.userID)
			}
		case .nextFollowedEventTime, .followedEventStarting, .nextJoinedLFGTime, .joinedLFGStarting,
			.personalEventStarting:
			return  // Can't be cleared
		case .microKaraokeSongReady:
			try await req.redis.markAllViewedInUserHash(field: type, userID: user.userID)
		}
		try await req.redis.addUsersWithStateChange([user.userID])
	}

	// Calculates the start time of the earliest future followed event. Caches the value in Redis for quick access.
	// The "current" reference date depends on a setting whether to operate in "real time" (aka what you the human
	// reading this comment right now experience as the current date), or "cruise time" (aka what someone experienced)
	// on board in the past or in the future.
	func storeNextFollowedEvent(userID: UUID, on req: Request) async throws -> (Date, UUID)? {
		let filterDate: Date = Settings.shared.getScheduleReferenceDate(Settings.shared.upcomingEventNotificationSetting)
		let nextFavoriteEvent = try await Event.query(on: req.db)
			.filter(\.$startTime > filterDate)
			.sort(\.$startTime, .ascending)
			.join(EventFavorite.self, on: \Event.$id == \EventFavorite.$event.$id)
			.filter(EventFavorite.self, \.$user.$id == userID)
			.first()
		// This will "clear" the next Event values of the UserNotificationData if no Events match the
		// query (which is to say there is no next Event). Thought about using subtractNotifications()
		// but this just seems easier for now.
		try await addNotifications(
			users: [userID],
			type: .nextFollowedEventTime(nextFavoriteEvent?.startTime, nextFavoriteEvent?.id),
			info: "",
			on: req
		)
		if let event = nextFavoriteEvent, let id = event.id {
			return (event.startTime, id)
		}
		return nil
	}

	// Calculates the start time of the earliest future joined LFG. Caches the value in Redis for quick access.
	// The "current" reference date depends on a setting whether to operate in "real time" (aka what you the human
	// reading this comment right now experience as the current date), or "cruise time" (aka what someone experienced)
	// on board in the past or in the future.
	func storeNextJoinedAppointment(userID: UUID, on req: Request) async throws -> (Date, UUID)? {
		let filterDate: Date = Settings.shared.getScheduleReferenceDate(Settings.shared.upcomingLFGNotificationSetting)
		let nextJoinedLFG = try await FriendlyFez.query(on: req.db)
			.join(FezParticipant.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
			.filter(FezParticipant.self, \.$user.$id == userID)
			.filter(\.$fezType !~ [.open, .closed])
			.filter(\.$startTime != nil)
			.filter(\.$startTime > filterDate)
			.sort(\.$startTime, .ascending)
			.first()
		// This will "clear" the next LFG values of the UserNotificationData if no LFGs match the
		// query (which is to say there is no next LFG). Thought about using subtractNotifications()
		// but this just seems easier for now.
		try await addNotifications(
			users: [userID],
			type: .nextJoinedLFGTime(nextJoinedLFG?.startTime, nextJoinedLFG?.id),
			info: "",
			on: req
		)
		if let lfg = nextJoinedLFG, let lfgID = lfg.id, let lfgStartTime = lfg.startTime {
			return (lfgStartTime, lfgID)
		}
		return nil
	}
}
