import Vapor
import Fluent


/// A `Migration` that creates `Forum`s for each `Event` in the schedule.

struct CreateEventForums: Migration {    
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
					// date formatter for titles
					let dateFormatter = DateFormatter()
					dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
					dateFormatter.dateFormat = "(E, HH:mm)"
					// create forums
					var forums: [Forum] = []
					for event in events {
						// build title
						let title = dateFormatter.string(from: event.startTime) + " \(event.title)"
						switch event.eventType {
							case .shadow:
							let forum = try Forum(
								title: title,
								category: shadow,
								creator: admin,
								isLocked: false
							)
							forums.append(forum)
							default:
							let forum = try Forum(
								title: title,
								category: official,
								creator: admin,
								isLocked: false
							)
							forums.append(forum)
						}
					}
					// save forums
					return forums.map { $0.save(on: database) }.flatten(on: database.eventLoop).transform(to: ())
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
}
