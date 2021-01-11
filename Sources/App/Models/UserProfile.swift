import Foundation
import Vapor
import FluentPostgreSQL

/// The optional information provided by a user for their profile page. The associated
/// `UserProfile` is automatically created wnen a `User` is created via the endpoint. Only
/// the `.userID`, `.username` and `.userSearch` fields are populated upon initialization.

final class UserProfile: Codable {
    typealias Database = PostgreSQLDatabase

    // MARK: Properties
    
    /// The profile's ID, provisioned automatically.
    var id: UUID?
    
    /// The `ID` of the parent `User`, provisioned by the creation handler.
    var userID: UUID
    
    /// Concatenation of displayName + (@username) + realName, to speed search by name.
    var userSearch: String
    
    /// The user's username.
    var username: String
    
    /// The filename of the image for the user's profile picture.
    var userImage: String
    
    /// An optional bio or blurb or whatever.
    var about: String?
    
    /// An optional name for display alongside the username. "Display Name (@username)"
    var displayName: String?
    
    /// An optional email address. Social media addresses, URLs, etc. should probably be
    /// in `.about` or maybe `.message`.
    var email: String?
    
    /// An optional home city, country, planet...
    var homeLocation: String?
    
    /// An optional message to anybody viewing the profile. "I like turtles."
    var message: String?
    
    /// An optional preferred pronoun or form of address.
    var preferredPronoun: String?
    
    /// An optional real world name for the user.
    var realName: String?
    
    /// An optional cabin number.
    var roomNumber: String?
    
    /// Limits viewing this profile's info (except `.username` and `.displayName`, which are
    /// always viewable) to logged-in users. Default is `false` (don't limit).
    var limitAccess: Bool

    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?

    // MARK: Initialization
    
    ///  Initializes a new UserProfile associated with a `User` account.
    ///
    /// - Parameters:
    ///   - userID: The ID of the parent `User`.
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
        userID: UUID,
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
    ) {
        self.userID = userID
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
