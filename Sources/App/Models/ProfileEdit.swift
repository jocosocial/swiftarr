import Vapor
import Fluent

/**
	When a `UserProfile` is edited, a `ProfileEdit` is created and associated with the
	profile. The `ProfileEdit` records the state of the profile just before the edit occurred.
	
	This is done for accountability purposes and the data collected is intended to be viewable
	only by users with an access level of `.moderator` or above.

	- See Also: [CreateProfileEditSchema](CreateProfileEditSchema) the Migration for creating the ProfileEdit table in the database.
*/
final class ProfileEdit: Model {
	static let schema = "profileedits"
	
    // MARK: Properties
    
    /// The edit's ID.
    @ID(key: .id) var id: UUID?
        
    /// The `UserProfileData` contents of the user's profile, just before the edit.
    @OptionalField(key: "profileData") var profileData: UserProfileUploadData?

    /// The user's userImage filename, just before the edit.
    @OptionalField(key: "profileImage") var profileImage: String?
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
	// MARK: Relations

    /// The `User` whose profile got edited.
    @Parent(key: "user") var user: User

    /// The `User` that performed the edit. Equal to `user` if someone's editing their own profile.
    @Parent(key: "editor") var editor: User
        
    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new ProfileEdit.
    ///
    /// - Parameters:
    ///   - target: The `User` whose profile data was changed.
    ///   - editor: The `User` who performed the edit.
    init(target: User, editor: User) throws {
    	self.$user.id = try target.requireID()
    	self.$user.value = target
    	self.$editor.id = try editor.requireID()
    	self.$editor.value = editor
    	self.profileData = try UserProfileUploadData(user: target)
        self.profileImage = target.userImage
    }
}
