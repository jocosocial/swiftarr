import Vapor
import Fluent


/**
	Admins can create Announcements, which are text strings intended to be shown to all users. All announcements have a 'display until' time,
	and are considered 'active' until their display until time expires. 

	Announcement IDs are ints, and increase with each announcement created. The `User` model stores the highest Announcement ID the user
	has seen.

	Announcements are global, and are retrieveable while logged out. However, endpoints returning announcement data will only return all active
	announcements for logged-out users. Logged-in users will additionally get data indicating which announcements are unread. Clients may implement
	local solutions for determining which announcements are unread for logged-out users.

	- See Also: [AnnouncementData](AnnouncementData) the DTO for returning info on Announcements.
	- See Also: [AnnouncementCreateData](AnnouncementCreateData) the DTO for creating and editing Announcements.
	- See Also: [CreateAnnouncementSchema](CreateAnnouncementSchema) the Migration that creates the Announcement table in the database.
*/
final class Announcement: Model {
	static let schema = "announcements"
	
    // MARK: Properties
    
    /// The announcement's ID.
    @ID(custom: "id") var id: Int?
    
    /// The text content of the announcement.
    @Field(key: "text") var text: String
    
    /// The announcement is considered 'active' until this time. Most API endpoints only return info on active announcements. 
    @Field(key: "display_until") var displayUntil: Date
                
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
 
	// MARK: Relations
    
    /// The parent `User`  who authored the announcement.
    @Parent(key: "author") var author: User
        
    // MARK: Initialization
    
    /// Used by Fluent
 	init() { }
 	
    /// Initializes a new Announcement.
    ///
    /// - Parameters:
    ///   - author: The author of the Announcement.
    ///   - text: The text content of the Announcement.
    init(author: User, text: String, displayUntil: Date) throws {
        self.$author.id = try author.requireID()
        self.$author.value = author
        // We don't do much text manipulation on input, but let's normalize line endings.
        self.text = text.replacingOccurrences(of: "\r\n", with: "\r")
        self.displayUntil = displayUntil
    }
}
