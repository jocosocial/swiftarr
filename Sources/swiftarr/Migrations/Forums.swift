import Fluent
import Vapor

/// A `Migration` that creates an initial set of Twit-arr official `Forum`s.

struct CreateForums: AsyncMigration {

	/// Creates an initial set of forum threads in "Twitarr Support".
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		// get admin, category IDs
		guard let admin = try await User.query(on: database).filter(\.$username == "admin").first(),
			let category = try await Category.query(on: database).filter(\.$title == "Twit-arr Support").first()
		else {
			fatalError("could not get IDs")
		}
		// create forums
		let forums: [Forum] = try getAdminForums()
			.map {
				try Forum(title: $0, category: category, creatorID: admin.requireID(), isLocked: false)
			}
		try await forums.create(on: database)
	}

	/// Required by `Migration` protocol, but this isn't a model update, so just return a
	/// pre-completed `Future`.
	///
	/// - Parameter conn: The database connection.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		guard let category = try await Category.query(on: database).filter(\.$title == "Twit-arr Support").first()
		else {
			fatalError("could not get IDs")
		}
		// delete forums
		try await Forum.query(on: database).filter(\.$category.$id == category.requireID())
			.filter(\.$title ~~ getAdminForums()).delete()
	}

	func getAdminForums() -> [String] {
		do {
			if try Environment.detect().isRelease {
				return [
					// forum list here
				]
			}
			else {
				// test forums
				return [
					"Twit-arr Support",
					"Twit-arr Feedback",
				]
			}
		}
		catch let error {
			fatalError("Environment.detect() failed! error: \(error)")
		}
	}
}
