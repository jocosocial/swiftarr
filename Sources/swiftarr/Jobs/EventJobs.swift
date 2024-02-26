import Fluent
import Queues
import Vapor

/// AsyncJobs require a payload, and apparently we can't just shove Codable at it.
/// So this struct exists in case the job ever decides to need runtime parameters.
public struct EmptyJobPayload: Codable {}

/// Base class for the Sched schedule update job. This is common between the AsyncScheduledJob
/// and AsyncJob.
class UpdateScheduleJobBase {
	static func execute(context: QueueContext) async throws {
		do {
			context.logger.notice("Starting UpdateScheduleJob")
			let scheduleURLString = Settings.shared.scheduleUpdateURL
			guard !scheduleURLString.isEmpty else {
				throw Abort(
					.internalServerError,
					reason: "Schedule Updater ran, but the URL is empty, so we're bailing."
				)
			}
			let scheduleURL = URI(string: Settings.shared.scheduleUpdateURL)
			let userAgent =
				"Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
			let response = try await context.application.client.get(scheduleURL, headers: ["User-Agent": userAgent])
			guard response.status == .ok else {
				throw Abort(
					.internalServerError,
					reason:
						"Failed to GET schedule data from \(String(reflecting: scheduleURL)) got response \(response.status.code)"
				)
			}
			guard let fileLen = response.body?.readableBytes,
				let scheduleFileStr = response.body?.getString(at: 0, length: fileLen)
			else {
				throw Abort(.badRequest, reason: "Could not read schedule data.")
			}
			// Parse and validate, throw if >50 events deleted (require manual in this case)
			let differences = try await EventParser().validateEventsInICS(scheduleFileStr, on: context.application.db)
			if differences.deletedEvents.count > 50 {
				throw Abort(
					.badRequest,
					reason:
						"This update deletes more than 50 events and should be done manually, not via automatic updating."
				)
			}
			if differences.deletedEvents.isEmpty && differences.createdEvents.isEmpty
				&& differences.timeChangeEvents.isEmpty && differences.locationChangeEvents.isEmpty
				&& differences.minorChangeEvents.isEmpty
			{
				// Log that no change was needed
				try await ScheduleLog(diff: nil, isAutomatic: true).save(on: context.application.db)
				context.logger.notice(
					"UpdateScheduleJob completed successfully. Source schedule hasn't changed, no updates to apply."
				)
			}
			else {
				// Apply changes to db, log what happened
				guard let forumAuthor = context.application.getUserHeader("admin") else {
					throw Abort(
						.internalServerError,
						reason: "Could not find admin user when running schedule updater."
					)
				}
				try await EventParser()
					.updateDatabaseFromICS(scheduleFileStr, on: context.application.db, forumAuthor: forumAuthor)
				try await ScheduleLog(diff: differences, isAutomatic: true).save(on: context.application.db)
				context.logger.notice("UpdateScheduleJob completed successfully--there were updates to apply.")
			}
		}
		catch {
			context.logger.notice("UpdateScheduleJob failed. \(String(reflecting: error))")
			try await ScheduleLog(error: error).save(on: context.application.db)
		}
	}
}

/// Job to update the Sched schedule on a "cron" (and by "cron" I mean Vapor Queue).
public struct UpdateScheduleJob: AsyncScheduledJob {
	public func run(context: QueueContext) async throws {
		try await UpdateScheduleJobBase.execute(context: context)
	}
}

/// Job to update the Sched schedule on demand.
public struct UpdateJob: AsyncJob {
	public typealias Payload = EmptyJobPayload

	public func dequeue(_ context: QueueContext, _ payload: EmptyJobPayload) async throws {
		try await UpdateScheduleJobBase.execute(context: context)
	}
}

/// Job to push socket notifications of an upcoming event on a "cron" (and by "cron" I mean Vapor Queue).
public struct UserEventNotificationJob: AsyncScheduledJob {
	func processEvents(_ context: QueueContext) async throws {
		// Events are managed in the Port Time Zone
		let portCalendar = Settings.shared.getPortCalendar()
		let filterStartTime = portCalendar.date(
			byAdding: .second,
			value: Int(Settings.shared.upcomingEventNotificationSeconds),
			to: Settings.shared.getDateInCruiseWeek()
		)!

		let upcomingEvents = try await Event.query(on: context.application.db)
			.with(\.$favorites)
			.filter(\.$startTime == filterStartTime)
			.all()

		for event in upcomingEvents {
			let eventID = try event.requireID()
			let favoriteUserIDs = try event.favorites.map { try $0.requireID() }
			let infoStr = "\(event.title) is starting Soon™ in \(event.location)."
			context.application.websocketStorage.forwardToSockets(
				users: favoriteUserIDs,
				type: .followedEventStarting(eventID),
				info: infoStr
			)
		}
	}

	// This is sufficiently complex enough to merit its own function. Unlike the Settings.shared.getDateInCruiseWeek(),
	// just adding .seconds to Date() isn't enough because Date() returns millisecond-precision. Which no one tells you
	// unless you do a .timeIntervalSince1970 and get the actual Double value back to look at what's behind the dot.
	// I'm totally not salty about spending several hours chasing this down. Anywho...
	// This takes the current Date(), strips the ultra-high-precision that we don't want, and returns Date() with the
	// upcoming notification offset applied.
	func getFezFilterDate() -> Date {
		let portCalendar = Settings.shared.getPortCalendar()
		let todayDate = Date()
		let todayCalendar = Settings.shared.calendarForDate(todayDate)
		let todayComponents = todayCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: todayDate)
		return portCalendar.date(
			byAdding: .second,
			value: Int(Settings.shared.upcomingEventNotificationSeconds),
			to: todayCalendar.date(from: todayComponents)!
		)!
	}

	func processFezzes(_ context: QueueContext) async throws {
		let upcomingFezzes = try await FriendlyFez.query(on: context.application.db)
			.filter(\.$startTime == getFezFilterDate())
			.filter(\.$fezType !~ [.open, .closed])
			.all()
		for fez in upcomingFezzes {
			let fezID = try fez.requireID()
			var infoStr = "\(fez.title) is starting Soon™"
			if let location = fez.location {
				infoStr += " in \(location)."
			}
			context.application.websocketStorage.forwardToSockets(
				users: fez.participantArray,
				type: .joinedLFGStarting(fezID),
				info: infoStr
			)
		}
	}

	public func run(context: QueueContext) async throws {
		context.logger.info("Running UserEventNotificationJob")
		try await processEvents(context)
		try await processFezzes(context)
	}
}
