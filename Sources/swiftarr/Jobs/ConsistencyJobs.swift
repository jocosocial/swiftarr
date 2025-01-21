import Fluent
import Queues
import Vapor

// Holder for the constant data of privileged users in the application.
struct PrivilegedUsers {
	var ttUser: User
	var modUser: User

	init(ttUser: User, modUser: User) {
		self.ttUser = ttUser
		self.modUser = modUser
	}
}

// Job to run once a night to synchronize notification data between the Postgres database
// and Redis. In years past we have observed that on a number of occasions data can become
// inconsistent leading to permanently unread seamails and the like. This job recalculates
// the most common failure modes and updates the Redis notification data so that inconsistencies
// don't last too long.
struct UpdateRedisJobBase: APICollection {
	// Removes any stale unread chat IDs from the given mailbox.
	func cleanupMailInbox(_ context: QueueContext, userID: UUID, inbox: MailInbox, inboxData: [UUID: MailInbox]) async throws -> Void {
		// existingKeys are the keys present in the Redis Hash.
		let existingKeys = try await Set(context.application.redis.getUnreadChats(userID: userID, inbox: inbox))
		// newKeys are the keys that should be the Redis Hash.
		let newKeys = Set(inboxData.filter { $0.value == inbox }.map { $0.key })
		// staleKeys are garbage that should be removed from the Redis Hash.
		let staleKeys = existingKeys.subtracting(newKeys)
		for key in staleKeys {
			context.logger.warning("Found stale key \(key) in \(inbox) for \(userID)")
			try await context.application.redis.markChatRead(key, in: inbox, for: userID)
		}
		if (staleKeys.count > 0) {
			try await context.application.redis.addUsersWithStateChange([userID])
		}
	}

	// Looks at all Chats (Fezzes) that a user is a part of and calculates any unreads.
	// Or clears any unreads if none exist.
	func processChatParticipants(
		_ context: QueueContext,
		chatParticipants: [FezParticipant],
		userID: UUID,
		overrideInbox: MailInbox? = nil
	) async throws {
		try await withThrowingTaskGroup(of: Void.self) { group in
			var chatsInboxData: [UUID: MailInbox] = [:]
			for participant in chatParticipants {
				let chatID = try participant.fez.requireID()
				let unreadCount = participant.fez.postCount - participant.readCount
				let inbox = overrideInbox ?? MailInbox.mailboxForChatType(type: participant.fez.fezType)
				// Adding {chatID: 0} to the Unread hash is counted as a conversation with
				// unread messages, so we need to avoid adding any with an unreadCount of 0.
				guard unreadCount != 0 else {
					continue
				}
				let redisUnreadCount = try await context.application.redis.getChatUnreadCount(chatID, for: userID, in: inbox)
				if (unreadCount != redisUnreadCount) {
					context.application.logger.warning("Unread count inconsistent in chat \(chatID) for user \(userID)")
					group.addTask {
						try await context.application.redis.setChatUnreadCount(
							unreadCount,
							chatID: chatID,
							userID: userID,
							inbox: inbox
						)
					}
					try await context.application.redis.addUsersWithStateChange([userID])
				}
				chatsInboxData[chatID] = inbox
			}
			if let inbox = overrideInbox {
				try await cleanupMailInbox(context, userID: userID, inbox: inbox, inboxData: chatsInboxData)
			}
			for inbox in MailInbox.userMailInboxes {
				try await cleanupMailInbox(context, userID: userID, inbox: inbox, inboxData: chatsInboxData)
			}
		}
	}

	// Ensure common data inconsistencies for a user are fixed. At this time this does not do
	// all possible Redis data, just the ones that have been observed to cause issues.
	func processUser(_ context: QueueContext, user: User, privilegedUsers: PrivilegedUsers) async throws {
		let userID = try user.requireID()
		context.logger.debug("\(userID)")
		// Fez Consistency
		let userFezParticipants = try await FezParticipant.query(on: context.application.db)
			.with(\.$fez)
			.filter(\.$user.$id == userID)
			.all()
		context.logger.debug("User is part of \(userFezParticipants.count) chats")
		try await self.processChatParticipants(context, chatParticipants: userFezParticipants, userID: userID)

		// Privileged Users
		if user.accessLevel.hasAccess(.twitarrteam) {
			let ttFezParticipants = try await FezParticipant.query(on: context.application.db)
				.with(\.$fez)
				.filter(\.$user.$id == privilegedUsers.ttUser.requireID())
				.all()
			context.logger.debug("User is part of \(ttFezParticipants.count) TwitarrTeam chats")
			try await self.processChatParticipants(
				context,
				chatParticipants: ttFezParticipants,
				userID: userID,
				overrideInbox: MailInbox.twitarrTeamSeamail
			)
		}

		if user.accessLevel.hasAccess(.moderator) {
			let modFezParticipants = try await FezParticipant.query(on: context.application.db)
				.with(\.$fez)
				.filter(\.$user.$id == privilegedUsers.modUser.requireID())
				.all()
			context.logger.debug("User is part of \(modFezParticipants.count) moderator chats")
			try await self.processChatParticipants(
				context,
				chatParticipants: modFezParticipants,
				userID: userID,
				overrideInbox: MailInbox.moderatorSeamail
			)
		}
		// We don't have separate mailbox information for THO user
		// End Fez Consistency

		// Next Event
		context.logger.debug("Updating Followed Event")
		let _ = try await storeNextFollowedEvent(userID: userID, on: context.application)
		let _ = try await storeNextJoinedAppointment(userID: userID, on: context.application)
	}

	// Execute the job
	public func execute(context: QueueContext) async throws {
		context.logger.info("Starting UpdateRedisJob")
		do {
			let users = try await User.query(on: context.application.db).all()
			guard
				let ttUser = try await User.query(on: context.application.db).filter(\.$username == "TwitarrTeam")
					.first()
			else {
				throw Abort(
					.internalServerError,
					reason: "Could not find Twitarrteam user when running UpdateRedisJob."
				)
			}
			guard
				let modUser = try await User.query(on: context.application.db).filter(\.$username == "moderator")
					.first()
			else {
				throw Abort(
					.internalServerError,
					reason: "Could not find moderator user when running UpdateRedisJob."
				)
			}
			let privilegedUsers = PrivilegedUsers(ttUser: ttUser, modUser: modUser)
			for user in users {
				try await processUser(context, user: user, privilegedUsers: privilegedUsers)
			}
		}
		catch {
			context.logger.notice("UpdateRedisJob failed. \(String(reflecting: error))")
		}
		context.logger.info("Finished UpdateRedisJob")
	}
}

/// Job to fix Redis data inconsistencies run on a "cron" (and by "cron" I mean Vapor Queue).
public struct UpdateRedisJob: AsyncScheduledJob {
	public func run(context: QueueContext) async throws {
		try await UpdateRedisJobBase().execute(context: context)
	}
}

/// Job to fix Redis data inconsistencies run on demand.
public struct OnDemandUpdateRedisJob: AsyncJob, Sendable {
	public typealias Payload = EmptyJobPayload

	public func dequeue(_ context: QueueContext, _ payload: EmptyJobPayload) async throws {
		try await UpdateRedisJobBase().execute(context: context)
	}
}