import Foundation
import Vapor
import Fluent


/// The optional information provided by a user for their profile page. The associated
/// `UserProfile` is automatically created wnen a `User` is created via the endpoint. Only
/// the `.userID`, `.username` and `.userSearch` fields are populated upon initialization.

final class UserProfile: Model, Content {
	static let schema = "userprofiles"

    // MARK: Properties
    
    /// The profile's ID, provisioned automatically.
    @ID(key: .id) var id: UUID?
    
    /// The user's username. Uniqued.
    @Field(key: "username") var username: String
    
    /// Concatenation of displayName + (@username) + realName, to speed search by name.
    @Field(key: "userSearch") var userSearch: String
    
    /// The filename of the image for the user's profile picture.
    @Field(key: "userImage") var userImage: String
    
    /// An optional bio or blurb or whatever.
    @OptionalField(key: "about") var about: String?
    
    /// An optional name for display alongside the username. "Display Name (@username)"
    @OptionalField(key: "displayName") var displayName: String?
    
    /// An optional email address. Social media addresses, URLs, etc. should probably be
    /// in `.about` or maybe `.message`.
    @OptionalField(key: "email") var email: String?
    
    /// An optional home city, country, planet...
    @OptionalField(key: "homeLocation") var homeLocation: String?
    
    /// An optional message to anybody viewing the profile. "I like turtles."
    @OptionalField(key: "message") var message: String?
    
    /// An optional preferred pronoun or form of address.
    @OptionalField(key: "preferredPronoun") var preferredPronoun: String?
    
    /// An optional real world name for the user.
    @OptionalField(key: "realName") var realName: String?
    
    /// An optional cabin number.
    @OptionalField(key: "roomNumber") var roomNumber: String?
    
    /// Limits viewing this profile's info (except `.username` and `.displayName`, which are
    /// always viewable) to logged-in users. Default is `false` (don't limit).
    @Field(key: "limitAccess") var limitAccess: Bool

    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    
	// MARK: Relations

    /// The parent `User`, provisioned by the creation handler.
    @Parent(key: "user") var user: User
    
    /// The child `ProfileEdit` accountability records of the profile.
    @Children(for: \.$profile) var edits: [ProfileEdit]
    
	// MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    ///  Initializes a new UserProfile associated with a `User` account.
    ///
    /// - Parameters:
    ///   - user: The parent `User`.
    ///   - username: The .username of the parent `User`.
    ///   - about: An optional nutshell to share publicly.
    ///   - displayName: An optional name for display alongside the username.
    ///   - email: An optional email address to share publicly.
    ///   - homeLocation: An optional home location to share publicly.
    ///   - message: An optional greeting/message to share publicly.
    ///   - preferredPronoun: An optional preferred form of address/reference to share publicly.
    ///   - realName: An optional real name to share publicly.
    ///   - roomNumber: An option cabin number to share publicly.
    ///   - limitAccess: Whether the full version of this profile is only viewable by logged-in users.
    init(
        user: User,
        username: String,
        userImage: String = "",
        about: String? = nil,
        displayName: String? = nil,
        email: String? = nil,
        homeLocation: String? = nil,
        message: String? = nil,
        preferredPronoun: String? = nil,
        realName: String? = nil,
        roomNumber: String? = nil,
        limitAccess: Bool = false
    ) throws {
        self.$user.id = try user.requireID()
        self.$user.value = user
        // .userSearch is initially just @username
        self.userSearch = "@\(username)"
        self.userImage = userImage
        self.username = username
        self.about = about
        self.displayName = displayName
        self.email = email
        self.homeLocation = homeLocation
        self.message = message
        self.preferredPronoun = preferredPronoun
        self.realName = realName
        self.roomNumber = roomNumber
        self.limitAccess = limitAccess
    }
}
