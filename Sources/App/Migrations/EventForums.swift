import Vapor
import FluentPostgreSQL

/// A `Migration` that creates `Forum`s for each `Event` in the schedule.

struct EventForums: Migration {
    typealias Database = PostgreSQLDatabase
    
    /// Required by `Migration` protocol. Creates a set of forums for the schedule events.
    ///
    /// - Parameter conn: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on conn: PostgreSQLConnection) -> EventLoopFuture<Void> {
        // get admin, category IDs
        return User.query(on: conn).first().flatMap {
            (admin) in
            let officialResult = Category.query(on: conn).filter(\.title, .ilike, "event%").first()
            let shadowResult = Category.query(on: conn).filter(\.title, .ilike, "shadow%").first()
            return flatMap(officialResult, shadowResult) {
                (officialCategory, shadowCategory) in
                // ensure all is fine
                guard let admin = admin,
                    let official = officialCategory,
                    let shadow = shadowCategory,
                    official.title.lowercased() == "event forums",
                    shadow.title.lowercased() == "shadow event forums" else {
                        fatalError("could not create event forums")
                }
                // get events
                return Event.query(on: conn).all().flatMap {
                    (events) in
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
                                categoryID: shadow.requireID(),
                                creatorID: admin.requireID(),
                                isLocked: false
                            )
                            forums.append(forum)
                            default:
                            let forum = try Forum(
                                title: title,
                                categoryID: official.requireID(),
                                creatorID: admin.requireID(),
                                isLocked: false
                            )
                            forums.append(forum)
                        }
                    }
                    // save forums
                    return forums.map { $0.save(on: conn) }.flatten(on: conn).transform(to: ())
                }
            }
        }
    }
    
    /// Required by `Migration` protocol, but this isn't a model update, so just return a
    /// pre-completed `Future`.
    ///
    /// - Parameter conn: The database connection.
    /// - Returns: Void.
    static func revert(on conn: PostgreSQLConnection) -> EventLoopFuture<Void> {
        return .done(on: conn)
    }
}
