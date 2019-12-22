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

// MARK: - Functions

extension FezPost {
    /// Converts a `FezPost` model to a version omitting data that is not for public
    /// consumption.
    func convertToData() throws -> FezPostData {
        return try FezPostData(
            postID: self.requireID(),
            authorID: self.authorID,
            text: self.text,
            image: self.image
        )
    }
}

extension Future where T: FezPost {
    /// Convers a `Future<FezPost>` to a `Futured<FezPostData>`. This extension provides
    /// the convenience of simply using `post.convertToData)` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToData() -> Future<FezPostData> {
        return self.map {
            (fezPost) in
            return try fezPost.convertToData()
        }
    }
}
