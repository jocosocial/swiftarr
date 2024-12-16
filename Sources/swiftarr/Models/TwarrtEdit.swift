import Fluent
import Vapor

/// When a `Twarrt` is edited, a `TwarrtEdit` is created and associated with the
/// twarrt.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

final class TwarrtEdit: Model, @unchecked Sendable {
	static let schema = "twarrtedit"

	// MARK: Properties

	/// The edit's ID.
	@ID(key: .id) var id: UUID?

	/// The previous contents of the post.
	/// The previous text of the post.
	@Field(key: "text") var text: String

	/// The previous images, if any.
	@OptionalField(key: "images") var images: [String]?

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The ID of the twarrt that was edited.
	@Parent(key: "twarrt") var twarrt: Twarrt

	/// The `User` that performed the edit.
	@Parent(key: "editor") var editor: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	/// Initializes a new TwarrtEdit with the current contents of a twarrt.. Call on the twarrt BEFORE editing it
	///  to save previous contents.
	///
	/// - Parameters:
	///   - twarrt: The Twarrt that will be edited.
	init(twarrt: Twarrt, editorID: UUID) throws {
		self.$twarrt.id = try twarrt.requireID()
		self.$twarrt.value = twarrt
		self.text = twarrt.text
		self.images = twarrt.images
		self.$editor.id = editorID
	}
}

struct CreateTwarrtEditSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("twarrtedit")
			.id()
			.field("text", .string, .required)
			.field("images", .array(of: .string))
			.field("created_at", .datetime)
			.field("twarrt", .int, .references("twarrt", "id"))
			.field("editor", .uuid, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("twarrtedit").delete()
	}
}
