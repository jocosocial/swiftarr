import Fluent
import Vapor


final class EventPerformer: Model {
	static let schema = "event+performer"

	/// The pivot's ID.
	@ID(key: .id) var id: UUID?

	@Parent(key: "performer") var performer: Performer
	
	@Parent(key: "event") var event: Event
}

struct CreateEventPerformerSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("event+performer")
			.id()
			.field("performer", .uuid, .required, .references("performer", "id"))
			.field("event", .uuid, .required, .references("event", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("event+performer").delete()
	}
}
