import Fluent
import Foundation

/// A `Pivot` holding a sibllings relation between `User` and `Twarrt`.

final class TwarrtLikes: Model {
	static let schema = "twarrt+likes"

	// MARK: Properties

	/// The ID of the pivot.
	@ID(key: .id) var id: UUID?

	/// The type of like reaction. Needs to be optional to conform to `ModifiablePivot`'s
	/// required `init(_:_:)`.
	@Field(key: "liketype") var likeType: LikeType?

	/// TRUE if this twarrt is favorited by this user.
	@Field(key: "favorite") var isFavorite: Bool

	// MARK: Relations

	/// The associated `User` who likes this.
	@Parent(key: "user") var user: User

	/// The associated `Twarrt` that was liked.
	@Parent(key: "twarrt") var twarrt: Twarrt

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new TwarrtLikes pivot.
	///
	/// - Parameters:
	///   - user: The left hand `User` model.
	///   - twarrt: The right hand `Twarrt` model.
	init(_ userID: UUID, _ twarrt: Twarrt, likeType: LikeType?) throws {
		self.$user.id = userID
		self.$twarrt.id = try twarrt.requireID()
		self.$twarrt.value = twarrt
		self.likeType = likeType
		self.isFavorite = false
	}
}

struct CreateTwarrtLikesSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("twarrt+likes")
			.id()
			.unique(on: "user", "twarrt")
			.field("liketype", .string)
			.field("favorite", .bool, .required)
			.field("user", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("twarrt", .int, .required, .references("twarrt", "id", onDelete: .cascade))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("twarrt+likes").delete()
	}
}
