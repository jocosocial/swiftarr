import Fluent
import Vapor

final class Performer: Model {
	static let schema = "performer"
	
	@ID(key: .id) var id: UUID?
	
	/// Individual or band
	@Field(key: "name") var name: String
	
	/// Bio strings often have links, and may have HTML?
	@OptionalField(key: "bio") var bio: String?
	
	/// Photo of the performer
	@OptionalField(key: "photo") var photo: String?
	
	/// Performer's website, if any
	@OptionalField(key: "website") var website: String?
	
	/// TRUE if this is one of the JoCo official performers. FALSE if it's a shadow event organizer.
	@Field(key: "official_performer") var officialPerformer: Bool
	
	/// Official performers probably don't want to fill this in, but shadow event hosts might?
	/// Performers that are groups--I'm hoping they won't use this as the performer associates with a single Twitarr user.
	@OptionalParent(key: "uesr") var user: User?
	
	///
	@Siblings(through: EventPerformer.self, from: \.$performer, to: \.$event) var events: [Event]
}

struct CreatePerformerSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("performer")
			.id()
			.field("name", .string, .required)
			.field("bio", .string)
			.field("photo", .string)
			.field("website", .string)
			.field("official_performer", .bool, .required)
			.field("user", .uuid, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("performer").delete()
	}
}


