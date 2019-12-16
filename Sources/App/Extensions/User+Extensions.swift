import Vapor
import FluentPostgreSQL
import Authentication

// model uses UUID as primary key
extension User: PostgreSQLUUIDModel {}

// model can be passed as HTTP body data
extension User: Content {}

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

// MARK: - Relations

extension User {
    /// The child `Barrels`s owned by the user.
    var barrels: Children<User, Barrel> {
        return children(\.ownerID)
    }
    
    /// The child `Forum`s created by the user.
    var forums: Children<User, Forum> {
        return children(\.creatorID)
    }
    
    /// The sibling `ForumPost`s "liked" by the user.
    var likes: Siblings<User, ForumPost, PostLikes> {
        return siblings()
    }
    
    /// The child `UserNote`s owned by the user.
    var notes: Children<User, UserNote> {
        return children(\.userID)
    }

    /// The child `UserProfile` of the user.
    var profile: Children<User, UserProfile> {
        return children(\.userID)
    }
}

// MARK: - Functions

extension User {
    /// Returns a list of IDs of all accounts associated with the `User`. If user is a primary
    /// account (has no `.parentID`) it returns itself plus any sub-accounts. If user is a
    /// sub-account, it determines its parent, then returns the parent and all sub-accounts.
    ///
    /// - Parameter req: The incoming request `Container`, which provides the `EventLoop` on
    ///   which the query must be run.
    /// - Returns: `[UUID]` containing all the user's associated IDs.
    func allAccountIDs(on req: Request) -> Future<[UUID]> {
        let parent = self.parentID != nil ? self.parentID : self.id
        return User.query(on: req).group(.or) {
            (or) in
            or.filter(\.id == parent)
            or.filter(\.parentID == parent)
        }.all()
            .map {
                (users) in
                return try users.map { try $0.requireID() }
        }
    }
    
    /// Converts a `User` model to a version that is publicly viewable. Only the ID, username
    /// and timestamp of the last profile update are returned.
    func convertToInfo() throws -> UserInfo {
        return try UserInfo(
            userID: self.requireID(),
            username: self.username,
            updatedAt: self.profileUpdatedAt
        )
    }
    
    /// Returns the parent `User` of the user sending the request. If the requesting user has
    /// no parent, the user itself is returned.
    ///
    /// - Parameter req: The incoming request `Container`, which provides reference to the
    ///   sending user.
    func parentAccount(on req: Request) throws -> Future<User> {
        let parentID = self.parentID != nil ? self.parentID : self.id
        guard let userID = parentID else {
            throw Abort(.internalServerError, reason: "parent ID not found")
        }
        return User.find(userID, on: req)
            .unwrap(or: Abort(.internalServerError, reason: "parent not found"))
            .map {
                (user) in
                return user
        }
    }
    
    /// Converts a `User` model to a `SeaMonkey` representation.
    func convertToSeaMonkey() throws -> SeaMonkey {
        return try SeaMonkey(
            userID: self.requireID(),
            username: "@\(self.username)")
    }
}

extension Future where T: User {
    /// Converts a `Future<User>` to a `Future<UserInfo>`. This extension provides the
    /// convenience of simply using `user.convertToInfo()` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToInfo() throws -> Future<UserInfo> {
        return self.map {
            (user) in
            return try user.convertToInfo()
        }
    }
    
    /// Converts a `Future<User>` to a `Future<SeaMonkey>`. This extension provides the
    /// convenience of simply using `user.convertToSeaMonkey()` and allowing the compiler
    /// to choose the appropriate version for the context.
    func convertToSeaMonkey() throws -> Future<SeaMonkey> {
        return self.map {
            (user) in
            return try user.convertToSeaMonkey()
        }
    }
}
