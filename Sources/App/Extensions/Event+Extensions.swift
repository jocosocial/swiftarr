import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension Event: PostgreSQLUUIDModel {}

// model can be passed as HTTP body data
extension Event: Content {}

// model can be used as endpoint parameter
extension Event: Parameter {}

// MARK: - Custom Migration

extension Event: Migration {
    /// Required by `Migration` protocol. Creates the table, with unique  constraint on `.uid`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // uid must be unique
            builder.unique(on: \.uid)
        }
    }
}

// MARK: - Timestamping Conformance

extension Event {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}

// MARK: - Functions

extension Event {
    /// Converts an `Event` model to a version omitting data that is of no interest to a user.
    func convertToData(withFavorited tagged: Bool) throws -> EventData {
        return try EventData(
            eventID: self.requireID(),
            title: self.title,
            description: self.info,
            startTime: self.startTime,
            endTime: self.endTime,
            location: self.location,
            eventType: self.eventType.label,
            forum: self.forumID,
            isFavorite: tagged
        )
    }
}

extension Future where T: Event {
    /// Converts a `Future<Event>` to a `Future<EventData>`. This extension provides the
    /// convenience of simply using `event.convertToData()` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToData(withFavorited tagged: Bool) throws -> Future<EventData> {
        return self.map {
            (event) in
            return try event.convertToData(withFavorited: tagged)
        }
    }
}
