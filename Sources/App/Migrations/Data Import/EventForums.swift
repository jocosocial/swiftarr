import Vapor
import Fluent


/// A `Migration` that creates `Forum`s for each `Event` in the schedule.

struct SetInitialEventForums: Migration {    
    /// Required by `Migration` protocol. Creates a set of forums for the schedule events.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func prepare(on database: Database) -> EventLoopFuture<Void> {
        // get admin, category IDs
        return User.query(on: database).first().flatMap {
            (admin) in
            let officialResult = Category.query(on: database).filter(\.$title, .custom("ILIKE"), "event%").first()
            let shadowResult = Category.query(on: database).filter(\.$title, .custom("ILIKE"), "shadow%").first()
            return EventLoopFuture.whenAllSucceed([officialResult, shadowResult], on: database.eventLoop).flatMap {
               categories in
                // ensure all is fine
                guard let admin = admin,
                    let official = categories[0],
                    let shadow = categories[1],
                    official.title.lowercased() == "event forums",
                    shadow.title.lowercased() == "shadow event forums" else {
                        fatalError("could not create event forums")
                }
                // get events
                return Event.query(on: database).all().throwingFlatMap { events in
					// create forums
					var futures: [EventLoopFuture<Void>] = []
					for event in events {
						let forum = try SetInitialEventForums.buildEventForum(event, creator: admin, 
								shadowCategory: shadow, officialCategory: official)
						futures.append(forum.save(on: database).throwingFlatMap {
							// Build an initial post in the forum with information about the event, and
							// a callout for posters to discuss the event.
							let postText = SetInitialEventForums.buildEventPostText(event)
							let infoPost = try ForumPost(forum: forum, author: admin, text: postText)
						
							// Associate the forum with the event
							event.$forum.id = forum.id
							event.$forum.value = forum
							return event.save(on: database).flatMap {
								return infoPost.save(on: database)
							}
						})
					}
					return futures.flatten(on: database.eventLoop)
                }
            }
        }
    }
    
    /// Required by `Migration` protocol, but this isn't a model update, so just return a
    /// pre-completed `Future`.
    ///
    /// - Parameter database: A connection to the database, provided automatically.
    /// - Returns: Void.
    func revert(on database: Database) -> EventLoopFuture<Void> {
        database.schema("eventforums").delete()
    }
    
    static func buildEventForum(_ event: Event, creator: User, shadowCategory: Category, officialCategory: Category) throws -> Forum {
		// date formatter for titles
		let dateFormatter = DateFormatter()
		dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
		dateFormatter.dateFormat = "(E, HH:mm)"
		// build title and forum
		let title = dateFormatter.string(from: event.startTime) + " \(event.title)"
		let forum = try Forum(title: title, category: event.eventType == .shadow ? shadowCategory : officialCategory,
				creator: creator, isLocked: false)
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
