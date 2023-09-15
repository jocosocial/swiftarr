import Fluent
import Foundation
import Vapor

/// 	This is the object a Karaoke Manager makes when they log a karaoke performance in the Karaoke Lounge.
///
/// 	The played song is related to a song in the Karaoke Library, and the Manager records the name(s) of the karaoke singer(s).
/// 	A timestamp is added automatically.
final class KaraokePlayedSong: Model {
	static let schema = "karaoke_played_song"

	/// The song's ID, provisioned automatically.
	@ID(key: .id) var id: UUID?

	/// Who sung the song. Freeform; if multiple people sang the song onstage together, multiple names may be entered.
	/// @username tags may be used if the singers have Twit-arr accounts.
	@Field(key: "singers") var performers: String

	/// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?

	// MARK: Relations

	/// The song that was sung.
	@Parent(key: "song") var song: KaraokeSong

	/// The Karaoke Manager that created the entry.
	@Parent(key: "manager") var manager: User

	// MARK: Initialization

	// Used by Fluent
	init() {}

	init(singer: String, song: KaraokeSong, managerID: UUID) throws {
		self.performers = singer
		self.$song.id = try song.requireID()
		self.$manager.id = managerID
	}
}

struct CreateKaraokePlayedSongSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("karaoke_played_song")
			.id()
			.field("singers", .string, .required)
			.field("song", .uuid, .required, .references("karaoke_song", "id", onDelete: .cascade))
			.field("manager", .uuid, .required, .references("user", "id", onDelete: .cascade))
			.field("created_at", .datetime)
			.create()
	}

	func revert(on database: Database) async throws {
		try await database.schema("karaoke_played_song").delete()
	}
}
