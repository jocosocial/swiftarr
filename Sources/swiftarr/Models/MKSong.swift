import Fluent
import Vapor

final class MKSong: Model {
	static let schema = "microkaraoke_song"

	// MARK: Properties

	/// The song's ID.
	@ID(custom: "id") var id: Int?

	/// The name of the song
	@Field(key: "song_name") var songName: String

	/// the artist/band that performed the original song
	@Field(key: "artist_name") var artistName: String
		
	/// The number of snippets required for this song
	@Field(key: "total_snippets") var totalSnippets: Int
	
	/// The beats per minute of the song; used to set the rate of the countdown timer that appears before recording.
	@Field(key: "bpm") var bpm: Int
	
	/// TRUE if this song is being made in portrait mode, else landscape. Clients that upload video clips must ensure the correct orientation, as all clips
	/// in the same song need the same orientation.
	@Field(key: "is_portrait") var isPortrait: Bool
	
	/// TRUE if this song video hass a video clip for each part of the song. This value could go back to FALSE for a song if a clip is deleted after completion.
	@Field(key: "is_complete") var isComplete: Bool
	
	/// TRUE if a mod has approved ths video. Once approved the video can be returned by methods that get the list of viewable videos.
	@Field(key: "mod_approved") var modApproved: Bool

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	/// Timestamp of the model's last update, set automatically.
	@Timestamp(key: "updated_at", on: .update) var updatedAt: Date?

	/// Timestamp of the model's soft-deletion, set automatically.
	@Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Relations

	/// The video clips that make up the song's video presentation
	@Children(for: \.$song) var snippets: [MKSnippet]
	
	/// In order for content to be reported on by users, there needs to be an author responsible for the content. For songs, however,
	/// users will report on the song as a whole, not individual video clips submitted by users. So, Micro Karaoke songs are always 'authored' by the Kraken client user
	/// and users will report against that user.
	@Parent(key: "kraken_user") var krakenUser: User

	// MARK: Initialization

	/// Used by Fluent
	init() {}

	/// Initializes a new MKSong object.
	///
	/// - Parameters:
	///   - word: the word to alert on..
	init(name: String, artist: String, totalSnippets: Int, bpm: Int, krakenUserID: UUID) {
		self.songName = name
		self.artistName = artist
		self.totalSnippets = totalSnippets
		self.bpm = bpm
//		isPortrait = true
		isPortrait = Bool.random()
		isComplete = false
		modApproved = false
		$krakenUser.id = krakenUserID
	}
}

// Songs can be reported
extension MKSong: Reportable {
	/// The type for `MKSong` reports.
	var reportType: ReportType { .mkSong }

	var authorUUID: UUID { $krakenUser.id }	// As entire songs aren't 'authored' by anyone, we set the author to kraken 

	var autoQuarantineThreshold: Int { 100000 }
	
	var moderationStatus: ContentModerationStatus {
		get {
			return modApproved ? .modReviewed : .normal
		}
		set(newValue) {
			modApproved = newValue == .modReviewed
		}
	}
}


struct CreateMKSongSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("microkaraoke_song")
			.field("id", .int, .identifier(auto: true))
			.field("song_name", .string, .required)
			.field("artist_name", .string, .required)
			.field("total_snippets", .int, .required)
			.field("bpm", .int, .required)
			.field("is_portrait", .bool, .required)
			.field("is_complete", .bool, .required)
			.field("mod_approved", .bool, .required)
			.field("kraken_user", .uuid, .required, .references("user", "id"))
			
			.field("created_at", .datetime)
			.field("updated_at", .datetime)
			.field("deleted_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("microkaraoke_song").delete()
	}
}

