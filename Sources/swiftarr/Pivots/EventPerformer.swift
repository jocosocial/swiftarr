import Fluent
import Vapor


final class EventPerformer: Model {
	static let schema = "event+performer"

	/// The pivot's ID.
	@ID(key: .id) var id: UUID?

	@Parent(key: "performer") var performer: Performer
	
	@Parent(key: "event") var event: Event

	// MARK: Initialization

	// Used by Fluent
	init() {}
	
	/// Initializes a new EventPerformer
	/// 
	/// - Parameters:
	///   - event: An Event saved in the database.
	///   - performer: A Performer saved in the database.
	init(event: Event, performer: Performer) throws {
		self.$event.id = try event.requireID()
		self.$performer.id = try performer.requireID()
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
