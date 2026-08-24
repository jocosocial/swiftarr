import Fluent
import FluentSQL
import Vapor

/// 	An individual post within a `FriendlyFez` discussion. A FezPost must contain
/// 	text content and may also contain image content, unless the Fez is of type `FezType.closed`,
/// 	in which case the post may not contain images.
///
/// 	- See Also: [FezPostData](FezPostData) the DTO for returning info on FezPosts. FezPostData is also a member of `FezData`.
/// 	- See Also: [CreateFezPostSchema](CreateFezPostSchema) the Migration for creating the FezPost table in the database.
final class FezPost: Model, Searchable, @unchecked Sendable {
	static let schema = "fezposts"

	// MARK: Properties

	/// The post's ID.
	@ID(custom: "id") var id: Int?

	/// The text content of the post.
	@Field(key: "text") var text: String

	/// The filenames of any image content of the post. Seamail (closed/open) posts cannot have images.
	/// LFG posts are limited to one image. Private Event posts use the forum post image limit.
	@OptionalField(key: "images") var images: [String]?

	/// Moderators can set several statuses on fezPosts that modify editability and visibility.
	@Enum(key: "mod_status") var moderationStatus: ContentModerationStatus

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Relations

	/// The `FriendlyFez` to which the post belongs.
	@Parent(key: "friendly_fez") var fez: FriendlyFez

	/// The post's author.
	@Parent(key: "author") var author: User

	// MARK: Initialization

	/// Used by Fluent
	init() {}

	/// Initializes a new FezPost.
	///
	/// - Parameters:
	///   - fezID: The ID of the post's FriendlyFez.
	///   - authorID: The ID of the author of the post.
	///   - text: The text content of the post.
	///   - images: The filenames of any image content of the post.
	init(
		fez: FriendlyFez,
		authorID: UUID,
		text: String,
		images: [String]? = nil
	) throws {
		self.$fez.id = try fez.requireID()
		self.$fez.value = fez
		self.$author.id = authorID

		// Generally I'm in favor of "validate input, sanitize output" but I hate "\r\n" with the fury of a thousand suns.
		self.text = text.replacingOccurrences(of: "\r\n", with: "\r")
		self.images = images
		self.moderationStatus = .normal
	}
}

// fezposts can be filtered by author and content
extension FezPost: ContentFilterable {
	func contentTextStrings() -> [String] {
		return [self.text]
	}
}

// Fez posts can be reported
extension FezPost: Reportable {
	/// The report type for `FezPost` reports.
	var reportType: ReportType { .fezPost }
	/// Standardizes how to get the author ID of a Reportable object.
	var authorUUID: UUID { $author.id }

	/// No auto quarantine for fez posts.
	var autoQuarantineThreshold: Int { Int.max }
}

struct CreateFezPostSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let modStatusEnum = try await database.enum("moderation_status").read()
		try await database.schema("fezposts")
			.field("id", .int, .identifier(auto: true))
			.field("text", .string, .required)
			.field("image", .string)
			.field("mod_status", modStatusEnum, .required)
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			.field("friendly_fez", .uuid, .required, .references("friendlyfez", "id"))
			.field("author", .uuid, .required, .references("user", "id"))
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("fezposts").delete()
	}
}

/// Converts the single `image` column into an `images` string array so Private Event posts
/// can attach more than one photo.
struct UpdateFezPostImagesMigration: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("fezposts")
			.field("images", .array(of: .string))
			.update()
		if let sql = database as? SQLDatabase {
			_ = try await sql.raw(
				#"UPDATE "fezposts" SET "images" = ARRAY["image"] WHERE "image" IS NOT NULL AND "image" <> ''"#
			)
			.all()
		}
		try await database.schema("fezposts")
			.deleteField("image")
			.update()
	}

	func revert(on database: Database) async throws {
		try await database.schema("fezposts")
			.field("image", .string)
			.update()
		if let sql = database as? SQLDatabase {
			_ = try await sql.raw(
				#"UPDATE "fezposts" SET "image" = "images"[1] WHERE "images" IS NOT NULL AND cardinality("images") > 0"#
			)
			.all()
		}
		try await database.schema("fezposts")
			.deleteField("images")
			.update()
	}
}
