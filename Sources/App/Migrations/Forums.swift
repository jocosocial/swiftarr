import Vapor
import Fluent


/// A `Migration` that creates an initial set of Twit-arr official `Forum`s.

struct CreateForums: Migration {
    
    /// Required by `Migration` protocol. Creates an initial set of categories for forums.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        // initial set of Twit-arr forums
        var adminForums: [String] = []
        do {
            if (try Environment.detect().isRelease) {
                adminForums = [
                    // forum list here
                ]
            } else {
                // test forums
                adminForums = [
                    "Twit-arr Support",
                    "Twit-arr Feedback"
                ]
            }
        } catch let error {
            fatalError("Environment.detect() failed! error: \(error)")
        }
        // get admin, category IDs
        return User.query(on: database).first().flatMap { (admin) in
            return Category.query(on: database).first().throwingFlatMap { (category) in
				guard let admin = admin,
					admin.username == "admin",
					let category = category,
					category.title == "Twit-arr Support" else {
						fatalError("could not get IDs")
				}
				// create forums
				var forums: [Forum] = []
				for adminForum in adminForums {
					let forum = try Forum(
						title: adminForum,
						category: category,
						creator: admin,
						isLocked: false
					)
					forums.append(forum)
				}
				// save forums
				return forums.map { $0.save(on: database) }.flatten(on: database.eventLoop).transform(to: ())
            }
        }
    }
    
    /// Required by `Migration` protocol, but this isn't a model update, so just return a
    /// pre-completed `Future`.
    ///
    /// - Parameter conn: The database connection.
    /// - Returns: Void.
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("forums").delete()
    }
}
