import Fluent
import Vapor

/// A `PersonalEvent` that a user has added to their calendar, and optionally invited
/// select users to also have in their calendars.
final class PersonalEvent: Model, Searchable {
	static let schema = "personal_event"

    // MARK: Properties

	/// The event's ID.
	@ID(key: .id) var id: UUID?
 
    /// The title of the event.
	@Field(key: "title") var title: String
 
    /// A description of the event.
	@Field(key: "description") var description: String
 
    /// The start time of the event.
	@Field(key: "startTime") var startTime: Date
 
    /// The end time of the event.
	@Field(key: "endTime") var endTime: Date

    /// The location of the event.
	@Field(key: "location") var location: String

    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

    /// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

    /// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

    // MARK: Relations

    /// The `Us
    /// er` that created this `PersonalEvent`.
	@Parent(key: "owner") var owner: User

    /// The participants in this `PersonalEvent`.
	@Siblings(through: PersonalEventParticipant.self, from: \.$personalEvent, to: \.$user) var participants: [User]

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
	///   - uid: The event's sched.com identifier.
	init(
		title: String,
		description: String,
        startTime: Date,
		endTime: Date,
		location: String,
        owner: UUID
	) {
		self.startTime = startTime
		self.endTime = endTime
		self.title = title
		self.description = description
		self.location = location
        self.$owner.id = owner
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

// @TODO searchable