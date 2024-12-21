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
public struct UpdateRedisJob: AsyncScheduledJob, APICollection {
	// Looks at all Chats (Fezzes) that a user is a part of and calculates any unreads.
	// Or clears any unreads if none exist.
	func processChatParticipants(
		_ context: QueueContext,
		chatParticipants: [FezParticipant],
		userID: UUID,
		overrideInbox: MailInbox? = nil
	) async throws {
		try await withThrowingTaskGroup(of: Void.self) { group in
			for participant in chatParticipants {
				let chatID = try participant.fez.requireID()
				let unreadCount = participant.fez.postCount - participant.readCount
				let inbox = overrideInbox ?? MailInbox.mailboxForChatType(type: participant.fez.fezType)
				// Adding {chatID: 0} to the Unread hash is counted as a conversation with
				// unread messages, so we need to avoid adding any with an unreadCount of 0.
				guard unreadCount != 0 else {
					continue
				}
				group.addTask {
					try await context.application.redis.setChatUnreadCount(
						unreadCount,
						chatID: chatID,
						userID: userID,
						inbox: inbox
					)
				}
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
		try await context.application.redis.clearChatUnreadCounts(userID: userID, inbox: MailInbox.seamail)
		try await context.application.redis.clearChatUnreadCounts(userID: userID, inbox: MailInbox.lfgMessages)
		try await context.application.redis.clearChatUnreadCounts(userID: userID, inbox: MailInbox.privateEvent)
		try await self.processChatParticipants(context, chatParticipants: userFezParticipants, userID: userID)

		// Privileged Users
		if user.accessLevel.hasAccess(.twitarrteam) {
			let ttFezParticipants = try await FezParticipant.query(on: context.application.db)
				.with(\.$fez)
				.filter(\.$user.$id == privilegedUsers.ttUser.requireID())
				.all()
			context.logger.debug("User is part of \(ttFezParticipants.count) TwitarrTeam chats")
			try await context.application.redis.clearChatUnreadCounts(
				userID: userID,
				inbox: MailInbox.twitarrTeamSeamail
			)
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
			try await context.application.redis.clearChatUnreadCounts(
				userID: userID,
				inbox: MailInbox.moderatorSeamail
			)
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
	public func run(context: QueueContext) async throws {
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
