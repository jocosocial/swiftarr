import Fluent
import FluentSQL
import Vapor

/// A `PersonalEvent` that a user has added to their calendar, and optionally invited
/// select users to also have in their calendars.
final class PersonalEvent: Model, Searchable, @unchecked Sendable {
	static let schema = "personal_event"

	// MARK: Properties

	/// The event's ID.
	@ID(key: .id) var id: UUID?

	/// The title of the event.
	@Field(key: "title") var title: String

	/// A description of the event.
	@Field(key: "description") var description: String?

	/// The start time of the event.
	@Field(key: "start_time") var startTime: Date

	/// The end time of the event.
	@Field(key: "end_time") var endTime: Date

	/// The location of the event.
	@Field(key: "location") var location: String?

	/// An ordered list of participants in the event. Newly joined members are
	// appended to the array, meaning this array stays sorted by join time.
	@Field(key: "participant_array") var participantArray: [UUID]

	/// Moderators can set several statuses on fezPosts that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Relations

	/// The `User` that created this `PersonalEvent`.
	@Parent(key: "owner") var owner: User

	// MARK: Initialization
	// Used by Fluent
	init() {}

	/// Initializes a new `PersonalEvent`.
	///
	/// - Parameters:
	///   - title: The title of the event.
	///   - description: A description of the event.
	///   - startTime: The start time of the event.
	///   - endTime: The end time of the event.
	///   - location: The location of the event.
	///   - owner: The ID of the owning user.
	init(
		title: String,
		description: String?,
		startTime: Date,
		endTime: Date,
		location: String?,
		owner: UUID
	) {
		self.startTime = startTime
		self.endTime = endTime
		self.title = title
		self.description = description
		self.location = location
		self.$owner.id = owner
		self.moderationStatus = .normal
		self.participantArray = []
	}

	init(_ data: PersonalEventContentData, cacheOwner: UserCacheData) {
		self.startTime = data.startTime
		self.endTime = data.endTime
		self.title = data.title
		self.description = data.description
		self.location = data.location
		self.$owner.id = cacheOwner.userID
		self.moderationStatus = .normal
		self.participantArray = data.participants
	}
}

// PersonalEvents can be reported.
extension PersonalEvent: Reportable {
	/// The report type for `PersonalEvent` reports.
	var reportType: ReportType { .personalEvent }
	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $owner.id }

	/// No auto quarantine for PersonalEvents.
	var autoQuarantineThreshold: Int { Int.max }
}

struct CreatePersonalEventSchema: AsyncMigration {
	static let schema = "personal_event"
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema(CreatePersonalEventSchema.schema)
			.id()
			.field("title", .string, .required)
			.field("description", .string)
			.field("start_time", .datetime, .required)
			.field("end_time", .datetime, .required)
			.field("location", .string)
			.field("mod_status", modStatusEnum, .required)
			.field("participant_array", .array(of: .uuid), .required)
			.field("owner", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			.create()

		if let sqlDatabase = database as? SQLDatabase {
			try await sqlDatabase.raw(
				"""
				ALTER TABLE \(unsafeRaw: CreatePersonalEventSchema.schema)
				ADD COLUMN IF NOT EXISTS fulltext_search tsvector
					GENERATED ALWAYS AS (to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, ''))) STORED;
				"""
			)
			.run()
			try await sqlDatabase.raw(
				"""
				CREATE INDEX IF NOT EXISTS idx_\(unsafeRaw: CreatePersonalEventSchema.schema)_search
				ON \(ident: CreatePersonalEventSchema.schema)
				USING GIN
				(fulltext_search)
				"""
			)
			.run()
		}
	}

	func revert(on database: Database) async throws {
		try await database.schema(CreatePersonalEventSchema.schema).delete()
	}
}
