import Vapor
import Fluent

/**
	Each time a moderator performs a moderation action--editing, locking, or deleting a post, forum, or fez, changing a user's access level, issuing a temp quarantine,
	or other moderation-only activities, we log the action by creating one of these records in the database..
	
	The data collected may only be viewed by moderators. The intent is to make it easier for mods to coordinate.

	- See Also: [ModeratorActionLogData](ModeratorActionLogData) the DTO for returning data about moderator actions.
	- See Also: [CreateModeratorActionSchema](CreateModeratorActionSchema) the Migration for creating the ModeratorAction table in the database.
*/
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
     
	/// If the mod is in the process of handling reports when taking this action, this gets set to the reports' actionGroup, making it easier to correllate user reports amd mod actions.
    @Field(key: "action_group") var actionGroup: UUID?

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
    	actionGroup = moderator.actionGroup
    }
}

/// Describes the type of action a moderator took. This enum is used both in the ModeratorAction Model, and in several Moderation DTOs.
/// Be careful when modifying this. Not all ModeratorActionTypes are applicable to all ReportTypes.
enum ModeratorActionType: String, Codable {
	/// The moderator edited a piece of content owned by somebody else.
	case edit
	/// The moderator deleted somebody else's content. For `user` content, this means the user photo (users and profile fields can't be deleted).
	case delete
	
	/// The moderator has quarantined a user or a piece of content. Quarantined content still exists, but the server replaces the contents with a quarantine message.
	/// A quarantined user can still read content, but cannot post or edit. 
	case quarantine
	/// If enough users report on some content (e.g. a twarrt or forum post), that content will get auto-quarantined. A mod can review the content and if it's not in violation
	/// they can set it's modStatus to `markReviewed` to indicate the content is OK. This protects the content from auto-quarantining.
	case markReviewed
	/// The moderator has locked a piece of content. Locking prevents the owner from modifying the content; locking a forum or fez prevents new messages
	/// from being posted.
	case lock
	/// The moderator has unlocked a piece of content. Unlocking lets others  
	case unlock
	
	case editProfile
	case changeAccessLevel	// really, change access level

	static func setFromModerationStatus(_ status: ContentModerationStatus) -> Self {
		switch status {
			case .normal: return .unlock
			case .autoQuarantined: return .quarantine
			case .quarantined: return .quarantine
			case .locked: return .lock
			case .modReviewed: return .markReviewed
		}
	}
}
