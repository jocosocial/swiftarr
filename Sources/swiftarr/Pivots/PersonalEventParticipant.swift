import Fluent
import Foundation

/// A `Pivot` holding a siblings relation between `User` and `PersonalEvent`.

final class PersonalEventParticipant: Model {
	static let schema = "personal_event+participants"

    // MARK: Properties

    /// The ID of the pivot.
	@ID(key: .id) var id: UUID?

    // MARK: Relationships

    /// The associated `User` who is a participant of the `PersonalEvent`.
	@Parent(key: "user") var user: User

    /// The associated `PersonalEvent` which the `User` is a participant of.
	@Parent(key: "personal_event") var personalEvent: PersonalEvent

    // MARK: Initialization
	// Used by Fluent
	init() {}

    /// Initializes a new `PersonalEventParticipant` pivot.
	///
	/// - Parameters:
	///   - userID: The left hand `User` model.
	///   - event: The right hand `PersonalEvent` model.
	init(_ userID: UUID, _ event: PersonalEvent) throws {
		self.$user.id = userID
        self.$personalEvent.id = try event.requireID()
        self.$personalEvent.value = event
	}
}

struct CreatePersonalEventParticipantSchema: AsyncMigration {
    // Reminder that migrations should not reference the MyModel.schema above
    // because we could want to change it later and we want migrations to be
    // idempotent. It's fine to duplicate it down here though!
    static let schema = "personal_event+participants"
    
	func prepare(on database: Database) async throws {
		try await database.schema(CreatePersonalEventParticipantSchema.schema)
			.id()
			.unique(on: "user", "personal_event")
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("personal_event", .uuid, .required, .references("personal_event", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema(CreatePersonalEventParticipantSchema.schema).delete()
	}
}