import Vapor
import FluentPostgreSQL

// model uses UUID as primary key
extension ForumEdit: PostgreSQLUUIDModel {}

// model can be passed as HTTP body data
extension ForumEdit: Content {}

// model can be used as endpoint parameter
extension ForumEdit: Parameter {}

// MARK: - Custom Migration

extension ForumEdit: Migration {
    /// Required by `Migration` protocol. Creates the table, with foreign key constraint
    /// to `ForumPost`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // foreign key contraint to ForumPost
            builder.reference(from: \.postID, to: \ForumPost.id)
        }
    }
}

// MARK: - Timestamping Conformance

extension ForumEdit {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
}

// MARK: - Parent

extension ForumEdit {
    /// The parent `ForumPost` of the edit.
    var profile: Parent<ForumEdit, ForumPost> {
        return parent(\.postID)
    }
}

