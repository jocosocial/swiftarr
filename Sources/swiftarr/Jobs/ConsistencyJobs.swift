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
        for user in users {
            let userID = try user.requireID()
            context.logger.info("Processing user \(userID) :: \(user.username)")
            try await withThrowingTaskGroup(of: Void.self) { group in
                let fezParticipants = try await FezParticipant.query(on: context.application.db)
                // .join(FriendlyFez.self, on: \FezParticipant.$fez.$id == \FriendlyFez.$id)
                .with(\.$fez)
                .filter(\.$user.$id == userID)
                .all()
                context.logger.info("User is part of \(fezParticipants.count) chats")
                for fezParticipant in fezParticipants {
                    let chatID = try fezParticipant.fez.requireID()
                    context.logger.info("Looking at chat \(chatID) :: \(fezParticipant.fez.fezType)")
                    let unreadCount = fezParticipant.fez.postCount - fezParticipant.readCount
                    context.logger.info("Unread Count: \(unreadCount)")
                    let inbox = MailInbox.mailboxForChatType(type: fezParticipant.fez.fezType)
                    group.addTask {
                        try await context.application.redis.setUnreadCount(unreadCount, chatID: chatID, userID: userID, inbox: inbox)
                    }
                }
                context.logger.info("Done with chats")
            }
        }
        context.logger.info("Finished UpdateRedisJob")
    }
}