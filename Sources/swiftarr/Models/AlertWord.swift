import Fluent
import Vapor

final class AlertWord: Model {
	static let schema = "alertword"

	// MARK: Properties

	/// The alertword's ID.
	@ID(custom: "id") var id: Int?

	/// The alertword. Must be one word, no spaces. Should be stored in lowercase.
	@Field(key: "word") var word: String

	/// The number of Twarrts that contain this alertword
	@Field(key: "twarrt_count") var twarrtCount: Int

	/// The number of ForumPosts that contain this alertword
	@Field(key: "post_count") var postCount: Int

	// MARK: Relations

	/// The sibling `User`s who have added this alert word to their list of words to be notified on.
	@Siblings(through: AlertWordPivot.self, from: \.$alertword, to: \.$user) var users

	// MARK: Initialization

	/// Used by Fluent
	init() {}

	/// Initializes a new AlertWord object.
	///
	/// - Parameters:
	///   - word: the word to alert on..
	init(_ word: String) {
		self.word = word
		twarrtCount = 0
		postCount = 0
	}
}

struct CreateAlertWordSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("alertword")
			.field("id", .int, .identifier(auto: true))
			.field("word", .string, .required)
			.unique(on: "word")
			.field("twarrt_count", .int, .required)
			.field("post_count", .int, .required)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("alertword").delete()
	}
}
