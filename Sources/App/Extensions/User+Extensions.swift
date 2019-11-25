import Vapor
import FluentPostgreSQL
import Authentication

// model uses UUID as primary key
extension User: PostgreSQLUUIDModel {}

// model and representations can be passed as HTTP body data
extension User: Content {}
extension User.Admin: Content {}
extension User.Public: Content {}

// model can be used as endpoint parameter
extension User: Parameter {}

// MARK: - Custom Migration

extension User: Migration {
    /// Required by `Migration` protocol. Creates the table, with unique constraint on `.username`.
    ///
    /// - Parameter connection: A connection to the database, provided automatically.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            builder in
            try addProperties(to: builder)
            // username must be unique
            builder.unique(on: \.username)
        }
    }
}

// MARK: - Timestamping Conformance

extension User {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}

// MARK: - BasicAuthenticatable Conformance

extension User: BasicAuthenticatable {
    /// Required username key for HTTP Basic Authorization.
    static let usernameKey: UsernameKey = \User.username
    /// Required password key for HTTP Basic Authorization.
    static let passwordKey: PasswordKey = \User.password
}

// MARK: - TokenAuthenticatable Conformance

extension User: TokenAuthenticatable {
    /// Required typealias, using `Token` class for HTTP Bearer Authorization.
    typealias TokenType = Token
}

// MARK: - Children

extension User {
    /// The `Barrels`s owned by the user.
    var barrels: Children<User, Barrel> {
        return children(\.ownerID)
    }
    
    /// The `UserNote`s owned by the user.
    var notes: Children<User, UserNote> {
        return children(\.userID)
    }

    /// The child `UserProfile` of the user.
    var profile: Children<User, UserProfile> {
        return children(\.userID)
    }
}

// MARK: - Methods

extension User {
    /// Converts a `User` model to a version that is publicly viewable. Only the ID, username
    /// and timestamp of the last profile update are returned.
    func convertToPublic() throws -> User.Public {
        return try User.Public(
            id: self.requireID(),
            username: self.username,
            updatedAt: self.profileUpdatedAt
        )
    }
}

extension Future where T: User {
    /// Converts a `Future<User>` to a `Future<User.Public>`. This extension provides the
    /// convenience of simply using `user.convertToPublic()` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToPublic() throws -> Future<User.Public> {
        return self.map {
            (user) in
            return try user.convertToPublic()
        }
    }
}
