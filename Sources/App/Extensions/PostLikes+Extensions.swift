import Vapor
import FluentPostgreSQL

// MARK: - Custom Migration

extension PostLikes: Migration {
    /// Required by `Migration` protocol. Creates the table, with foreign key constraints
    /// to `User` and `ForumPost`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // foreign key constraint to User
            builder.reference(from: \.userID, to: \User.id, onDelete: .cascade)
            // foreign key constrain to ForumPost
            builder.reference(from: \.postID, to: \ForumPost.id, onDelete: .cascade)
        }
    }
}
