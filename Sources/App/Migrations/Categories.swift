import Vapor
import Fluent


/// A `Migration` that creates an initial set of categories for `Forum`s.
struct CreateCategories: Migration {  
	struct CategoryCreateInfo {
		var title: String
		var purpose: String
	}
  
    /// Required by `Migration` protocol. Creates an initial set of categories for forums.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
		var categories: [Category] = []
		
		// categories only mods can see and post in
        let moderatorCategories: [CategoryCreateInfo] = [
			.init(title: "Moderators Only", purpose: "Mod Chat. Only Mods can see this."),
			.init(title: "Mods Only Dumpster Fire", purpose: "Mods: Move flamewar theads here"),
        ]
        for modCategory in moderatorCategories {
            let category = Category(title: modCategory.title, purpose: modCategory.purpose, viewAccess: .moderator, 
            		createForumAccess: .moderator)
            categories.append(category)
        }
        
		// categories to which users cannot directly add forums
        let adminCategories: [CategoryCreateInfo] = [
            .init(title: "Event Forums", purpose: "A thread for each Official event"),
			.init(title: "Shadow Event Forums", purpose: "A thread for each Shadow event"),
        ]
        for adminCategory in adminCategories {
            let category = Category(title: adminCategory.title, purpose: adminCategory.purpose, createForumAccess: .moderator)
            categories.append(category)
        }

        // categories to which users can add forums
        let userCategories: [CategoryCreateInfo] = [
            .init(title: "Help Desk", purpose: "Need help? Ask here."),
			.init(title: "General", purpose: "Discuss amongst yourselves"),
            .init(title: "Covid", purpose: "No hate, only hugs. Except for Covid—hate Covid."),
            .init(title: "Activities", purpose: "Things to do that aren't Events. Pokemon, KrakenMail, puzzles..."),
			.init(title: "Safe Space", purpose: "No hate, only hugs"),
			.init(title: "Egype", purpose: "Did a performer do something silly? Do you want to meme about it?"),
			
        ]
        for userCategory in userCategories {
            let category = Category(title: userCategory.title, purpose: userCategory.purpose)
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
