import Fluent
import PostgresNIO
import Vapor

/// Methods for accessing the list of boardgames available in the onboard Games Library.
struct MicroKaraokeController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/karaoke endpoints
		let baseRoute = app.grouped(DisabledAPISectionMiddleware(feature: .microkaraoke)).grouped("api", "v3", "microkaraoke")

		let flexAuthGroup = addFlexCacheAuthGroup(to: baseRoute)
		flexAuthGroup.get("video", filenameParam, use: getUserVideoClip)

		let tokenAuthGroup = addTokenCacheAuthGroup(to: baseRoute)
		tokenAuthGroup.post("offer", use: retrieveMicroKaraokeOffer)
		tokenAuthGroup.on(.POST,"recording", body: .collect(maxSize: "50mb"), use: uploadMicroKaraokeRecording)
		tokenAuthGroup.get("songlist", use: getCompletedSongList)
		tokenAuthGroup.get("song", mkSongIDParam, use: getSongManifest)
	}
	
	/// `POST /api/v3/microkaraoke/offer`
	///
	///  Requests the server to generate an offer packet for a micro karaoke recording. The offer packet has information about the song to be sung, the particular
	///  lyric to be sung, and the audio files for the sound cues to be used.
	///  
	///  This method is a POST because it's non-idempotent. There is no post data sent to the server, although it requires a logged-in user.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MicroKaraokeOfferPacket` describing the song and lyric.
	func retrieveMicroKaraokeOffer(_ req: Request) async throws -> MicroKaraokeOfferPacket {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent()	// Banned, quarantined, and temp-quarantined users can't use MK

		// Does this user have an existing offer? If so, return it.
		if let openOffer = try await MKSnippet.query(on: req.db).filter(\.$mediaURL == nil)
				.filter(\.$author.$id == cacheUser.userID).with(\.$song).first() {
			return try makeOfferPacket(from: openOffer, song: openOffer.song) 
		}
		
		// Check that we have enough open slots. If not, generate a new song
		// This compares the sum of slots in all songs with the number of snippets actually created. "Snippets Created" includes
		// offers that aren't fulfilled yet, but does not include offers that have timed out.
// Fails because of https://github.com/vapor/fluent-kit/issues/570
//		let allSongsSlots = try await MKSong.query(on: req.db).sum(\.$totalSnippets) ?? 0
		let allSongs = try await MKSong.query(on: req.db).all()
		let allSongsSlots = allSongs.reduce(0) { $0 + $1.totalSnippets }
		let totalSnippets = try await MKSnippet.query(on: req.db).count()
		if allSongsSlots - totalSnippets < 5 {
			// Generate a new song, as we're low on empty song slots
			let currentSong = try allSongs.max { try $0.requireID() < $1.requireID() }
			try await addSong(req, currentSong: currentSong)
		}		
		
		// Try to find a song that has open slots, where this user has not yet added a snippet, at least in the last several hours.
		let validSongs = try await MKSong.query(on: req.db).filter(\.$isComplete == false)
				.with(\.$snippets).sort(\.$createdAt, .ascending).all()
		var alreadySungInASong = false
		for song in validSongs {
			let userSnippets: [MKSnippet] = song.snippets.filter { $0.$author.id == cacheUser.userID }
			// TT and above are exempt and can make multiple clips per song--the idea is that they are automatically
			// Micro Karaoke Ambassadors that will have others record videos using their accounts. (really, using their device).
			if !(cacheUser.accessLevel.hasAccess(.twitarrteam) || cacheUser.userRoles.contains(.karaokeambassador)) {
				// If this user uploaded a clip for this song within the last 4 hours, disallow
				if let lastUpload = userSnippets.max(by: { ($0.updatedAt ?? Date()) < ($1.updatedAt ?? Date()) })?.updatedAt, 
						lastUpload > Date() - 3600 * 4 {
					alreadySungInASong = true
					continue
				}
			}
			// Find an open slot in this song, if one exists. Songs may have open offers for all slots that have no uploads.
			let openSlots = Set(0...(song.totalSnippets - 1)).subtracting(song.snippets.map { $0.songSnippetIndex })
			if let chosenSlot = openSlots.randomElement() {
				// Hard-delete any snippet with this songID+snippetIndex that's been soft-deleted
				try await MKSnippet.query(on: req.db).withDeleted().filter(\.$deletedAt < Date())
						.filter(\.$song.$id == song.requireID()).filter(\.$songSnippetIndex == chosenSlot)
						.delete(force: true)
				
				let newOffer = try MKSnippet(song: song, songSnippetIndex: chosenSlot, author: cacheUser)
				try await newOffer.save(on: req.db)
				let result = try makeOfferPacket(from: newOffer, song: song)
				return result
			}
		}
		// If we get here, it means we didn't find a song with open clips we could offer to this user
		if alreadySungInASong {
			throw Abort(.badRequest, reason: "You've recently taken song slots in all the songs currently being constructed. Come back later.")
		}
		else {
			throw Abort(.badRequest, reason: "There don't seem to be any open song slots.")
		}
	}
	
	/// `POST /api/v3/microkaraoke/recording`
	///
	///  Uploads a video recording containing a person singing the snippet of a song given by the offer. 
	///
	/// - Parameter recordingData: `MicroKaraokeRecordingData` in request body
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MicroKaraokeOfferPacket` describing the song and lyric.
	func  uploadMicroKaraokeRecording(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		try cacheUser.guardCanCreateContent()	// Banned, quarantined, and temp-quarantined users can't use MK
		let data = try ValidatingJSONDecoder().decode(MicroKaraokeRecordingData.self, fromBodyOf: req)
		
		// Check that the user is correct for this snippet and the media is about the right size
		guard let offer = try await MKSnippet.query(on: req.db).filter(\.$id == data.offerID).with(\.$song).withDeleted().first() else {
			throw Abort(.badRequest, reason: "Invalid offer ID. Could mean the slot reservation expired.")
		}
		guard offer.$author.id == cacheUser.userID else {
			throw Abort(.badRequest, reason: "User mismatch. The uploading user doesn't match the user offered this song slot.")
		}
		guard offer.mediaURL == nil else {
			throw Abort(.badRequest, reason: "Cannot upload a video for this reservation. This song slot already has its video.")
		}
		let dataSize = data.videoData.count
		guard dataSize > 500000 && dataSize < 40 * 1000000 else {
			throw Abort(.badRequest, reason: "Video file size doesn't look to be right for a video clip.")
		}
		
		// Save the media, and fill in the media for this snippet
		let snippetURL = try getUserUploadedClipsDir().appendingPathComponent(offer.requireID().uuidString).appendingPathExtension("mp4")
// TODO: For files this big, we might need nonblocking writes
		try data.videoData.write(to: snippetURL)
		var serverSnippetDirURL = Settings.shared.apiUrlComponents
		serverSnippetDirURL.path = try "/api/v3/microkaraoke/video/\(offer.requireID().uuidString).mp4"
		guard let mediaURL = serverSnippetDirURL.url?.absoluteString else {
			throw Abort(.internalServerError, reason: "Couldn't construct URL for uploaded media.")
		}
		offer.mediaURL = mediaURL
		offer.deletedAt = nil
		try await offer.save(on: req.db)
		
		// See if this snippet completes the song--if so, mark song complete
		let finishedSnippetCount = try await MKSnippet.query(on: req.db).filter(\.$song.$id == offer.$song.id).filter(\.$mediaURL != nil).count()
		if finishedSnippetCount >= offer.song.totalSnippets {
			offer.song.isComplete = true
			try await offer.song.save(on: req.db)
		}
		return .ok
	}
	
	
	/// `GET /api/v3/microkaraoke/songlist`
	///
	///  Retuns the list of songs that can be viewed. If the user is a moderator, this list includes songs that are complete but need mod approval.
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `[MicroKaraokeCompletedSong]` with info on all the completed songs that can be viewed.
	func getCompletedSongList(_ req: Request) async throws -> [MicroKaraokeCompletedSong] {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let query = MKSong.query(on: req.db).filter(\.$isComplete == true).sort(\.$id).join(MKSnippet.self, [
				.field(.path(MKSong.path(for: \.$id), schema: MKSong.schema), .equal, .path(MKSnippet.path(for: \.$song.$id), schema: MKSnippet.schema)),
				.value(.path(MKSnippet.path(for: \.$author.$id), schema: MKSnippet.schema), .equal, .bind(cacheUser.userID))], method: .left)
		if !cacheUser.accessLevel.canEditOthersContent() {
			query.filter(\.$modApproved == true)
		}
		let validSongs = try await query.all()
		let uniqueSongDict = try Dictionary(validSongs.map({ try ($0.requireID(), $0) }), uniquingKeysWith:  { (first, _) in first })
		let uniquedSongs = try Array(uniqueSongDict.values).sorted(by: { try $0.requireID() < $1.requireID() })
		let result = try uniquedSongs.map { song in
			var userContributed = false
			if let _ = try? song.joined(MKSnippet.self) {
				userContributed = true
			}
			return try MicroKaraokeCompletedSong(from: song, userContributed: userContributed)
		}
		try await markNotificationViewed(user: cacheUser, type: .microKaraokeSongReady(0), on: req)
		return result
	}
	
	/// `GET /api/v3/microkaraoke/song/:song_id`
	///
	///  
	///
	/// - Parameter song_id: The song to get a manifest for.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `MicroKaraokeSongManifest` with a list of URLs to all the video clips that make up the song, in order.
	func getSongManifest(_ req: Request) async throws -> MicroKaraokeSongManifest {
		let _ = try req.auth.require(UserCacheData.self)
		guard let songID = req.parameters.get(mkSongIDParam.paramString, as: Int.self) else {
			throw Abort(.badRequest, reason: "Could not get song parameter from URL path")
		}
		guard let song = try await MKSong.find(songID, on: req.db) else {
			throw Abort(.badRequest, reason: "Could not find a song with this song ID.")
		}
		guard song.isComplete else {
			throw Abort(.badRequest, reason: "This song isn't finished yet.")
		}
		let songSnippets = try await MKSnippet.query(on: req.db).filter(\.$song.$id == songID ).sort(\.$songSnippetIndex).all()
		let songInfo = try await getSongInfo(forSongNamed: song.songName, on: req)
		var karaokeTrack = Settings.shared.apiUrlComponents
		karaokeTrack.path = "/microkaraoke/\(song.songName)/karaokeAudio.mp3"
		guard let karaokeTrackURL = karaokeTrack.url else {
			throw Abort(.internalServerError, reason: "Could not build audio file URL for karaoke audio track.")
		}
		let result = try MicroKaraokeSongManifest(from: songSnippets, song: song, info: songInfo, karaokeMusicTrack: karaokeTrackURL)
		return result
	}
	
	/// `GET /api/v3/microkaraoke/video/:filename`
	///
	///  Gets a user-uploaded karaoke snippet video. This downloads the actual video file
	///
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `Response` .
	func getUserVideoClip(_ req: Request) async throws -> Response {
		guard let inputFilename = req.parameters.get(filenameParam.paramString) else {
			throw Abort(.badRequest, reason: "No video file specified.")
		}

		// Check the extension
		let fileExtension = URL(fileURLWithPath: inputFilename).pathExtension
		if !["mp4"].contains(fileExtension) {
			throw Abort(.badRequest, reason: "File has wrong file extension type.")
		}

		// Strip extension and any other gunk off the filename. Eject if two extensions detected (.php.jpg, for example).
		let noFiletype = URL(fileURLWithPath: inputFilename).deletingPathExtension()
		if noFiletype.pathExtension.count > 0 {
			throw Abort(.badRequest, reason: "Malformed image filename.")
		}
		let filename = noFiletype.lastPathComponent
		// This check is important for security. Not only does it do the obvious, it protects
		// against "../../../../file_important_to_Swiftarr_operation" attacks.
		guard let fileUUID = UUID(filename) else {
			throw Abort(.badRequest, reason: "Image filename is not a valid UUID.")
		}

		let fileURL = try getUserUploadedClipsDir().appendingPathComponent(fileUUID.uuidString + "." + fileExtension)
		let response = req.fileio.streamFile(at: fileURL.path)
		// If streamFile is returning the image file, add a cache-control header to the repsonse
		if response.status == .ok {
			response.headers.cacheControl = .init(isPublic: true, maxAge: 3600 * 24)
		}
		return response
	}
		
	// MARK: - Utilities
	
	// urlForSongDirectory() gets the `/Assets/microkaraoke` directory, where the STATIC file assets are stored (mostly short sound files)
	// urlForSongDirectory(songName:) gets the subdir for a specific song,
	// urlForSongDirectory(songName:, snippetIndex:) gets the subdir for a snippet within a song
	func urlForSongDirectory(songName: String? = nil, snippetIndex: Int? = nil) -> URL {
		var mkPath = Settings.shared.staticFilesRootPath.appendingPathComponent("Resources")
				.appendingPathComponent("Assets")
				.appendingPathComponent("microkaraoke")
		if let songName = songName {
			mkPath.appendPathComponent(songName)
			if let snippetIndex = snippetIndex {
				mkPath.appendPathComponent(String(snippetIndex))
			}
		}
		return mkPath
	}
	
	// returns the local access path for the user-uploaded karaoke video clips.
	func getUserUploadedClipsDir() throws -> URL {
		let result = Settings.shared.userImagesRootPath.appendingPathComponent("microkaraokevideos")
		try FileManager.default.createDirectory(at: result, withIntermediateDirectories: true)
		return result
	}
	
	func makeOfferPacket(from snippet: MKSnippet, song: MKSong) throws -> MicroKaraokeOfferPacket {
		let localSnippetDir = urlForSongDirectory(songName: song.songName, snippetIndex: snippet.songSnippetIndex)
		let lyricsFileURL = localSnippetDir.appendingPathComponent("lyric.txt")
		let lyrics = try String(contentsOf: lyricsFileURL, encoding: .utf8)
		var serverSnippetDirURL = Settings.shared.apiUrlComponents
		serverSnippetDirURL.path = "/microkaraoke/\(song.songName)/\(snippet.songSnippetIndex)"
		guard let url = serverSnippetDirURL.url else {
			throw Abort(.internalServerError, reason: "Could not convert URL Components to URL")
		}
		return try MicroKaraokeOfferPacket(from: snippet, song: song, snippetDirectory: url, lyrics: lyrics)
	}
	
	// Creates a new MKSong model
	func addSong(_ req: Request, currentSong: MKSong?) async throws {
		let mkPath = urlForSongDirectory()
		var allSongs = try FileManager.default.contentsOfDirectory(at: mkPath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
		allSongs = allSongs.filter { $0.hasDirectoryPath }
		// Remove songs from consideration if their songInfo's 'allowAdds' is false
		var availableSongs: [URL] = []
		for song in allSongs {
			if try await getSongInfo(forSongNamed: song.lastPathComponent, on: req).allowAdds {
				availableSongs.append(song)
			}
		}
		// If there's another choice for what song to use next, try not to use the same sone we used last
		if availableSongs.count > 1, let currentSong = currentSong {
			availableSongs = availableSongs.filter { $0.lastPathComponent != currentSong.songName }
		}
		
		guard let selectedSong = availableSongs.randomElement() else {
			throw Abort(.internalServerError)
		}
		let songInfo = try await getSongInfo(forSongNamed: selectedSong.lastPathComponent, on: req)
		// For testing, set totalSnippets to a specific number here. This makes it easy and fast-ish to complete lots of songs.
		let totalSnippets = songInfo.totalSnippets
//		let totalSnippets = 3
		let mkUserID = req.userCache.getUser(username: "MicroKaraoke")?.userID ?? UUID()
		let newSongModel = MKSong(name: songInfo.songname, artist: songInfo.artist, totalSnippets: totalSnippets, 
				bpm: songInfo.bpm, songCreatorID: mkUserID)
		try await newSongModel.save(on: req.db)
		
		
		// Immediately fill in the clips for any filler snippets where there's nobody singing and we need background video
//		let snippets = try FileManager.default.contentsOfDirectory(at: selectedSong, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
		for index in 0..<totalSnippets {
			let fillPath = selectedSong.appendingPathComponent("\(index)").appendingPathComponent("fill.mp3")
			if FileManager.default.fileExists(atPath: fillPath.path), let krakenUser = req.userCache.getUser(username: "kraken") {
				let newSnippetModel = try MKSnippet(song: newSongModel, songSnippetIndex: index, author: krakenUser)
				var mediaURL = Settings.shared.apiUrlComponents
				let filename = newSongModel.isPortrait ? "fillVideoPortrait" : "fillVideoLandscape"
				mediaURL.path = "/microkaraoke/\(songInfo.songname)/\(index)/\(filename).mp4"
				guard let url = mediaURL.url else {
					throw Abort(.internalServerError, reason: "Could not create URL for song filler video.")
				}
				newSnippetModel.mediaURL = url.absoluteString
				newSnippetModel.deletedAt = nil
				try await newSnippetModel.save(on: req.db)
			}
		}
	}
	
	func getSongInfo(forSongNamed songName: String, on req: Request) async throws -> SongInfoJSON {
		let songInfoURL = urlForSongDirectory(songName: songName).appendingPathComponent("songinfo.json")
		let buffer = try await req.fileio.collectFile(at: songInfoURL.path)
		guard let songInfoJSON = buffer.getData(at: 0, length: buffer.readableBytes) else {
			throw Abort(.badRequest, reason: "Could not read songinfo file.")
		}
		let songInfo = try JSONDecoder().decode(SongInfoJSON.self, from: songInfoJSON)
		return songInfo
	}
	
//	func buildFillerSnippet(forSong song: MKSong, snippetIndex: Int, on req: Request) async throws {
//		let fillPath = selectedSong.appendingPathComponent("\(index)").appendingPathComponent("fill.mp3")
//		if FileManager.default.fileExists(atPath: fillPath.path), let krakenUser = req.userCache.getUser(username: "kraken") {
//			let newSnippetModel = try MKSnippet(song: song, songSnippetIndex: snippetIndex, author: krakenUser)
//			var mediaURL = Settings.shared.apiUrlComponents
//			mediaURL.path = "/microkaraoke/\(song.songName)/\(snippetIndex)/video.mp4"
//			guard let url = mediaURL.url else {
//				throw Abort(.internalServerError, reason: "Could not create URL for song filler video.")
//			}
//			newSnippetModel.mediaURL = url.absoluteString
//			newSnippetModel.deletedAt = nil
//			try await newSnippetModel.save(on: req.db)
//		}
//	}
}

// This JSON struct is used in files inside of the 'microkaraoke' folder in static files, not used for network API calls.
struct SongInfoJSON: Decodable {
	var songname: String
	var artist: String
	var totalSnippets: Int
	var bpm: Int
	var allowAdds: Bool
	var durations: [Double]
}

