import Vapor
import FluentPostgreSQL

// model uses Int as primary key
extension Category: PostgreSQLModel {}

// model can be passed as HTTP body data
extension Category: Content {}

// model can be used as endpoint parameter
extension Category: Parameter {}

// MARK: - Custom Migration

extension Category: Migration {
    /// Required by `Migration` protocol. Creates the table, with unique  constraint on `.title`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // uid must be unique
            builder.unique(on: \.title)
        }
    }
}

// MARK: - Timestamping Conformance

extension Category {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}
