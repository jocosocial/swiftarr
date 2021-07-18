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

final class User: Model {
	static let schema = "users"
	
    /// The user's ID, provisioned automatically.
 	@ID(key: .id) var id: UUID?
    
// MARK: Who This User Is
    /// The user's publicly viewable username.
    @Field(key: "username") var username: String
    
    /// An optional name for display alongside the username. "Display Name (@username)"
    @OptionalField(key: "displayName") var displayName: String?
    
    /// An optional real world name for the user.
    @OptionalField(key: "realName") var realName: String?
    
    /// Concatenation of displayName + (@username) + realName, to speed search by name.
    @Field(key: "userSearch") var userSearch: String
    
// MARK: Access
    /// The user's password, encrypted to BCrypt hash value.
    @Field(key: "password") var password: String
    
    /// The user's recovery key, encrypted to BCrypt hash value.
    @Field(key: "recoveryKey") var recoveryKey: String
    
    /// The registration code (or other identifier) used to activate the user
    /// for full read-write access. Prefixed with "*" after being used for password recovery.
    @OptionalField(key: "verification") var verification: String?
    
    /// The user's `UserAccessLevel`, set to `.unverified` at time of creation,
    /// or to the parent's access level if a sub-account.
    @Field(key: "accessLevel") var accessLevel: UserAccessLevel
    
    /// Only refers to the user's ability to change their profile. Think of the profile fields as content, and mods can quarantine or lock that content,
    /// separate from outright banning a user.
    @Enum(key: "moderationStatus") var moderationStatus: ContentModerationStatus

    /// Number of successive failed attempts at password recovery.
    @Field(key: "recoveryAttempts") var recoveryAttempts: Int
    
    /// Cumulative number of reports submitted on user's posts.
    @Field(key: "reports") var reports: Int
    
    /// If non-nil, the account has been handed a time out by a moderator. The account will have an effective access level of 'Quarantined' until the given time.
    /// Quarantine generally means normal Read access but user canot post or modify any text or image content. The user's `accessLevel` field should not be
    /// changed when applying a temp quarantine. This way if mods later decide to ban the user, the end of the temp quarantine won't reset the user's access level
	/// (most likely to `.verified`).
    @Field(key: "tempQuarantineUntil") var tempQuarantineUntil: Date?
    
// MARK: About This User

    /// The filename of the image for the user's profile picture.
    @Field(key: "userImage") var userImage: String?
    
    /// An optional bio or blurb or whatever.
    @OptionalField(key: "about") var about: String?
    
    /// An optional email address. Social media addresses, URLs, etc. should probably be
    /// in `.about` or maybe `.message`.
    @OptionalField(key: "email") var email: String?
    
    /// An optional home city, country, planet...
    @OptionalField(key: "homeLocation") var homeLocation: String?
    
    /// An optional message to anybody viewing the profile. "I like turtles."
    @OptionalField(key: "message") var message: String?
    
    /// An optional preferred pronoun or form of address.
    @OptionalField(key: "preferredPronoun") var preferredPronoun: String?
    
    /// An optional cabin number.
    @OptionalField(key: "roomNumber") var roomNumber: String?
    
    /// Limits viewing this profile's info (except `.username` and `.displayName`, which are
    /// always viewable) to logged-in users. Default is `false` (don't limit).
    @Field(key: "limitAccess") var limitAccess: Bool
    
// MARK: Moderator Only

	/// If the user is a Moderator and is handling user reports, this will be set to the actionGroup of the reports. In this case, all the reports in the group
	/// are reporting on the same piece of content, and all have the same actionGroup. Any moderator actions the mod takes while handling reports 
	/// get set tot his UUID. When the reports are closed, this gets set to nil.
    @Field(key: "action_group") var actionGroup: UUID?

// Timestamps
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    
    /// Timestamp of the UserProfile's last update.
    @Field(key: "profileUpdatedAt") var profileUpdatedAt: Date
    
	// MARK: Relations

    /// If a sub-account, the ID of the User to which this user is associated,
    /// provisioned by `UsersController` handlers during creation.
    @OptionalParent(key: "parent") var parent: User?
    
    /// The child `Barrels`s owned by the user.
// FIXME: how to handle this
//	@Children(for: \$.) var barrels: [Barrel]

    /// The child `Twarrt`s created by the user.
	@Children(for: \.$author) var twarrts: [Twarrt]

    /// The sibling `Twarrt`s "liked" by the user.
    @Siblings(through: TwarrtLikes.self, from: \.$user, to: \.$twarrt) var twarrtLikes: [Twarrt]

	/// The child `Forum`s created by the user.
	@Children(for: \.$creator) var forums: [Forum]
    
    /// The child `ForumPost`s created by the user.
	@Children(for: \.$author) var posts: [ForumPost]
	
    /// The sibling `ForumPost`s "liked" by the user.
    @Siblings(through: PostLikes.self, from: \.$user, to: \.$post) var postLikes: [ForumPost]

    /// The `ForumReaders` pivots contain read counts for each forum thread this user had viewed.. 
    @Siblings(through: ForumReaders.self, from: \.$user, to: \.$forum) var readForums: [Forum]

	/// The child `FriendlyFez` objects created by this user.
	@Children(for: \.$owner) var owned_fezzes: [FriendlyFez]
	
	/// The sibling `FriendlyFez` objects this user has joined.
	@Siblings(through: FezParticipant.self, from: \.$user, to: \.$fez) var joined_fezzes: [FriendlyFez]

    /// The child `ProfileEdit` accountability records of this user.
    @Children(for: \.$user) var edits: [ProfileEdit]
        
    /// The child `UserNote`s owned by the user.
	@Children(for: \.$author) var notes: [UserNote]
	
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
        self.limitAccess = false
        self.moderationStatus = .normal
        
        buildUserSearchString()
    }
}
