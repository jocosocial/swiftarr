import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension Barrel: PostgreSQLUUIDModel {}

// model and representations can be passed as HTTP body data
extension Barrel: Content {}

// model can be used as endpoint parameter
extension Barrel: Parameter {}

// model uses default migration, as no constraints can be set
extension Barrel: Migration {}

// MARK: - Timestamping Conformance

extension Barrel {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}
