import Foundation
import Vapor
import FluentPostgreSQL

struct ProfileEdit: Codable {
    // MARK: Properties
    
    /// The edit's ID.
    var id: UUID?
    
    /// The ID of the profile that was edited.
    let profileID: UUID
    
    /// If this is a profile data update, the submitted `UserProfileData`.
    var profileData: UserProfileData?

    /// If this is a profile image update, the image filename.
    var profileImage: String?
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    // MARK: Initialization
    
    /// Initializes a new ProfileEdit.
    ///
    /// - Parameters:
    ///   - profileData: The submitted `UserProfileData`, else `nil`.
    ///   - profileImage: The name of the submitted image, els `nil`.
    init(
        profileID: UUID,
        profileData: UserProfileData? = nil,
        profileImage: String? = nil
    ) {
        self.profileID = profileID
        self.profileData = profileData
        self.profileImage = profileImage
    }
}
