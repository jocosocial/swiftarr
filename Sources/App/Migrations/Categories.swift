import Vapor
import Fluent


/// A `Migration` that creates an initial set of categories for `Forum`s.
struct CreateCategories: AsyncMigration {  
	struct CategoryCreateInfo {
		var title: String
		var purpose: String
		var viewAccess: UserAccessLevel
		var createAccess: UserAccessLevel
	}
  
	/// Required by `Migration` protocol. Creates an initial set of categories for forums.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {		
		let categories: [Category] = [
			// categories only mods can see and post in
			.init(title: "Moderators Only", purpose: "Mod Chat. Only Mods can see this.", viewAccess: .moderator, createForumAccess: .moderator),
			.init(title: "Mods Only Dumpster Fire", purpose: "Mods: Move flamewar theads here.", viewAccess: .moderator, createForumAccess: .moderator),

			// categories in which users cannot add forums but can post in existing forums
			.init(title: "Event Forums", purpose: "A thread for each Official event.", createForumAccess: .moderator, isEventCategory: true),
			.init(title: "Shadow Event Forums", purpose: "A thread for each Shadow event.", createForumAccess: .moderator, isEventCategory: true),

			// categories in which users can add forums
			.init(title: "Help Desk", purpose: "Need help? Ask here."),
			.init(title: "General", purpose: "Discuss amongst yourselves."),
			.init(title: "Covid", purpose: "No hate, only hugs. Except for Covid—hate Covid."),
			.init(title: "Activities", purpose: "Things to do that aren't Events. Pokemon, KrakenMail, puzzles..."),
			.init(title: "Safe Space", purpose: "No hate, only hugs."),
			.init(title: "Egype", purpose: "Did a performer do something silly? Do you want to meme about it?"),
			
			// Categories restricted to specific UserRoleTypes
			.init(title: "Shutternauts", purpose: "🧑 📸:joco:, 📸:pirate:, 📸:ship:", requiredRole: .shutternaut)
		]

		// save categories
		try await categories.create(on: database)
	}
	
	/// Undoes this migration, deleting all categories.
	///
	/// - Parameter conn: The database connection.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		try await Category.query(on: database).delete()
	}
}

/// A `Migration` that initializes the ForumCount field in each category. This migration should run after
/// all the migrations that generate forum threads.
struct SetInitialCategoryForumCounts: AsyncMigration {
	/// Initializes the cached `forumCount` value in each category.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		let categories = try await Category.query(on: database).with(\.$forums).all()
		for cat in categories {
			cat.forumCount = Int32(cat.forums.count)
			try await cat.save(on: database)
		}
	}

	func revert(on database: Database) async throws {
		// Nothing to do, really.
	}
}

struct CreateCategoriesV2: AsyncMigration {  
	struct CategoryCreateInfo {
		var title: String
		var purpose: String
		var viewAccess: UserAccessLevel
		var createAccess: UserAccessLevel
	}
  
	/// Required by `Migration` protocol. Creates an initial set of categories for forums.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {		
		let categories: [Category] = [
			.init(title: "Where and When", purpose: "Cruise News You Can Use", createForumAccess: .moderator, isEventCategory: false),
		]
		try await categories.create(on: database)
	}
	
	/// Undoes this migration, deleting all categories.
	///
	/// - Parameter conn: The database connection.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		try await Category.query(on: database).filter(\.$title == "Where and When").delete()
	}
}

struct RenameWhereAndWhen: AsyncMigration {   
	/// Required by `Migration` protocol. Renames the "Where and When" category to "Splashdot"
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {		
		try await Category.query(on: database)
    		.set(\.$title, to: "Splashdot")
			.set(\.$purpose, to: "News for cruise, stuff that matters - Official JoCo Cruise Daily Newsletter.")
    		.filter(\.$title == "Where and When")
    		.update()
	}
	
	/// Undoes this migration, renaming the category back to "Where and When"
	///
	/// - Parameter conn: The database connection.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		try await Category.query(on: database)
    		.set(\.$title, to: "Where and When")
			.set(\.$purpose, to: "Cruise News You Can Use")
    		.filter(\.$title == "Splashdot")
    		.update()
	}
}