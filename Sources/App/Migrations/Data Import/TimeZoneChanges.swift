import Vapor
import Fluent


/// A `Migration` that imports timezone change data located in the `seeds/` subdirectory of the project.
/// The `time-zone-changes.txt` file should contain tab-delimited data, 3 fields on each line:
/// 	`20220305T070000Z	-5	EST`
/// This line says that on March 5, 2022 at 2:00 AM EST (7 AM UTC), the boat will be in the EST timezone, with a timezone offset of -5 hours.
/// Because we usually use the previous year's schedule data for testing until we get the next year's schedule, it's intended that the `time-zone-changes.txt` file
/// will have more than one sailing's worth of timezone changes in it.
/// 
struct ImportTimeZoneChanges: AsyncMigration {	
	/// Required by `Migration` protocol. Reads in a TSV file.
	///
	/// - Requires: `time-zone-changes.txt` file in seeds subdirectory.
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		try await loadTZFile(on: database)
	}

	/// Reads and parses the `time-zone-changes.txt` file, erases previous `TimeZoneChange` entries in db, replaces with new entries from file.
	/// Usable both within Migrations and while server is up and running.
	/// 
	/// - Parameter database: A connection to the database.
	/// - Parameter isMigrationTime: TRUE if the app was launched with a `migrate` command. Affects how errors are handled.
	/// - Returns: Void.
	func loadTZFile(on database: Database, isMigrationTime: Bool = true) async throws {
		// get timezonechanges.txt
		do {
			let formatter = ISO8601DateFormatter()
			formatter.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withTimeZone]
			
			// read file as string
			let tzChangesPath = Settings.shared.seedsDirectoryPath.appendingPathComponent("time-zone-changes.txt")
			guard let data = FileManager.default.contents(atPath: tzChangesPath.path),
				let dataString = String(bytes: data, encoding: .utf8) else {
					throw("Could not read time zone changes file.")
			}
			// parse to TimeZoneChanges
			let lines = dataString.components(separatedBy: "\n")
			let tzChanges: [TimeZoneChange] = try lines.compactMap { line in
				let values = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
				guard values.count >= 3 else { return nil }
				let startTimeStr = values[0]
				if startTimeStr.hasPrefix("#") || startTimeStr.hasPrefix("//") { return nil }
				
				if let startTime = formatter.date(from: startTimeStr) {
					return try TimeZoneChange(startTime: startTime, name: values[1], id: values[2])
				}
				return nil
			}
			guard tzChanges.count > 0 else {
				throw("Found 0 entries in the timezonechanges.txt file. We must have at least an initial timezone.")
			}
			// Delete all the current timezone change data
			try await revert(on: database)
			// Replace with the new stuff
			try await tzChanges.create(on: database)
			// Build a TimeZoneChangeSet with the new data, and store it in Settings.
			let tzSet = try await TimeZoneChangeSet(database)
			Settings.shared.timeZoneChanges = tzSet
		} catch let error {
			// We need to stop the migration process (via FatalError) if we're doing a `run migrate` operation, as other
			// migrations may depend on this one succeeding. If this is called to update the TZ file while the server is running,
			// it's a regular thrown error instead.
			if isMigrationTime {
				fatalError("Error thrown while importing time zone change data. error: \(error)")
			}
			else {
				throw error
			}
		}
	}
	
	/// Required by `Migration` protocol. Deletes all timezone changes in the database. 
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		try await TimeZoneChange.query(on: database).delete()
	}
}
