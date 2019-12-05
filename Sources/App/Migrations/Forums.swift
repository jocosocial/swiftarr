import Vapor
import FluentPostgreSQL

/// A `Migration` that creates an initial set of Twit-arr official `Forum`s.

struct Forums: Migration {
    typealias Database = PostgreSQLDatabase
    
    /// Required by `Migration` protocol. Creates an initial set of categories for forums.
    ///
    /// - Parameter connection: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> EventLoopFuture<Void> {
        // initial set of Twit-arr forums
        let adminForums: [String] = [
            "Twit-arr Support",
            "Twit-arr Feedback"
        ]
        // get admin, category IDs
        return User.query(on: connection).first().flatMap {
            (admin) in
            return Category.query(on: connection).first().flatMap {
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
                return forums.map { $0.save(on: connection) }
                    .flatten(on: connection)
                    .transform(to: ())
            }
        }
    }
    
    /// Required by`Migration` protocol, but no point removing the forums, so just return
    /// a pre-completed `Future`.
    ///
    /// - Parameter connection: The database connection.
    /// - Returns: Void.
    static func revert(on connection: PostgreSQLConnection) -> Future<Void> {
        return .done(on: connection)
    }
}
