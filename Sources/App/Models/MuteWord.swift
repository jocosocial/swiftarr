import Fluent
import Vapor

final class MuteWord: Model {
	static let schema = "muteword"

	// MARK: Properties

	/// The muteword's ID.
	@ID(custom: "id") var id: Int?

	/// The muteword. Must be one word, no spaces. Should be stored in lowercase.
	@Field(key: "word") var word: String

	// MARK: Relations

	/// The associated `User` who added this muteword.
	@Parent(key: "user") var user: User

	// MARK: Initialization

	/// Used by Fluent
	init() {}

	/// Initializes a new MuteWord object.
	///
	/// - Parameters:
	///   - word: the word to alert on..
	init(_ word: String, userID: UUID) {
		self.word = word
		self.$user.id = userID
	}
}

struct CreateMuteWordSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("muteword")
			.field("id", .int, .identifier(auto: true))
			.field("word", .string, .required)
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("muteword").delete()
	}
}
