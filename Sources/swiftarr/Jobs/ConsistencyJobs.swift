import Fluent
import Queues
import Vapor

struct PrivilegedUsers {
	var ttUser: User
	var modUser: User

	init(ttUser: User, modUser: User) {
		self.ttUser = ttUser
		self.modUser = modUser
	}
}

public struct UpdateRedisJob: AsyncScheduledJob, APICollection {
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

	func processUser(_ context: QueueContext, user: User, privilegedUsers: PrivilegedUsers) async throws {
		let userID = try user.requireID()
		context.logger.info("Processing user \(userID)")
		// Fez Consistency
		let userFezParticipants = try await FezParticipant.query(on: context.application.db)
			.with(\.$fez)
			.filter(\.$user.$id == userID)
			.all()
		context.logger.info("User is part of \(userFezParticipants.count) chats")
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
			context.logger.info("User is part of \(ttFezParticipants.count) TwitarrTeam chats")
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
			context.logger.info("User is part of \(modFezParticipants.count) moderator chats")
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
		context.logger.info("Updating Followed Event")
		let _ = try await storeNextFollowedEvent(userID: userID, on: context.application)
	}

	public func run(context: QueueContext) async throws {
		// try await UpdateScheduleJobBase.execute(context: context)
		context.logger.info("Starting UpdateRedisJob")
		// do {
		// }
		// catch {
		// 	context.logger.notice("UpdateScheduleJob failed. \(String(reflecting: error))")
		// 	try await ScheduleLog(error: error).save(on: context.application.db)
		// }
		let users = try await User.query(on: context.application.db).all()
		guard let ttUser = try await User.query(on: context.application.db).filter(\.$username == "TwitarrTeam").first()
		else {
			throw Abort(
				.internalServerError,
				reason: "Could not find Twitarrteam user when running UpdateRedisJob."
			)
		}
		guard let modUser = try await User.query(on: context.application.db).filter(\.$username == "moderator").first()
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
		context.logger.info("Finished UpdateRedisJob")
	}
}
