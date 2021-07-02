import Vapor
import Fluent


/// Each time a moderator performs a moderation action--editing, locking, or deleting a post, forum, or fez, changing a user's access level, issuing a temp quarantine,
/// or other moderation-only activities, we log the action by creating one of these records in the database..
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

final class ModeratorAction: Model {
	static let schema = "moderator_actions"

	// MARK: Properties
    
    /// The edit's ID.
    @ID(key: .id) var id: UUID?
        
    /// The action taken.
    @Field(key: "action_type") var actionType: ModeratorActionType
    
    /// The type of content that got changed..
    @Field(key: "content_type") var contentType: ReportType

    /// The ID of the content that was affected, converted into a string. The actuial @id could be an Int or a UUID, depending on the value of `contentType`.
    @Field(key: "content_id") var contentID: String
     
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
	// MARK: Relations
    
    /// The moderator that took the action.
    @Parent(key: "actor") var actor: User
    
    /// The user whose content got moderated
    @Parent(key: "target_user") var target: User

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	        
	/// Initializes a new ModeratorAction.
	/// 
    /// - Parameters:
    ///   - post: The Twarrt that will be edited.
    init<T: Reportable>(content: T, action: ModeratorActionType, moderator: User) throws
    {
    	actionType = action
    	contentType = content.reportType
    	contentID = try content.reportableContentID()
    	$actor.id = try moderator.requireID()
    	$actor.value = moderator
    	$target.id = content.authorUUID
    }
}

enum ModeratorActionType: String, Codable {
	case edit
	case delete
	
	case quarantine
	case markReviewed
	case lock
	case unlock
	
	case editProfile
	case changeAccessLevel	// really, change access level

	var label: String {
		return "meh"
	}
}
