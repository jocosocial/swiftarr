import Fluent
import Vapor

/// A `Migration` that imports the event schedule from a `schedule.ics` file
/// located in the `seeds/` subdirectory of the project.
struct ImportEvents: AsyncMigration {
	/// Required by `Migration` protocol. Reads either a test or production `.ics` file in the
	/// `seeds/` subdirectory, converts the lines into elements of an array, hands that off to
	/// a parser and populates the `Event` database with the `[Event]` array returned.
	///
	/// - Requires: `schedule.ics` file in seeds subdirectory.
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		// get schedule.ics
		let scheduleFile: String
		do {
			if try Environment.detect().isRelease {
				scheduleFile = "schedule.ics"
			}
			else {
				scheduleFile = "test-schedule.ics"
			}
			// read file as string
			let schedulePath = Settings.shared.seedsDirectoryPath.appendingPathComponent(scheduleFile)
			guard let data = FileManager.default.contents(atPath: schedulePath.path),
				let dataString = String(bytes: data, encoding: .utf8)
			else {
				fatalError("Could not read schedule file.")
			}
			// parse to events
			try await EventParser().parse(dataString).create(on: database)
		}
		catch let error {
			fatalError("Environment.detect() failed! error: \(error)")
		}
	}

	/// Required by `Migration` protocol. Deletes all schedule events in the database. Running this migration revert should
	/// delete all `EventFavorite`s, but won't delete Event `Forum`s.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		try await Event.query(on: database).delete()
	}
}
