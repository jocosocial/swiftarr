import Fluent
import Vapor


final class EventPerformer: Model, @unchecked Sendable {
	static let schema = "event+performer"

	/// The pivot's ID.
	@ID(key: .id) var id: UUID?

	@Parent(key: "performer") var performer: Performer
	
	@Parent(key: "event") var event: Event

	/// TRUE if a TwitarrTeam member linked this performer to this event by hand. The spreadsheet link import replaces
	/// the pivots it created, but leaves manually-linked pivots alone.
	@Field(key: "manually_linked") var manuallyLinked: Bool

	// MARK: Initialization

	// Used by Fluent
	init() {
		self.manuallyLinked = false
	}
	
	/// Initializes a new EventPerformer
	/// 
	/// - Parameters:
	///   - event: An Event saved in the database.
	///   - performer: A Performer saved in the database.
	///   - manuallyLinked: TRUE if this link was made by hand rather than imported.
	init(event: Event, performer: Performer, manuallyLinked: Bool = false) throws {
		self.$event.id = try event.requireID()
		self.$performer.id = try performer.requireID()
		self.manuallyLinked = manuallyLinked
	}
}



struct CreateEventPerformerSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("event+performer")
			.id()
			.field("performer", .uuid, .required, .references("performer", "id"))
			.field("event", .uuid, .required, .references("event", "id"))
			.unique(on: "performer", "event")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("event+performer").delete()
	}
}

struct AddEventPerformerManuallyLinkedMigration: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("event+performer")
			.field("manually_linked", .bool, .required, .sql(.default(false)))
			.update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("event+performer")
			.deleteField("manually_linked")
			.update()
	}
}
