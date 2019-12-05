import Vapor
import FluentPostgreSQL

/// A `Migration` that creates an initial set of categories for `Forums`.

struct Categories: Migration {
    typealias Database = PostgreSQLDatabase
    
    /// Required by `Migration` protocol. Creates an initial set of categories for forums.
    ///
    /// - Parameter connection: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> EventLoopFuture<Void> {
        // categories to which users cannot directly add forums
        let adminCategories: [String] = [
            "Twit-arr Support",
            "Event Forums",
            "Shadow Event Forums"
        ]
        // categories to which users can add forums
        let userCategories: [String] = [
            "Test 1",
            "Test 2"
        ]
        // create categories
        var categories: [Category] = []
        for adminCategory in adminCategories {
            let category = Category(title: adminCategory, isRestricted: true)
            categories.append(category)
        }
        for userCategory in userCategories {
            let category = Category(title: userCategory, isRestricted: false)
            categories.append(category)
        }
        // save categories
        return categories.map { $0.save(on: connection) }
            .flatten(on: connection)
            .transform(to: ())
    }
    
    /// Required by`Migration` protocol, but no point removing the categories, so
    /// just return a pre-completed `Future`.
    ///
    /// - Parameter connection: The database connection.
    /// - Returns: Void.
    static func revert(on connection: PostgreSQLConnection) -> Future<Void> {
        return .done(on: connection)
    }
}
