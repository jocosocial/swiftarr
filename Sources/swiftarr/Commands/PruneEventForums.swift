import Fluent
import Foundation
import Vapor

/// Prune Old Event Forums
/// 
/// In long-lived Swiftarr instances such as the Beta, we typically do not reset
/// the database between sailings. As we accumulate years of events, the amount
/// of forums starts to grow unweildy. The old events are marked as deleted and
/// removed from the schedule, but the forums remain. This backend command is
/// intended to be executed by an operator in one of these long-lived environments
/// to soft-delete all forums that are linked to soft-deleted events.
/// 
/// The effects of this command can be reversed by importing the deleted schedule
/// again which will restore the events and their associated forums (thanks, 
/// soft-delete).
///
struct PruneEventForumsCommand: AsyncCommand {
	struct Signature: CommandSignature {}

	var help: String {
		"""
		Delete forum threads for events from past schedules. For example, if your server was
		started with a schedule from 2023 and you imported 2024, you would continue to see forum
		threads for the 2023 events in the relevant forum categories until running this command.
		"""
	}

	func run(using context: CommandContext, signature: Signature) async throws {
		context.application.logger.info("Pruning deleted event forums")
        try await findEvents(on: context.application)
        try await updateCategoryCounts(on: context.application)
        context.application.logger.info("Complete!")
	}

	private func findEvents(on app: Application) async throws {
        // Count the number of deleted events.
        let deletedEventCount = try await Event.query(on: app.db)
            .withDeleted()
            .filter(\.$deletedAt != nil)
            .count()
        app.logger.info("Found \(deletedEventCount) deleted events in the database.")

        // Count the number of active event forums.
        let activeEventForums = try await Forum.query(on: app.db)
            .join(child: \.$scheduleEvent, method: .left)
            .with(\.$scheduleEvent)
            .filter(Event.self, \.$deletedAt == nil)
            .all()
        app.logger.info("Found \(activeEventForums.count) active event forums.")

        // Count the number of deleted event forums. This should match the deleted 
        // event count from above.
        let deletedEventForums = try await Forum.query(on: app.db)
            .join(child: \.$scheduleEvent, method: .left)
            .with(\.$scheduleEvent)
            .filter(Event.self, \.$deletedAt != nil)
            .withDeleted()
            .all()
        app.logger.info("Found \(deletedEventForums.count) deleted event forums")

        // Actually delete them now.
        try await app.db.transaction { database in 
            await withThrowingTaskGroup(of: Void.self) { group in
                for forum in deletedEventForums {
                    guard forum.deletedAt == nil else {
                        app.logger.info("Skipping previously deleted forum: \(forum.title)")
                        continue
                    }
                    group.addTask {
                        app.logger.info("Deleting forum: \(forum.title)")
                        try await forum.delete(on: database)
                    }
                }
            }
        }
	}

    private func updateCategoryCounts(on app: Application) async throws {
        let categories = try await Category.query(on: app.db)
            .filter(\.$isEventCategory == true)
            .with(\.$forums)
            .all()

        await withThrowingTaskGroup(of: Void.self) { group in
            categories.forEach { category in
                group.addTask {
                    let newCount = Int32(category.forums.count)
                    app.logger.info("Adjusting count for category \(category.title): \(category.forumCount) -> \(newCount)")
                    category.forumCount = newCount;
                    try await category.save(on: app.db)
                }
            }
        }
    }
}
