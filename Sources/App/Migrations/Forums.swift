import Vapor
import FluentPostgreSQL

/// A `Migration` that creates an initial set of Twit-arr official `Forum`s.

struct Forums: Migration {
    typealias Database = PostgreSQLDatabase
    
    /// Required by `Migration` protocol. Creates an initial set of categories for forums.
    ///
    /// - Parameter conn: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on conn: PostgreSQLConnection) -> EventLoopFuture<Void> {
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
        return User.query(on: conn).first().flatMap {
            (admin) in
            return Category.query(on: conn).first().flatMap {
                (category) in
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
                        categoryID: category.requireID(),
                        creatorID: admin.requireID(),
                        isLocked: false
                    )
                    forums.append(forum)
                }
                // save forums
                return forums.map { $0.save(on: conn) }.flatten(on: conn).transform(to: ())
            }
        }
    }
    
    /// Required by`Migration` protocol, but no point removing the forums, so just return
    /// a pre-completed `Future`.
    ///
    /// - Parameter conn: The database connection.
    /// - Returns: Void.
    static func revert(on conn: PostgreSQLConnection) -> Future<Void> {
        return .done(on: conn)
    }
}
