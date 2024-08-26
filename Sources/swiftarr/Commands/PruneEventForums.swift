import Fluent
import Foundation
import Vapor

struct PruneEventForumsCommand: AsyncCommand {
	struct Signature: CommandSignature {}

	var help: String {
		"""
		Delete forum threads for events from past schedules. For example, if your server was
		started with a schedule from 2023 and you imported 2024, you would continue to see forum
		threads for the 2023 events in the relevant forum categories.
		"""
	}

	func run(using context: CommandContext, signature: Signature) async throws {
		context.application.logger.info("Pruning deleted event forums")
        try await findEvents(on: context.application)
        // @TODO update category counts
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
                    group.addTask {
                        app.logger.info("Deleting forum: \(forum.title)")
                        try await forum.delete(on: database)
                    }
                }
            }
        }
	}
}
