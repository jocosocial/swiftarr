import Fluent
import PostgresNIO
import Vapor

/// Methods for accessing the list of boardgames available in the onboard Games Library.
struct KaraokeController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/karaoke endpoints
		let baseRoute = app.grouped(DisabledAPISectionMiddleware(feature: .karaoke)).grouped("api", "v3", "karaoke")

		let flexAuthGroup = addFlexCacheAuthGroup(to: baseRoute)
		flexAuthGroup.get("", use: getKaraokeSongs)
		flexAuthGroup.get(songIDParam, use: getKaraokeSong)
		flexAuthGroup.get("latest", use: getLatestPerformedSongs)

		let tokenAuthGroup = addTokenCacheAuthGroup(to: baseRoute)
		tokenAuthGroup.post(songIDParam, "favorite", use: addFavorite)
		tokenAuthGroup.post(songIDParam, "favorite", "remove", use: removeFavorite)
		tokenAuthGroup.delete(songIDParam, "favorite", use: removeFavorite)
		tokenAuthGroup.get("userismanager", use: userCanLogKaraokeSongPerformances)
		tokenAuthGroup.post(songIDParam, "logperformance", use: logSongPerformance)

		let adminAuthGroup = addTokenCacheAuthGroup(to: baseRoute).grouped([RequireAdminMiddleware()])
		adminAuthGroup.post("reload", use: reloadKaraokeData)
	}

	/// `GET /api/v3/karaoke`
	///
	/// Returns an array of karaoke songs in a structure designed to support pagination. Can be called while not logged in;
	/// if logged in favorite information is returned.
	///
	/// This call can't be used to browse the entire ~25000 song library. You must specify either a search string with >2 chars, or
	/// specify favorites=true.
	///
	/// **URL Query Parameters**
	/// * `?search=STRING` - Only show songs whose artist or title contains the given string.
	///   If a single letter or %23 is sent, it will return songs where the artist matches the letter, or starts with a number.
	/// * `?favorite=TRUE` - Only return songs that have been favorited by current user.
	///	* `?start=INT` - Offset from start of results set
	/// * `?limit=INT` - the maximum number of songs to retrieve: 1-200, default is 50.
	///
	/// - Returns: `KaraokeSongResponseData`
	func getKaraokeSongs(_ req: Request) async throws -> KaraokeSongResponseData {
		struct SongQueryOptions: Decodable {
			var search: String?
			var favorite: String?
			var start: Int?
			var limit: Int?
		}
		let filters = try req.query.decode(SongQueryOptions.self)
		let start = filters.start ?? 0
		let limit = (filters.limit ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
		let songQuery = KaraokeSong.query(on: req.db).sort(\.$artist, .ascending).sort(\.$title, .ascending)
		var filteringLetters = false
		if let search = filters.search {
			if search.count == 1 {
				filteringLetters = true
				if search == "#" {
					songQuery.filter(\.$artist, .custom("~"), "^[0-9]")
				}
				else if let _ = search.rangeOfCharacter(from: NSCharacterSet.letters) {
					songQuery.filter(\.$artist, .custom("ILIKE"), "\(search)%")
				}
				else {
					filteringLetters = false
				}
			}
			else {
				songQuery.group(.or) { (or) in
					or.fullTextFilter(\.$artist, search)
					or.fullTextFilter(\.$title, search)
				}
			}
		}
		var filteringFavorites = false
		if let user = req.auth.get(UserCacheData.self) {
			if let fav = filters.favorite, fav.lowercased() == "true" {
				songQuery.join(KaraokeFavorite.self, on: \KaraokeSong.$id == \KaraokeFavorite.$song.$id)
					.filter(KaraokeFavorite.self, \.$user.$id == user.userID)
				filteringFavorites = true
			}
			else {
				// The custom SQL here implements a left join similar to the following commented-out code, except
				// it also filters the KaraokeFavorite results to only favorites by the current user.
				//				songQuery.join(KaraokeFavorite.self, on: \KaraokeFavorite.$song.$id == \KaraokeSong.$id, method: .left)
				songQuery.join(
					KaraokeSong.self,
					KaraokeFavorite.self,
					on: .custom(
						"""
																		LEFT JOIN "karaoke+favorite" ON "karaoke_song"."id" = "karaoke+favorite"."song" AND 
																		"karaoke+favorite"."user" = '\(user.userID)'
																		"""
					)
				)
			}
		}
		else {
			if let fav = filters.favorite, fav.lowercased() == "true" {
				throw Abort(.badRequest, reason: "Must be logged in to view favorites")
			}
		}
		let hasSearchString = filters.search?.count ?? 0 >= 3
		guard filteringFavorites || filteringLetters || hasSearchString else {
			throw Abort(
				.badRequest,
				reason: "Search string must have at least 3 characters, or be a single letter, or be the character #."
			)
		}

		let totalFoundSongs = try await songQuery.count()
		let songs = try await songQuery.range(start..<(start + limit)).with(\.$sungBy).all()
		let songData = try songs.map { song -> KaraokeSongData in
			// Fluent doesn't seem to have an optional joined() variant; if we do a left join to join KaraokeFavorite,
			// there can be songs that aren't favorited in the results. But joined() always returns a model, or throws if it can't.
			// Plus, the error is that it couldn't decode the first non-optional field it encounters--the same thing we'd get if we
			// had a schema mismatch.
			let isFavorite = filteringFavorites ? true : (try? song.joined(KaraokeFavorite.self)) != nil
			return try KaraokeSongData(with: song, isFavorite: isFavorite)
		}
		return KaraokeSongResponseData(totalSongs: totalFoundSongs, start: start, limit: limit, songs: songData)
	}

	/// `GET /api/v3/karaoke/:song_id`
	///
	/// Returns a single karaoke song. Can be called while not logged in; if logged in favorite information is returned.
	///
	/// - Returns: `KaraokeSongData`
	func getKaraokeSong(_ req: Request) async throws -> KaraokeSongData {
		let song = try await KaraokeSong.findFromParameter(songIDParam, on: req)
		var favorite: KaraokeFavorite?
		if let user = req.auth.get(UserCacheData.self) {
			favorite = try await song.$favorites.$pivots.query(on: req.db).filter(\.$user.$id == user.userID).first()
		}
		return try KaraokeSongData(with: song, isFavorite: favorite != nil)
	}

	/// `GET /api/v3/karaoke/performance`
	///
	/// Returns an array of the 10 most recent karaoke songs that have been marked as being performed.
	/// Can be called while not logged in; if logged in favorite information is returned.
	///
	/// Intent of this call is to let people see what's been happening recently in the karaoke lounge without making a complete index of
	/// `who sang what song when` available.
	///
	/// - Returns: An array of up to 10 `KaraokePerformedSongsData`
	func getLatestPerformedSongs(_ req: Request) async throws -> [KaraokePerformedSongsData] {
		let recentSongs = try await KaraokePlayedSong.query(on: req.db).sort(\.$createdAt, .descending).range(0..<10)
			.with(\.$song).all()
		return recentSongs.map {
			KaraokePerformedSongsData(
				artist: $0.song.artist,
				songName: $0.song.title,
				performers: $0.performers,
				time: $0.createdAt ?? Date()
			)
		}
	}

	/// `POST /api/v3/karaoke/:songID/favorite`
	///
	/// Add the specified `KaraokeSong` to the user's list of favorite songs. Must be logged in
	///
	/// - Parameter songID: in URL path
	/// - Returns: 201 Created on success.
	func addFavorite(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		let song = try await KaraokeSong.findFromParameter(songIDParam, on: req)
		do {
			try await KaraokeFavorite(user.userID, song).create(on: req.db)
		}
		catch let error {
			if let sqlError = error as? PostgresError, sqlError.code == .uniqueViolation {
				return .ok
			}
			throw error
		}
		return .created
	}

	/// `POST /api/v3/karaoke/:songID/favorite/remove`
	/// `DELETE /api/v3/karaoke/:songID/favorite`
	///
	/// Remove the specified `KaraokeSong` from the user's favorite list.
	///
	/// - Parameter songID: in URL path
	/// - Returns: 204 No Content on success. 200 OK if song was already not favorited.
	func removeFavorite(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard let songID = req.parameters.get(songIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Could not make UUID out of song parameter")
		}
		let pivot = try await KaraokeFavorite.query(on: req.db).filter(\.$user.$id == user.userID)
			.filter(\.$song.$id == songID).first()
		guard let pivot = pivot else {
			return .ok
		}
		try await pivot.delete(on: req.db)
		return .noContent
	}

	/// `GET /api/v3/karaoke/userismanager`
	///
	/// Returns TRUE in isAuthorized if the user is a Karaoke Manager, meaning they can create entries in  the Karaoke Song Log.
	///
	/// - Returns: 200 OK
	func userCanLogKaraokeSongPerformances(_ req: Request) async throws -> UserAuthorizedToCreateKaraokeLogs {
		let user = try req.auth.require(UserCacheData.self)
		return UserAuthorizedToCreateKaraokeLogs(isAuthorized: user.userRoles.contains(.karaokemanager))
	}

	/// `POST /api/v3/karaoke/:songID/logperformance`
	///
	/// Allows authorized users to create log entries for karaoke performances. Each log entry is timestamped, references a song in the Karaoke song
	/// catalog, and has a freeform text field for entering the song performer(s). Song performers don't need to be Twit-arr users and may not have accounts,
	/// but @mentions in the note field should be processed.
	///
	/// - Parameter songID: in URL path
	/// - Parameter note: `NoteCreateData` in request body
	/// - Returns: 201 Created on success.
	func logSongPerformance(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		guard user.userRoles.contains(.karaokemanager) else {
			throw Abort(.forbidden, reason: "User is not authorized to log Karaoke song performances.")
		}
		let song = try await KaraokeSong.findFromParameter(songIDParam, on: req)
		let data = try ValidatingJSONDecoder().decode(NoteCreateData.self, fromBodyOf: req)
		try await KaraokePlayedSong(singer: data.note, song: song, managerID: user.userID).create(on: req.db)
		return .created
	}

	/// `POST /api/v3/karaoke/reload`
	///
	///  Reloads the karaoke data from the seed file. Removes all previous entries.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `HTTP 200 OK` if the settings were updated.
	func reloadKaraokeData(_ req: Request) async throws -> HTTPStatus {
		let migrator = ImportKaraokeSongs()
		try await migrator.revert(on: req.db)
		try await migrator.prepare(on: req.db)
		return .ok
	}

	// MARK: - Utilities

}
