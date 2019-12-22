import Vapor
import FluentPostgreSQL

// model uses Int as primary key
extension FezPost: PostgreSQLModel {}

// model can be passed as HTTP body content
extension FezPost: Content {}

// model can be used as endpoint parameter
extension FezPost: Parameter {}

extension FezPost: Migration {
    /// Required by `Migration` protocol. Creates the table, with foreign key  constraint
    /// to .friendlyFez `Barrel`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // foreign key constraint to Barrel of type .friendlyFez
            builder.reference(from: \.fezID, to: \Barrel.id)
        }
    }
}

// MARK: - Timestamping Conformance

extension FezPost {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}
