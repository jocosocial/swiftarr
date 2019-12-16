import Foundation
import Vapor
import FluentPostgreSQL

/// When a `UserProfile` is edited, a `ProfileEdit` is created and associated with the
/// profile.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

struct ProfileEdit: Codable {
    // MARK: Properties
    
    /// The edit's ID.
    var id: UUID?
    
    /// The ID of the profile that was edited.
    let profileID: UUID
    
    /// If this is a profile data update, the submitted `ProfileEditData`.
    var profileData: ProfileEditData?

    /// If this is a profile image update, the image filename.
    var profileImage: String?
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    // MARK: Initialization
    
    /// Initializes a new ProfileEdit.
    ///
    /// - Parameters:
    ///   - profileID: The ID of the profile that was edited.
    ///   - profileData: The submitted `ProfileEditData`, else nil.
    ///   - profileImage: The name of the submitted image, else nil.
    init(
        profileID: UUID,
        profileData: ProfileEditData? = nil,
        profileImage: String? = nil
    ) {
        self.profileID = profileID
        self.profileData = profileData
        self.profileImage = profileImage
    }
}
