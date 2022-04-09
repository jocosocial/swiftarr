import Vapor
import Fluent


/// A `Migration` that creates `Forum`s for each `Event` in the schedule.

struct SetInitialEventForums: AsyncMigration {	
	/// Required by `Migration` protocol. Creates a set of forums for the schedule events.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func prepare(on database: Database) async throws {
		// get admin, category IDs
		guard let admin = try await User.query(on: database).filter(\.$username == "admin").first(),
				let officialCategory = try await Category.query(on: database).filter(\.$title, .custom("ILIKE"), "event%").first(),
				let shadowCategory = try await Category.query(on: database).filter(\.$title, .custom("ILIKE"), "shadow%").first() else {
			fatalError("Could not set up event forums; couldn't find admin user or the event categories")
		}
		// ensure all is fine
		guard officialCategory.title.lowercased() == "event forums", shadowCategory.title.lowercased() == "shadow event forums" else {
			fatalError("could not create event forums")
		}
		// get events
		let events = try await Event.query(on: database).all()
		for event in events {
			let forum = try SetInitialEventForums.buildEventForum(event, creatorID: admin.requireID(), 
					shadowCategory: shadowCategory, officialCategory: officialCategory)
			try await forum.save(on: database)
			// Build an initial post in the forum with information about the event, and
			// a callout for posters to discuss the event.
			let postText = SetInitialEventForums.buildEventPostText(event)
			let infoPost = try ForumPost(forum: forum, authorID: admin.requireID(), text: postText)
		
			// Associate the forum with the event
			event.$forum.id = forum.id
			event.$forum.value = forum
			try await event.save(on: database)
			try await infoPost.save(on: database)
		}
	}
	
	/// Deletes all the event forums created by this migration.
	///
	/// - Parameter database: A connection to the database, provided automatically.
	/// - Returns: Void.
	func revert(on database: Database) async throws {
		guard let officialCategory = try await Category.query(on: database).filter(\.$title, .custom("ILIKE"), "event%").first(),
				let shadowCategory = try await Category.query(on: database).filter(\.$title, .custom("ILIKE"), "shadow%").first() else {
			fatalError("Could not  revert event forums; couldn't find the event categories")
		}
		try await officialCategory.$forums.query(on: database).delete()
		try await shadowCategory.$forums.query(on: database).delete()
		let events = try await Event.query(on: database).all()
		for event in events {
			event.$forum.id = nil
			try await event.save(on: database)
		}
	}
	
	static func buildEventForum(_ event: Event, creatorID: UUID, shadowCategory: Category, officialCategory: Category) throws -> Forum {
		// date formatter for titles
		let dateFormatter = DateFormatter()
		dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
		dateFormatter.dateFormat = "(E, HH:mm)"
		// build title and forum
		let title = dateFormatter.string(from: event.startTime) + " \(event.title)"
		let forum = try Forum(title: title, category: event.eventType == .shadow ? shadowCategory : officialCategory,
				creatorID: creatorID, isLocked: false)
		return forum
	}
	
	/// Builds a text string for posting to the Events forum thread for an Event. This post is created by `admin`.
	/// On initial Events migration, each Event gets a thread in the Events category associated with it, and each thread
	/// gets an initial post. 
	///
	/// When Schedule Updating is added, schedule updates will need to modify the initial post for
	/// events whose data get modified. The post modifications should include e.g. "UPDATED TIME" or
	/// "UPDATED LOCATION".
	/// 
	/// - Parameter event: The event for which to produce a blurb.
	/// - Returns: A string suitable for adding to a ForumPost, describing the event.
	static func buildEventPostText(_ event: Event) -> String {

		let dateFormatter = DateFormatter()
		dateFormatter.dateFormat = "E, h:mm a"
		dateFormatter.locale = Locale(identifier: "en_US")
		dateFormatter.timeZone = TimeZone(abbreviation: "EST")
		var timeString = dateFormatter.string(from: event.startTime)

		// Omit endTime date if same as startTime
		dateFormatter.dateFormat = "E"
		if dateFormatter.string(from: event.startTime) == dateFormatter.string(from: event.endTime) {
			dateFormatter.dateFormat = "h:mm a z"
		}
		else {
			dateFormatter.dateFormat = "E, h:mm a"
		}
		timeString.append(" - \(dateFormatter.string(from: event.endTime))")
		
		let postText = """
				\(event.title)
				
				\(event.eventType.label) Event
				\(timeString)
				\(event.location)
				
				\(event.info)
				"""

		return postText
	}
}
