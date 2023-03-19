import Fluent
import Vapor

/// A `Migration` that imports the Karaoke Song Catalog file.
///
/// This file is  located in the `seeds/` subdirectory of the project.
struct ImportKaraokeSongs: AsyncMigration {
	/// Required by `Migration` protocol. Reads either a test or production `.ics` file in the
	/// `seeds/` subdirectory, converts the lines into elements of an array, hands that off to
	/// a parser and populates the `Event` database with the `[Event]` array returned.
	///
	/// - Requires: `JoCoKaraokeSongCatalog.txt` file in seeds subdirectory.
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		database.logger.info("Starting karaoke song import")
		// get the songs file. Tab-delimited, each line contains: "ARTIST \t SONG_TITLE \t TAGS \n"
		// Tags can be: "VR" for voice-reduced, M for midi (I think?)
		let songsFilename: String
		do {
			if try Environment.detect().isRelease {
				songsFilename = "JoCoKaraokeSongCatalog.txt"
			}
			else {
				songsFilename = "test-JoCoKaraokeSongCatalog.txt"
			}
			let songsFilePath = Settings.shared.seedsDirectoryPath.appendingPathComponent(songsFilename)
			let songsFile = try String(contentsOfFile: songsFilePath.path, encoding: .utf8)
			var lines = songsFile.components(separatedBy: "\r\n")
			if lines.count < 10 {
				lines = songsFile.components(separatedBy: .newlines)
			}

			// Creating one song at a time is slow, but PSQL chokes on a single command that creates 25000+ songs.
			// So, chunking the creates into batches of 1000.
			for startIndex in stride(from: 0, through: lines.count, by: 1000) {
				let endIndex = min(startIndex + 1000, lines.count)
				var karaokesongs: [KaraokeSong] = []
				for line in startIndex..<endIndex {
					let parts = lines[line].split(separator: "\t")
					if parts.count >= 2 {
						let modifier: String? = parts.count >= 3 ? String(parts[2]) : nil
						let isMidi = modifier == "M"
						let isVR = modifier == "VR"
						karaokesongs.append(
							KaraokeSong(
								artist: String(parts[0]),
								title: String(parts[1]),
								isVoiceRemoved: isVR,
								isMidi: isMidi
							)
						)
					}
				}
				try await karaokesongs.create(on: database)
				database.logger.info("Imported \(endIndex) karaoke songs.")
			}
		}
		catch {
			throw Abort(.internalServerError, reason: "Could not read karaoke songs file.")
		}
	}

	func revert(on database: Database) async throws {
		try await KaraokeSong.query(on: database).delete()
	}
}
