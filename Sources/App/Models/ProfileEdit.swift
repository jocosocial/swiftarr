import Vapor
import Fluent


/// When a `UserProfile` is edited, a `ProfileEdit` is created and associated with the
/// profile.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

final class ProfileEdit: Model {
	static let schema = "profileedits"
	
    // MARK: Properties
    
    /// The edit's ID.
    @ID(key: .id) var id: UUID?
        
    /// If this is a profile data update, the submitted `ProfileEditData`.
    @OptionalField(key: "profileData") var profileData: ProfileEditData?

    /// If this is a profile image update, the image filename.
    @OptionalField(key: "profileImage") var profileImage: String?
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
	// MARK: Relations

    /// The parent `UserProfile` of the edit.
    @Parent(key: "userprofile") var profile: UserProfile

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new ProfileEdit.
    ///
    /// - Parameters:
    ///   - profileID: The ID of the profile that was edited.
    ///   - profileData: The submitted `ProfileEditData`, else nil.
    ///   - profileImage: The name of the submitted image, else nil.
    init(
        profile: UserProfile,
        profileData: ProfileEditData? = nil,
        profileImage: String? = nil
    ) throws {
    	self.$profile.id = try profile.requireID()
    	self.$profile.value = profile
        self.profileData = profileData
        self.profileImage = profileImage
    }
    
    /// Makes a profileEdit from the values in the given profile.
    init(profile: UserProfile) throws {
    	self.$profile.id = try profile.requireID()
    	self.$profile.value = profile
    	self.profileData = ProfileEditData(about: profile.about ?? "", 
    	displayName: profile.displayName ?? "", 
    	email: profile.email ?? "", 
    	homeLocation: profile.homeLocation ?? "", 
    	message: profile.message ?? "", 
    	preferredPronoun: profile.preferredPronoun ?? "", 
    	realName: profile.realName ?? "", 
    	roomNumber: profile.roomNumber ?? "", 
    	limitAccess: profile.limitAccess)
    }
}
