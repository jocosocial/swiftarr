import Fluent
import Vapor

final class AlertWordPivot: Model, @unchecked Sendable {
	static let schema = "alertword+user"

	// MARK: Properties

	/// The pivot's ID.
	@ID(key: .id) var id: UUID?

	/// The number of Twarrts that this user has viewed
	@Field(key: "twarrt_count") var twarrtCount: Int

	/// The number of ForumPosts containing this alertword that this user has viewed
	@Field(key: "post_count") var postCount: Int

	// MARK: Relations

	/// The associated `User` who added this alertword.
	@Parent(key: "user") var user: User

	/// The associated `AlertWord` that was added.
	@Parent(key: "alertword") var alertword: AlertWord

	// MARK: Initialization

	/// Used by Fluent
	init() {}

	/// Initializes a new AlertWord object.
	///
	/// - Parameters:
	///   - word: the word to alert on..
	init(alertword: AlertWord, userID: UUID) throws {
		self.$alertword.id = try alertword.requireID()
		self.$user.id = userID
		twarrtCount = 0
		postCount = 0
	}
}

struct CreateAlertWordPivotSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("alertword+user")
			.id()
			.field("twarrt_count", .int, .required)
			.field("post_count", .int, .required)
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("alertword", .int, .required, .references("alertword", "id", onDelete: .cascade))
			.unique(on: "user", "alertword")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("alertword+user").delete()
	}
}
