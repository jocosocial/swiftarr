import Fluent
import Queues
import Vapor

public struct UpdateRedisJob: AsyncScheduledJob {
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
        print("There are \(users.count) users")
        guard let ttUser = try await User.query(on: context.application.db).filter(\.$username == "TwitarrTeam").first() else {
            throw Abort(
						.internalServerError,
						reason: "Could not find Twitarrteam user when running UpdateRedisJob."
					)
        }
        guard let modUser = try await User.query(on: context.application.db).filter(\.$username == "moderator").first() else {
            throw Abort(
						.internalServerError,
						reason: "Could not find moderator user when running UpdateRedisJob."
					)
        }
        for user in users {
            let userID = try user.requireID()
            context.logger.info("Processing user \(userID) :: \(user.username)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                let userFezParticipants = try await FezParticipant.query(on: context.application.db)
                    .with(\.$fez)
                    .filter(\.$user.$id == userID)
                    .all()
                // User Fezzes
                context.logger.info("User is part of \(userFezParticipants.count) chats")
                for fezParticipant in userFezParticipants {
                    let chatID = try fezParticipant.fez.requireID()
                    context.logger.info("Looking at chat \(chatID) :: \(fezParticipant.fez.fezType)")
                    let unreadCount = fezParticipant.fez.postCount - fezParticipant.readCount
                    context.logger.info("Unread Count: \(unreadCount)")
                    let inbox = MailInbox.mailboxForChatType(type: fezParticipant.fez.fezType)
                    group.addTask {
                        try await context.application.redis.setChatUnreadCount(unreadCount, chatID: chatID, userID: userID, inbox: inbox)
                    }
                }
                // Privileged Users
                if user.accessLevel.hasAccess(.twitarrteam) {
                    let inbox = MailInbox.twitarrTeamSeamail
                    let ttFezParticipants = try await FezParticipant.query(on: context.application.db)
                        .with(\.$fez)
                        .filter(\.$user.$id == ttUser.requireID())
                        .all()
                    context.logger.info("User \(userID) has twitarrteam count \(ttFezParticipants.count) chats")
                    try await context.application.redis.clearChatUnreadCounts(userID: userID, inbox: inbox)
                    for ttFezParticipant in ttFezParticipants {
                        let chatID = try ttFezParticipant.fez.requireID()
                        context.logger.info("Looking at chat \(chatID) :: \(ttFezParticipant.fez.fezType)")
                        let unreadCount = ttFezParticipant.fez.postCount - ttFezParticipant.readCount
                        context.logger.info("Unread Count: \(unreadCount)")
                        group.addTask {
                            try await context.application.redis.setChatUnreadCount(unreadCount, chatID: chatID, userID: userID, inbox: inbox)
                        }
                    }
                }
                context.logger.info("Done with chats")
            }
        }
        context.logger.info("Finished UpdateRedisJob")
    }
}