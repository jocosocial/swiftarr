import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension UserNote: PostgreSQLUUIDModel {}

// model and representations can be passed as HTTP body data
extension UserNote: Content {}

// model can be used as endpoint parameter
extension UserNote: Parameter {}

// MARK: - Custom Migration

extension UserNote: Migration {
    /// Required by `Migration` protocol. Creates the table, with foreign key constraints
    /// to `User` and `UserProfile`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // foreign key contraint to User
            builder.reference(from: \.userID, to: \User.id)
            // foreign key constraint to UserProfile
            builder.reference(from: \.profileID, to: \UserProfile.id)
        }
    }
}

// MARK: - Timestamping Conformance

extension UserNote {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt}
}

// MARK: - Parents

extension UserNote {
    /// The parent `User` of the note.
    var user: Parent<UserNote, User> {
        return parent(\.userID)
    }
}

extension UserNote {
    /// The parent `UserProfile` of the note.
    var profile: Parent<UserNote, UserProfile> {
        return parent(\.profileID)
    }
}
