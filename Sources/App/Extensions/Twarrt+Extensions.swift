import Vapor
import FluentPostgreSQL

// model uses Int as primary key
extension Twarrt: PostgreSQLModel {}

// model can be passed as HTTP body data
extension Twarrt: Content {}

// model can be used as endpoint paramter
extension Twarrt: Parameter {}

extension Twarrt: Migration {}

// MARK: - Timestamping Conformance

extension Twarrt {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}

// MARK: - Relations

// MARK: - Functions
