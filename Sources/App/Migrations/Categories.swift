import Vapor
import Fluent


/// A `Migration` that creates an initial set of categories for `Forum`s.
struct CreateCategories: Migration {    
    /// Required by `Migration` protocol. Creates an initial set of categories for forums.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        // categories to which users cannot directly add forums
        let adminCategories: [String] = [
            "Twit-arr Support",
            "Event Forums",
            "Shadow Event Forums"
        ]
        // categories to which users can add forums
        var userCategories: [String] = []
        do {
            if (try Environment.detect().isRelease) {
                userCategories = [
                    // category list here
                ]
            } else {
                // test categories
                userCategories = ["Test 1", "Test 2"]
            }
        } catch let error {
            fatalError("Environment.detect() failed! error: \(error)")
        }
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
        return categories.map { $0.save(on: database) }
            .flatten(on: database.eventLoop)
    }
    
    /// Required by `Migration` protocol, but this isn't a model update, so just return a
    /// pre-completed `Future`.
    ///
    /// - Parameter conn: The database connection.
    /// - Returns: Void.
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("categories").delete()
    }
}

/// A `Migration` that initializes the ForumCount field in each category. This migration should run after
/// all the migrations that generate forum threads.
struct SetInitialCategoryForumCounts: Migration {
	/// Required by `Migration` protocol.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
    	Category.query(on: database).with(\.$forums).all().flatMap { categories in
    		let futures = categories.map { cat -> EventLoopFuture<Void> in
    			cat.forumCount = Int32(cat.forums.count)
				return cat.save(on: database)
			}
			return futures.flatten(on: database.eventLoop)
    	}
    }

    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("categories").delete()
    }
}
