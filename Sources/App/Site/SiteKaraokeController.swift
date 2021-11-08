import Vapor
import Crypto
import Fluent
import LeafKit

/// Pages for displaying info on Karaoke Songs. This is all based on 2 kinds of data on the API:
/// * KaraokeSongs, a static list of all ~25000 songs in the jukebox. 
/// * Performances. Authorized users can create log entries noting that one or more performers sang a KaraokeSong.
struct SiteKaraokeController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app).grouped("karaoke").grouped(DisabledSiteSectionMiddleware(feature: .karaoke))
		openRoutes.get("", use: karaokePageHandler)
		
		// Routes that the user needs to be logged in to access.
		let privateRoutes = getPrivateRoutes(app).grouped("karaoke").grouped(DisabledSiteSectionMiddleware(feature: .karaoke))
		privateRoutes.get("logperformance", songIDParam, use: songPerformanceLogEntryPageHandler)
		privateRoutes.post("logperformance", songIDParam, use: songPerformanceLogEntryPostHandler)
		privateRoutes.post(songIDParam, "favorite", use: addFavoriteSong)
		privateRoutes.delete(songIDParam, "favorite", use: removeFavoriteSong)
	}

	/// GET /karaoke
	///
	/// **URL Query Parameters**
	/// * `?search=STRING` - returns song library results where the artist OR song title matches the given string.
	/// * `?favorite=TRUE` - Only return songs that have been favorited by current user. 
	///	* `?start=INT` - Offset from start of results set
	/// * `?limit=INT` - the maximum number of songs to retrieve: 1-200, default is 50. 
	///
	/// With no search query, returns a page with a search form and a list of the 10 most recently performed
	/// songs. With a search parameter, returns a list of matching songs from the catalog. The underlying idea is that
	/// it's not helpful to let the user browse all 25000+ songs.
	func karaokePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		let searchStr = req.query[String.self, at: "search"] ?? ""
		let favorite = req.query[String.self, at: "favorite"] == nil ? false : true
		if !searchStr.isEmpty || favorite {
			var mgrQuery: EventLoopFuture<Bool> = req.eventLoop.future(false)
			if let _ = req.auth.get(User.self) {
				mgrQuery = apiQuery(req, endpoint: "/karaoke/userismanager").flatMapThrowing { mgrResponse in
					let userIsMgr = try mgrResponse.content.decode(UserAuthorizedToCreateKaraokeLogs.self)
					return userIsMgr.isAuthorized
				}
			}
			return apiQuery(req, endpoint: "/karaoke").and(mgrQuery)
					.throwingFlatMap { (songResponse, userIsManager) in
				let matchingSongs = try songResponse.content.decode(KaraokeSongResponseData.self)
				struct SongSearchContext: Encodable {
					var trunk: TrunkContext
					var songs: KaraokeSongResponseData
					var searchText: String
					var userIsKaraokeMgr: Bool
					var paginator: PaginatorContext
					var showingFavorites: Bool
					var favoriteBtnURL: String

					init(_ req: Request, searchStr: String, songs: KaraokeSongResponseData, isMgr: Bool, showingFavorites: Bool) throws {
						trunk = .init(req, title: "Latest Karaoke Songs", tab: .none)
						self.songs = songs
						self.searchText = searchStr
						userIsKaraokeMgr = isMgr
						self.showingFavorites = showingFavorites
						if showingFavorites {
						//	favoriteBtnURL = searchStr.isEmpty ? "/karaoke" : "/karaoke?search=\(searchStr)"
							favoriteBtnURL = "/karaoke"
						}
						else {
						//	favoriteBtnURL = searchStr.isEmpty ? "/karaoke?favorite=true" : "/karaoke?search=\(searchStr)&favorite=true"
							favoriteBtnURL = "/karaoke?favorite=true"
						}
						paginator = .init(start: songs.start, total: songs.totalSongs, limit: songs.limit) { pageIndex in
							"/karaoke?search=\(searchStr)&start=\(pageIndex * songs.limit)&limit=\(songs.limit)"
						}
					}
				}
				let ctx = try SongSearchContext(req, searchStr: searchStr, songs: matchingSongs, isMgr: userIsManager,
						showingFavorites: favorite)
				return req.view.render("GamesAndSongs/matchingSongs", ctx)
			}
		}
		else {
			return apiQuery(req, endpoint: "/karaoke/latest").throwingFlatMap { response in
				let latestSongs = try response.content.decode([KaraokePerformedSongsData].self)
				struct LatestSongsContext: Encodable {
					var trunk: TrunkContext
					var songs: [KaraokePerformedSongsData]

					init(_ req: Request, songs: [KaraokePerformedSongsData]) throws {
						trunk = .init(req, title: "Latest Karaoke Songs", tab: .none)
						self.songs = songs
					}
				}
				let ctx = try LatestSongsContext(req, songs: latestSongs)
				return req.view.render("GamesAndSongs/latestSongs", ctx)
			}
		}
	}
	
	// POST /karaoke/:song_id/favorite
	func addFavoriteSong(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let songID = req.parameters.get(songIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing song ID parameter.")
    	}
    	return apiQuery(req, endpoint: "/karaoke/\(songID)/favorite", method: .POST).map { response in
    		return response.status
		}
	}
	
    // `DELETE /karaoke/:song_id/favorite`
    func removeFavoriteSong(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let songID = req.parameters.get(songIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing song ID parameter.")
    	}
    	return apiQuery(req, endpoint: "/karaoke/\(songID)/favorite", method: .DELETE).map { response in
    		return response.status
		}
    }
    
	// GET /karaoke/logperformance/:song_id
	func songPerformanceLogEntryPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let songID = req.parameters.get(songIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Could not make UUID out of song parameter")
		}
		return apiQuery(req, endpoint: "/karaoke/\(songID)").throwingFlatMap { response in
			let song = try response.content.decode(KaraokeSongData.self)
			struct LogPerformanceContext: Encodable {
				var trunk: TrunkContext
				var song: KaraokeSongData

				init(_ req: Request, song: KaraokeSongData) throws {
					trunk = .init(req, title: "Latest Karaoke Songs", tab: .none)
					self.song = song
				}
			}
			let ctx = try LogPerformanceContext(req, song: song)
			return req.view.render("GamesAndSongs/logSongPerformance", ctx)
		}
	}
	
	// POST /karaoke/logperformance/:song_id
	func songPerformanceLogEntryPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		struct FormData: Content {
			var message: String
		}
		let logEntry = try req.content.decode(FormData.self)
		guard let songID = req.parameters.get(songIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Could not make UUID out of song parameter")
		}
		return apiQuery(req, endpoint: "/karaoke/\(songID)/logperformance", method: .POST, beforeSend: { req in
			try req.content.encode(NoteCreateData(note: logEntry.message))
		}).map { response in
			return .created
		}
	}

}
