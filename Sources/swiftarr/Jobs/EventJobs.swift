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
                throw Abort(.internalServerError, reason: "Schedule Updater ran, but the URL is empty, so we're bailing.")
            }
            let scheduleURL = URI(string: Settings.shared.scheduleUpdateURL)
            let userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
            let response = try await context.application.client.get(scheduleURL, headers: [ "User-Agent" : userAgent])
            guard response.status == .ok else {
                throw Abort(.internalServerError, reason: "Failed to GET schedule data from \(String(reflecting: scheduleURL)) got response \(response.status.code)")
            }
            guard let fileLen = response.body?.readableBytes, let scheduleFileStr = response.body?.getString(at: 0, length: fileLen) else {
                throw Abort(.badRequest, reason: "Could not read schedule data.")
            }
            // Parse and validate, throw if >50 events deleted (require manual in this case)
            let differences = try await EventParser().validateEventsInICS(scheduleFileStr, on: context.application.db)
            if differences.deletedEvents.count > 50 {
                throw Abort(.badRequest, reason: "This update deletes more than 50 events and should be done manually, not via automatic updating.")
            }
            if differences.deletedEvents.isEmpty && differences.createdEvents.isEmpty && differences.timeChangeEvents.isEmpty &&
                    differences.locationChangeEvents.isEmpty && differences.minorChangeEvents.isEmpty {
                // Log that no change was needed
                try await ScheduleLog(diff: nil, isAutomatic: true).save(on: context.application.db)
                context.logger.notice("UpdateScheduleJob completed successfully. Source schedule hasn't changed, no updates to apply.")
            }
            else {
                // Apply changes to db, log what happened
                guard let forumAuthor = context.application.getUserHeader("admin") else {
                    throw Abort(.internalServerError, reason: "Could not find admin user when running schedule updater.")
                }
                try await EventParser().updateDatabaseFromICS(scheduleFileStr, on: context.application.db, forumAuthor: forumAuthor)
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

    public func dequeue(_ context: QueueContext,  _ payload: EmptyJobPayload) async throws {
        try await UpdateScheduleJobBase.execute(context: context)
    }
}