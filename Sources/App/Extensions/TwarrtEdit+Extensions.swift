import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension TwarrtEdit: PostgreSQLUUIDModel {}

// model can be passed as HTTP body data
extension TwarrtEdit: Content {}

// model can be used as endpoint parameter
extension TwarrtEdit: Parameter {}

// MARK: - Custom Migration

extension TwarrtEdit: Migration {
    /// Required by `Migration` protocol. Creates the table, with foreign key constraint
    /// to `Twarrt`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // foreign key contraint to ForumPost
            builder.reference(from: \.twarrtID, to: \Twarrt.id)
        }
    }
}

// MARK: - Timestamping Conformance

extension TwarrtEdit {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
}

// MARK: - Relations

extension TwarrtEdit {
    /// The parent `Twarrt` of the edit.
    var twarrt: Parent<TwarrtEdit, Twarrt> {
        return parent(\.twarrtID)
    }
}
