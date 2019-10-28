import Foundation
import Vapor
import FluentPostgreSQL

/// All accounts are of class User.
///
/// The terms "account" and "sub-account" used throughout this documentatiion are all
/// instances of User. The terms "primary account" and "parent account" are used
/// interchangeably to refer to any account that is not a sub-account.
///
/// A primary account holds the verification token and access level, and all
/// sub-accounts (if any) inherit these two credentials.
///
/// `User.id` and `User.parentID` are provisioned automatically, by the model protocols
/// and `UsersController` account creation handlers respectively.

final class User: Codable {
    // MARK: Properties
    
    /// The user's ID, provisioned automatically.
    var id: UUID?
    
    /// The user's publicly viewable username.
    var username: String
    
    /// The user's password, encrypted to BCrypt hash value.
    var password: String
    
    /// The user's recovery key, encrypted to BCrypt hash value.
    var recoveryKey: String
    
    /// The registration code (or other identifier) used to activate the user
    /// for full read-write access.
    var verification: String?
    
    /// If a sub-account, the ID of the User to which this user is associated,
    /// provisioned by `UsersController` handlers during creation.
    var parentID: UUID?
    
    /// The user's `UserAccessLevel`, set to `.unverified` at time of creation,
    /// or the parent's access level if a sub-account.
    var accessLevel: UserAccessLevel
    
    /// An array of keywords on which the user can mute a post.
    var keywordMutes: [String]
    
    /// Cumulative number of reports submitted on user's posts.
    var reports: Int
    
    // MARK: Timestampable/SoftDeletable
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?
    
    // MARK: Initialization
    
    /// Initializes a new User.
    ///
    /// - Parameters:
    ///   - username: The user's username, unadorned (e.g. "grundoon", not "@grundoon").
    ///   - password: A `BCrypt` hash of the user's password. Please **never** store actual
    /// passwords.
    ///   - recoveryKey: A `BCrypt` hash of the user's recovery key. Please **never** store
    /// the actual key.
    ///   - verification: A token of known identity, such as a provided code or a verified email
    /// address. `nil` if not yet verified.
    ///   - parentID: If a sub-account, the `id` of the master acount, otherwise `nil`.
    ///   - accessLevel: The user's access level (see `UserAccessLevel`).
    ///   - keywordMutes: The user's list of keywords that mute posts, initially empty.
    ///   - reports: The total number of reports made on the user's posts, initially 0.
    init(
        username: String,
        password: String,
        recoveryKey: String,
        verification: String? = nil,
        parentID: UUID? = nil,
        accessLevel: UserAccessLevel,
        keywordMutes: [String] = [],
        reports: Int = 0
    ) {
        self.username = username
        self.password = password
        self.recoveryKey = recoveryKey
        self.verification = verification
        self.parentID = parentID
        self.accessLevel = accessLevel
        self.keywordMutes = keywordMutes
        self.reports = reports
    }
    
    // MARK: Codable Representations
    
    /// Used for administrative functions.
    final class Admin: Codable {
        // MARK: Properties
        /// The user's ID.
        var id: UUID?
        /// The user's username.
        var username: String
        /// The user's identifying token.
        var verification: String?
        /// The user's parent user, if a sub-account.
        var parentID: UUID?
        /// The user's access level.
        var accessLevel: UserAccessLevel
        /// The user's muting keywords.
        var keywordMutes: [String]
        /// Cumulative number of reports on the user's posts.
        var reports: Int
        /// Timestamp of user creation.
        var createdAt: Date?
        /// Timestamp of last update to the model.
        var updatedAt: Date?
        /// Timestamp of the user's soft-deletion.
        var deletedAt: Date?
        
        // MARK: Initialization
        /// Initializes a User.Admin model.
        ///
        /// - Parameters:
        ///   - id: The user's ID.
        ///   - username: The user's username.
        ///   - verification: The user's identifying token.
        ///   - parentID: The user's parent user, if a sub-account
        ///   - accessLevel: The user's `UserAccessLevel`.
        ///   - keywordMutes: An array of keywords the user uses to mute others' posts.
        ///   - reports: Cumulative number of reports on the user's posts.
        ///   - createdAt: Timestamp of user creation.
        ///   - updatedAt: Timestamp of last update to the user's model.
        ///   - deletedAt: Timestamp of the model's soft-deletion.
        init(
            id: UUID?,
            username: String,
            verification: String?,
            parentID: UUID?,
            accessLevel: UserAccessLevel,
            keywordMutes: [String],
            reports: Int,
            createdAt: Date?,
            updatedAt: Date?,
            deletedAt: Date?
        ) {
            self.id = id
            self.username = username
            self.verification = verification
            self.parentID = parentID
            self.accessLevel = accessLevel
            self.keywordMutes = keywordMutes
            self.reports = reports
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }
    
    /// Used for posted content headers.
    final class Header: Codable {
        // MARK: Properties
        /// The user's ID.
        var id: UUID?
        /// The string for displaying the user's identity.
        var displayedName: String
        /// The filename of the user's profile image.
        var image: String
        
        // MARK: Initialization
        /// Initializes a User.Header model.
        ///
        /// - Parameters:
        ///   - id: The user's ID.
        ///   - displayedName: The string for displaying the user's identity.
        ///   - image: The filename of the user's profile image.
        init(id: UUID?, displayedName: String, image: String) {
            self.id = id
            self.displayedName = displayedName
            self.image = image
        }
    }
    
    /// Used for general identification and reference.
    final class Public: Codable {
        // MARK: Properties
        /// The user's ID.
        var id: UUID?
        /// The user's username.
        var username: String
        /// Timestamp of last update to the user's profile.
        var updatedAt: Date
        
        // MARK: Initialization
        /// Initializes a User.Public model.
        ///
        /// - Parameters:
        ///   - id: The user's ID.
        ///   - username: The user's username.
        ///   - updatedAt: Timestamp of last update to the user's profile.
        init(id: UUID?, username: String, updatedAt: Date) {
            self.id = id
            self.username = username
            self.updatedAt = updatedAt
        }
    }
}

/// All API endpoints are protected by a mimimum user access level.
/// This `enum` structure is ordered and should *never* be modified when
/// working with stored production `User` data – bad things will happen.
enum UserAccessLevel: UInt8, PostgreSQLRawEnum {
    /// A user account that has not yet been activated. (read-only, limited)
    case unverified
    /// A user account that has been banned. (read-only, limited)
    case banned
    /// A `.verified` user account that has triggered Moderator review. (read-only)
    case quarantined
    /// A user account that has been activated for full read-write access.
    case verified
    /// An account whose owner is part of the Moderator Team.
    case moderator
    /// An account officially associated with Management, has access to all `.moderator`
    /// and a subset of `.admin` functions (the non-destructive ones).
    case tho
    /// An Administrator account, unrestricted access.
    case admin
}

// model uses UUID as primary key
extension User: PostgreSQLUUIDModel {}      // model uses UUID as primary key

// MARK: Custom Migration
extension User: Migration {                 // model uses custom migreation
    /// Creates the table, with unique constraint on `.username`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: A Void promise.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            builder in
            try addProperties(to: builder)
            builder.unique(on: \.username)  // username must be unique
        }
    }
}

// model can be passed as HTTP body data
extension User: Content {}

// model can used as endpoint parameter
extension User: Parameter {}

// model uses timestamps and soft deletes
extension User {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    
    /// Required key for `\.deletedAt` functionalilty.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}

// MARK: BasicAuthenticatable Conformance
//extension User: BasicAuthenticatable {
//    /// Required username key for HTTP Basic Authorization.
//    static let usernameKey: UsernameKey = \User.username
//    /// Required password key for HTTP Basic Authorization.
//    static let passwordKey: PasswordKey = \User.password
//}

// MARK: TokenAuthenticatable Conformance
//extension User: TokenAuthenticatable {
//    /// Required typealias, using `Token` class for HTTP Bearer Authorization.
//    typealias TokenType = Token
//}

// representation models can be passed as HTTP body data
extension User.Admin: Content {}
extension User.Header: Content {}
extension User.Public: Content {}

