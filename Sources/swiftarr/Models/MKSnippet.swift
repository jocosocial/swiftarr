import Fluent
import Vapor

final class MKSnippet: Model {
	static let schema = "microkaraoke_snippet"

	// MARK: Properties

	/// The snippet's ID.
	@ID(key: .id) var id: UUID?

	/// Each 'song' is a sequence of video snippets spliced together. Each snippet offered to a user for recording has a index into hat sequence.
	/// Snippet 0 is the first snippet in a song.
	@Field(key: "song_snippet_index") var songSnippetIndex: Int

	/// The URL of the snippet media. Nil upon creation. Gets filled in once the user uploads their video clip for this snippet offer.
	@Field(key: "media_url") var mediaURL: String?

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Relations

	/// The parent `User`  who was offered the snippet slot. If mediaFilename is non-nil, the parent `User` who authored the video clip.
	@Parent(key: "author") var author: User

	/// The song that this snippet will be/is a part of.
	@Parent(key: "song_id") var song: MKSong

	// MARK: Initialization

	/// Used by Fluent
	init() {}

	/// Initializes a new MKSnippet object.
	///
	/// - Parameters:
	///   - song: 
	///   - snippetNumber:
	init(song: MKSong, songSnippetIndex: Int, author: UserCacheData) throws {
		self.$song.id = try song.requireID()
		self.$author.id = author.userID
		self.songSnippetIndex = songSnippetIndex
		
		self.deletedAt = Date() + 60 * 30
	}
}

// Snippets can be reported, and deleted by mods
extension MKSnippet: Reportable {
	/// The type for `MKSong` reports.
	var reportType: ReportType { .mkSongSnippet }

	var authorUUID: UUID { self.$author.id }	

	var autoQuarantineThreshold: Int { 10000 }
	
	var moderationStatus: ContentModerationStatus {
		get {
			if let deletedAt = self.deletedAt {
				return deletedAt < Date() ? .quarantined : .normal
			}
			return .normal
		}
		set(newValue) {
		}
	}
}

struct CreateMKSnippetSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("microkaraoke_snippet")
			.id()
			.field("song_snippet_index", .int, .required)
			.field("media_url", .string)
			
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			
			.field("author", .uuid, .required, .references("user", "id"))
			.field("song_id", .int, .required, .references("microkaraoke_song", "id"))
			
			// NOTE this interacts poorly with soft-delete! Unique is enforced by SQL directly, and SQL knows nothing
			// about the deleted_at field (Fluent implements soft-delete by silently adding a filter to queries)
			.unique(on: "song_snippet_index", "song_id")
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("microkaraoke_snippet").delete()
	}
}

