import Fluent
import Queues
import Vapor

// Holder for the UUIDs of the privileged mailbox phantom accounts, keyed by `PrivilegedMailbox.user`.
// A mailbox whose phantom account hasn't been seeded on this instance yet (e.g. a newly-added
// mailbox before its migration has run) is simply absent--`processUser` skips it rather than
// failing the whole job.
typealias PrivilegedUserIDs = [PrivilegedUser: UUID]

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
	func processUser(_ context: QueueContext, user: User, privilegedUserIDs: PrivilegedUserIDs) async throws {
		let userID = try user.requireID()
		context.logger.debug("\(userID)")
		// Fez Consistency
		let userFezParticipants = try await FezParticipant.query(on: context.application.db)
			.with(\.$fez)
			.filter(\.$user.$id == userID)
			.all()
		context.logger.debug("User is part of \(userFezParticipants.count) chats")
		try await self.processChatParticipants(context, chatParticipants: userFezParticipants, userID: userID)

		// Privileged mailbox read tracking is now per-user, but we find each mailbox's fezzes via its
		// phantom account's FezParticipants. Build a lookup so we can substitute the actual user's
		// readCount where they have their own FezParticipant (from being a direct member or
		// having previously viewed the fez). Without this, the phantom account's stale readCount
		// would cause the job to incorrectly mark conversations as unread.
		let userParticipantsByFez: [UUID: FezParticipant] = Dictionary(
			uniqueKeysWithValues: userFezParticipants.map { ($0.$fez.id, $0) }
		)

		// Privileged Mailboxes. Figure out which mailboxes this user can see, then fetch every applicable
		// phantom account's FezParticipants in one query (rather than one query per mailbox) and partition
		// the results in memory, so adding more mailboxes (see #517) doesn't add more round trips per user.
		let userRoles = Set(user.roles.map { $0.role })
		let applicableMailboxes = PrivilegedMailbox.all.compactMap { mailbox -> (PrivilegedMailbox, UUID)? in
			guard mailbox.requirement.isSatisfied(accessLevel: user.accessLevel, roles: userRoles),
				let phantomID = privilegedUserIDs[mailbox.user]
			else {
				return nil
			}
			return (mailbox, phantomID)
		}
		if !applicableMailboxes.isEmpty {
			let allMailboxFezParticipants = try await FezParticipant.query(on: context.application.db)
				.with(\.$fez)
				.filter(\.$user.$id ~~ applicableMailboxes.map { $0.1 })
				.all()
			let participantsByPhantomID = Dictionary(grouping: allMailboxFezParticipants, by: { $0.$user.id })
			for (mailbox, phantomID) in applicableMailboxes {
				// Prefer the user's own FezParticipant over the phantom account's when available.
				let resolvedParticipants = (participantsByPhantomID[phantomID] ?? []).map { phantomParticipant -> FezParticipant in
					if let userParticipant = userParticipantsByFez[phantomParticipant.$fez.id] {
						return userParticipant
					}
					return phantomParticipant
				}
				context.logger.debug("User is part of \(resolvedParticipants.count) \(mailbox.user.rawValue) chats")
				try await self.processChatParticipants(
					context,
					chatParticipants: resolvedParticipants,
					userID: userID,
					overrideInbox: mailbox.inbox
				)
			}
		}
		// We don't have separate mailbox information for THO user
		// End Fez Consistency

		// Next Event
		context.logger.debug("Updating Followed Event")
		let _ = try await storeNextFollowedEvent(userID: userID, on: context.application)
		let _ = try await storeNextJoinedAppointment(userID: userID, on: context.application)
	}

	// Resolves the UUID of each mailbox's phantom account from `phantomUsers`. A mailbox whose phantom
	// account isn't present (e.g. it hasn't been seeded on this instance yet) is logged and omitted
	// rather than failing the whole job--see issue #628.
	static func resolvePrivilegedUserIDs(from phantomUsers: [User], logger: Logger) throws -> PrivilegedUserIDs {
		var privilegedUserIDs: PrivilegedUserIDs = [:]
		for mailbox in PrivilegedMailbox.all {
			guard let phantom = phantomUsers.first(where: { $0.username == mailbox.user.rawValue }) else {
				logger.warning(
					"Could not find \(mailbox.user.rawValue) user when running UpdateRedisJob; skipping that mailbox."
				)
				continue
			}
			privilegedUserIDs[mailbox.user] = try phantom.requireID()
		}
		return privilegedUserIDs
	}

	// Execute the job
	public func execute(context: QueueContext) async throws {
		context.logger.info("Starting UpdateRedisJob")
		do {
			let users = try await User.query(on: context.application.db).with(\.$roles).all()
			let phantomUsers = try await User.query(on: context.application.db)
				.filter(\.$username ~~ PrivilegedMailbox.all.map { $0.user.rawValue })
				.all()
			let privilegedUserIDs = try Self.resolvePrivilegedUserIDs(from: phantomUsers, logger: context.logger)
			for user in users {
				try await processUser(context, user: user, privilegedUserIDs: privilegedUserIDs)
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