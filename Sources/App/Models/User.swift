import Foundation
import Vapor
import Fluent


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
/// `UsersController` account creation handlers respectively. `.createdAt`, `.updatedAt` and
/// `.deletedAt` are all maintained automatically by the model protocols and should never be
///  otherwise modified.

final class User: Model, Content {
	static let schema = "users"
	
   // MARK: Properties
    
    /// The user's ID, provisioned automatically.
 	@ID(key: .id) var id: UUID?
    
    /// The user's publicly viewable username.
    @Field(key: "username") var username: String
    
    /// The user's password, encrypted to BCrypt hash value.
    @Field(key: "password") var password: String
    
    /// The user's recovery key, encrypted to BCrypt hash value.
    @Field(key: "recoveryKey") var recoveryKey: String
    
    /// The registration code (or other identifier) used to activate the user
    /// for full read-write access.
    @OptionalField(key: "verification") var verification: String?
    
    /// The user's `UserAccessLevel`, set to `.unverified` at time of creation,
    /// or to the parent's access level if a sub-account.
    @Field(key: "accessLevel") var accessLevel: UserAccessLevel
    
    /// Number of successive failed attempts at password recovery.
    @Field(key: "recoveryAttempts") var recoveryAttempts: Int
    
    /// Cumulative number of reports submitted on user's posts.
    @Field(key: "reports") var reports: Int
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    
    /// Timestamp of the child UserProfile's last update.
    @Field(key: "profileUpdatedAt") var profileUpdatedAt: Date
    
	// MARK: Relations

    /// If a sub-account, the ID of the User to which this user is associated,
    /// provisioned by `UsersController` handlers during creation.
    @OptionalParent(key: "parent") var parent: User?
    
    /// The child `Barrels`s owned by the user.
// FIXME: how to handle this
//	@Children(for: \$.) var barrels: [Barrel]

	/// The child `Forum`s created by the user.
	@Children(for: \.$creator) var forums: [Forum]
    
    /// The child `UserNote`s owned by the user.
	@Children(for: \.$author) var notes: [UserNote]
	
    /// The sibling `ForumPost`s "liked" by the user.
    @Siblings(through: PostLikes.self, from: \.$user, to: \.$post) var postLikes: [ForumPost]

    /// The child `ForumPost`s created by the user.
	@Children(for: \.$author) var posts: [ForumPost]
	
    /// The child `UserProfile` of the user.
	@Children(for: \.$user) var profile: [UserProfile]		// Actually 1:1
//	@Parent(key: "user_profile") var profile: UserProfile
    
    /// The sibling `Twarrt`s "liked" by the user.
    @Siblings(through: TwarrtLikes.self, from: \.$user, to: \.$twarrt) var twarrtLikes: [Twarrt]

    /// The child `Twarrt`s created by the user.
	@Children(for: \.$author) var twarrts: [Twarrt]

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
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
    ///   - parent: If a sub-account, the `id` of the master acount, otherwise `nil`.
    ///   - accessLevel: The user's access level (see `UserAccessLevel`).
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
        parent: User? = nil,
        accessLevel: UserAccessLevel,
        recoveryAttempts: Int = 0,
        reports: Int = 0,
        profileUpdatedAt: Date = Date(timeIntervalSince1970: 0)
    ) {
        self.username = username
        self.password = password
        self.recoveryKey = recoveryKey
        self.verification = verification
        self.$parent.id = parent?.id
        self.$parent.value = parent
        self.accessLevel = accessLevel
        self.recoveryAttempts = recoveryAttempts
        self.reports = reports
        self.profileUpdatedAt = profileUpdatedAt
    }
}
