import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension Report: PostgreSQLUUIDModel {}

// model can be passed as HTTP body data
extension Report: Content {}

// model can be used as endpoint parameter
extension Report: Parameter {}

// MARK: - Custom Migration

extension Report: Migration {
    /// Required by `Migration` protocol. Creates the table, with foreign key constraint
    /// to `User`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // foreign key contraint to User
            builder.reference(from: \.submitterID, to: \User.id)
        }
    }
}

// MARK: - Timestamping Conformance

extension Report {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
}

