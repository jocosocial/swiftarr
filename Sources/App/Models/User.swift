import Foundation
import Vapor
import FluentPostgreSQL
import Authentication

/// All accounts are of class `User`.
///
/// The terms "account" and "sub-account" used throughout this documentatiion are all
/// instances of User. The terms "primary account", "parent account" and "master account"
/// are used interchangeably to refer to any account that is not a sub-account.
///
/// A primary account holds the access level, verification token and recovery key, and all
/// sub-accounts (if any) inherit these three credentials.
///
/// `.id` and `.parentID` are provisioned automatically, by the model protocols and
/// `UsersController` account creation handlers respectively. `.createdAt`, .updatedAt` and
/// `.deletedAt` are all maintained automatically by the model protocols and should never be
///  otherwise modified.

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
    /// or to the parent's access level if a sub-account.
    var accessLevel: UserAccessLevel
    
    /// An array of keywords on which the user can mute a post.
    var keywordMutes: [String]
    
    /// Number of successive failed attempts at password recovery.
    var recoveryAttempts: Int
    
    /// Cumulative number of reports submitted on user's posts.
    var reports: Int
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?
    
    /// Timestamp of the child UserProfile's last update.
    var profileUpdatedAt: Date
    
    // MARK: Initialization
    
    /// Initializes a new User.
    ///
    /// - Parameters:
    ///   - username: The user's username, unadorned (e.g. "grundoon", not "@grundoon").
    ///   - password: A `BCrypt` hash of the user's password. Please **never** store actual
    ///     passwords.
    ///   - recoveryKey: A `BCrypt` hash of the user's recovery key. Please **never** store
    ///     the actual key.
    ///   - verification: A token of known identity, such as a provided code or a verified email
    ///     address. `nil` if not yet verified.
    ///   - parentID: If a sub-account, the `id` of the master acount, otherwise `nil`.
    ///   - accessLevel: The user's access level (see `UserAccessLevel`).
    ///   - keywordMutes: The user's list of keywords that mute posts, initially empty.
    ///   - recoveryAttempts: The number of successive failed attempts at password recovery,
    ///     initially 0.
    ///   - reports: The total number of reports made on the user's posts, initially 0.
    ///   - profileUpdatedAt: The timestamp of the associated profile's last update, initially
    ///     epoch.
    
    init(
        username: String,
        password: String,
        recoveryKey: String,
        verification: String? = nil,
        parentID: UUID? = nil,
        accessLevel: UserAccessLevel,
        keywordMutes: [String] = [],
        recoveryAttempts: Int = 0,
        reports: Int = 0,
        profileUpdatedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.username = username
        self.password = password
        self.recoveryKey = recoveryKey
        self.verification = verification
        self.parentID = parentID
        self.accessLevel = accessLevel
        self.keywordMutes = keywordMutes
        self.recoveryAttempts = recoveryAttempts
        self.reports = reports
        self.profileUpdatedAt = profileUpdatedAt
    }
    
    // MARK: - Codable Representations
    
    /// Used for administrative functions.
    final class Admin: Codable {
        // MARK: Properties
        /// The user's ID.
        var id: UUID
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
        /// Number of successive failed attempts at password recovery.
        var recoveryAttempts: Int
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
        ///   - recoveryAttempts: Number of successive failed password recovery attempts.
        ///   - reports: Cumulative number of reports on the user's posts.
        ///   - createdAt: Timestamp of user creation.
        ///   - updatedAt: Timestamp of last update to the user's model.
        ///   - deletedAt: Timestamp of the model's soft-deletion.
        init(
            id: UUID,
            username: String,
            verification: String?,
            parentID: UUID?,
            accessLevel: UserAccessLevel,
            keywordMutes: [String],
            recoveryAttempts: Int,
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
            self.recoveryAttempts = recoveryAttempts
            self.reports = reports
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.deletedAt = deletedAt
        }
    }
    
    /// Used for general identification and reference.
    final class Public: Codable {
        // MARK: Properties
        /// The user's ID.
        var id: UUID
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
        init(id: UUID, username: String, updatedAt: Date) {
            self.id = id
            self.username = username
            self.updatedAt = updatedAt
        }
    }
}
