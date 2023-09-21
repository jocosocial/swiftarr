import Fluent
import Vapor

/// `ScheduleLog` records changes made to the events in the schedule, both by manual schedule updates (done by uploading a .ics file) and 
/// automatic schedule updates (where the server periodically queries Sched.com and applies changes automatically).
///
final class ScheduleLog: Model {
	static let schema = "schedulelog"

// MARK: Properties

	/// The edit's ID.
	@ID(custom: "id") var id: Int?

	/// TRUE if this update was started automatically by the server. The server is currently set up to use Queues to query Sched.com once per hour
	/// and automatically apply any schedule updates to our db. FALSE if this was a manual update.
	@Field(key: "automatic_update") var automaticUpdate: Bool

	/// The total number of changes between the existing db and the new schedule information. May be > than the number of events modified as it may
	/// count a time and location change to a single event as 2 changes.
	@Field(key: "change_count") var changeCount: Int

	/// The JSON built from the `EventUpdateDifferenceData`, describing what changed. Will be nil if there was an error
	/// or if this was an automatic schedule update check and nothing changed.
	@OptionalField(key: "difference_data") var differenceData: Data?

	/// If this was an automated schedule update and it failed, the failure reason.
	@OptionalField(key: "error_result") var errorResult: String?

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new ScheduleLog for a successful update event.
	///
	/// - Parameters:
	///   - diff: The changes between the old and new schedule. Pass in NIL if there we no changes.
	///   - isAutomatic: TRUE if this update was done by the automatic Queues system.
	init(diff: EventUpdateDifferenceData?, isAutomatic: Bool) throws {
		self.automaticUpdate = isAutomatic
		changeCount = 0
		if let diff = diff {
			changeCount = diff.createdEvents.count + diff.deletedEvents.count + diff.locationChangeEvents.count +
					diff.timeChangeEvents.count + diff.minorChangeEvents.count
			if changeCount > 0 {
				differenceData = try JSONEncoder().encode(diff)
			}
		}
	}
	
	/// Initializes a new ScheduleLog that reports an error indicating the schedule update did not complete.
	///
	/// - Parameters:
	///   - diff: The changes between the old and new schedule..
	init(error: Error) throws {
		self.automaticUpdate = true			// Manual updates don't log failures, as they can report the failure directly to the admin.
		errorResult = error.localizedDescription
		changeCount = 0
	}
}

struct CreateScheduleLogSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("schedulelog")
			.field("id", .int, .identifier(auto: true))
			.field("automatic_update", .bool, .required)
			.field("change_count", .int64, .required)
			.field("difference_data", .data)
			.field("error_result", .string)
			.field("created_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("profileedit").delete()
	}
}
