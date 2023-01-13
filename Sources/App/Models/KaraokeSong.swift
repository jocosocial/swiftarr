import Foundation
import Vapor
import Fluent

/**
	A song in the Karaoke Jukebox. The Jukebox has ~25000 songs; rather too many to let users browse without searching.
	For Heroku deploys there's an alternate import file that only import ~1000 songs. This is due to Heroku's free tier limiting us
	to 10000 database rows.
 */
final class KaraokeSong: Model, Searchable {
	static let schema = "karaoke_song"
	
	/// The song's ID, provisioned automatically.
 	@ID(key: .id) var id: UUID?
	
	/// The name of the person or group.
	@Field(key: "artist") var artist: String
	
	/// The title of the song
	@Field(key: "title") var title: String

	/// If TRUE, this is the regular (non-karaoke) version of the song that's been processed through voice-remover software.
	@Field(key: "voiceRemoved") var voiceRemoved: Bool
	
	/// If TRUE, this song is a MIDI track.
	@Field(key: "midi") var midi: Bool

	// Karaoke songs support fulltext search
	@Field(key: "fulltext_search") var fullTextSearch: String
	
// MARK: Relations

	/// The sibling `User`s who have favorited the song.
	@Siblings(through: KaraokeFavorite.self, from: \.$song, to: \.$user) var favorites: [User]

	/// A list of who, if anyone, has already performed this song on the boat this trip.
	@Children(for: \.$song) var sungBy: [KaraokePlayedSong]

// MARK: Initialization
	
	// Used by Fluent
 	init() { }
 	
 	init(artist: String, title: String, isVoiceRemoved: Bool = false, isMidi: Bool = false) {
 		self.artist = artist
 		self.title = title
 		self.voiceRemoved = isVoiceRemoved
 		self.midi = isMidi
 	}
}

struct CreateKaraokeSongSchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		try await database.schema("karaoke_song")
				.id()
				.field("artist", .string, .required)
				.field("title", .string, .required)
				.field("voiceRemoved", .bool, .required)
				.field("midi", .bool, .required)
				.create()
	}
 
	func revert(on database: Database) async throws {
		try await database.schema("karaoke_song").delete()
	}
}

