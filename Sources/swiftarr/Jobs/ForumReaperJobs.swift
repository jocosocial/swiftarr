import Fluent
import Queues
import Vapor

/// Base class for the EmptyForumReaper job. This is common between the AsyncScheduledJob
/// and AsyncJob.
class EmptyForumReaperJobBase {
	static func execute(context: QueueContext) async throws {
		context.logger.notice("Starting EmptyForumReaper job")
		
		// Get all forums that are not soft-deleted
		let allForums = try await Forum.query(on: context.application.db)
			.filter(\.$deletedAt == nil)
			.all()
		
		context.logger.info("Found \(allForums.count) active forums to check")
		
		var deletedCount = 0
		var deletedForumIDs: [UUID] = []
		
		// Get admin user for moderator logging
		guard let adminUser = try await User.query(on: context.application.db)
			.filter(\.$username == PrivilegedUser.admin.rawValue)
			.first()
		else {
			throw Abort(
				.internalServerError,
				reason: "Could not find admin user when running EmptyForumReaper job."
			)
		}
		
		// Check each forum for posts
		for forum in allForums {
			let forumID = try forum.requireID()
			
			// Count non-deleted posts for this forum
			let postCount = try await ForumPost.query(on: context.application.db)
				.filter(\.$forum.$id == forumID)
				.filter(\.$deletedAt == nil)
				.count()
			
			if postCount == 0 {
				// Soft delete the forum
				try await forum.delete(on: context.application.db)
				deletedCount += 1
				deletedForumIDs.append(forumID)
				
				context.logger.info("Deleted empty forum: \(forumID) - '\(forum.title)'")
				
				// Log to moderator log
				do {
					let modAction = try ModeratorAction(
						content: forum,
						action: .delete,
						moderator: adminUser
					)
					try await modAction.save(on: context.application.db)
				} catch {
					// Log error but don't fail the job
					context.logger.warning("Failed to log moderator action for forum \(forumID): \(String(reflecting: error))")
				}
			}
		}
		
		if deletedCount > 0 {
			context.logger.notice("EmptyForumReaper completed: deleted \(deletedCount) empty forum(s). Forum IDs: \(deletedForumIDs.map { $0.uuidString }.joined(separator: ", "))")
		} else {
			context.logger.notice("EmptyForumReaper completed: no empty forums found")
		}
	}
}

/// Job to delete empty forums on a "cron" (and by "cron" I mean Vapor Queue).
public struct EmptyForumReaperJob: AsyncScheduledJob {
	public func run(context: QueueContext) async throws {
		try await EmptyForumReaperJobBase.execute(context: context)
	}
}

/// Job to delete empty forums on demand.
public struct OnDemandEmptyForumReaperJob: AsyncJob, Sendable {
	public typealias Payload = EmptyJobPayload

	public func dequeue(_ context: QueueContext, _ payload: EmptyJobPayload) async throws {
		try await EmptyForumReaperJobBase.execute(context: context)
	}
}

