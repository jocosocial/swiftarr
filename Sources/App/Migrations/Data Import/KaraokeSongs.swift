import Vapor
import Fluent


/// A `Migration` that imports the Karaoke Song Catalog file.
/// 
/// This file is  located in the `seeds/` subdirectory of the project.
struct ImportKaraokeSongs: Migration {    
    /// Required by `Migration` protocol. Reads either a test or production `.ics` file in the
    /// `seeds/` subdirectory, converts the lines into elements of an array, hands that off to
    /// a parser and populates the `Event` database with the `[Event]` array returned.
    ///
    /// - Requires: `2020JoCoKaraokeSongCatalog.txt` file in seeds subdirectory.
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
    	database.logger.info("Starting karaoke song import")
        // get the songs file. Tab-delimited, each line contains: "ARTIST \t SONG_TITLE \t TAGS \n"
        // Tags can be: "VR" for voice-reduced, M for midi (I think?)
        let songsFilename: String
        do {
            if try Environment.detect().name != "heroku" {
                songsFilename = "2022JoCoKaraokeSongCatalog.txt"
            } else {
                songsFilename = "JoCoKaraokeSongCatalog-heroku.txt"
            }
			let songsFilePath = Settings.shared.seedsDirectoryPath.appendingPathComponent(songsFilename)
			let songsFile = try String(contentsOfFile: songsFilePath.path, encoding: .utf8) 
			var lines = songsFile.components(separatedBy: "\r\n")
			if lines.count < 10 {
				lines = songsFile.components(separatedBy: .newlines)
			}	

			// Creating one song at a time is slow, but PSQL chokes on a single command that creates 25000+ songs.
			// So, chunking the creates into batches of 1000. 
			let save1000Songs = { (startIndex: Int) -> EventLoopFuture<Void> in
				let endIndex = min(startIndex + 1000, lines.count)
				var karaokesongs: [KaraokeSong] = []
				for line in startIndex..<endIndex {
					let parts = lines[line].split(separator: "\t")
					if parts.count >= 2 {
						let modifier: String? = parts.count >= 3 ? String(parts[2]) : nil
						let isMidi = modifier == "M"
						let isVR = modifier == "VR"
						karaokesongs.append(KaraokeSong(artist: String(parts[0]), title: String(parts[1]), 
								isVoiceRemoved: isVR, isMidi: isMidi))
					}
				}
				return karaokesongs.create(on: database)
			}
			
			var rollupFutures: [EventLoopFuture<Void>] = []
			for index in stride(from: 0, through: lines.count, by: 1000) {
				rollupFutures.append(save1000Songs(index))
				database.logger.info("Imported \(index) karaoke songs.")
			}
			return rollupFutures.flatten(on: database.eventLoop)
		}
		catch {
			fatalError("Could not read karaoke songs file.")
		}
	}
	
    func revert(on database: Database) -> EventLoopFuture<Void> {
        KaraokeSong.query(on: database).delete()
    }
}
