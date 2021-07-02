import Vapor
import Fluent


/// A collection of `ForumPost`s on a single topic. Only the `.creatorID` user
/// or one with .accessLevel of `.moderator` or above can edit a forum's title
/// or place it into a locked state.
///
/// - Note: A locked state (`.isLocked` == true) means that the forum is currently
///   read-only and is distinct from a forum's removal by soft-deletion.

final class Forum: Model {
	static let schema = "forums"

    // MARK: Properties
    
    /// The forum's ID.
    @ID(key: .id) var id: UUID?
    
    /// The title of the forum.
    @Field(key: "title") var title: String
        
    /// Moderators can set several statuses on forums that modify editability and visibility.
    @Enum(key: "mod_status") var moderationStatus: ContentModerationStatus
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    
	// MARK: Relations
    
    /// The parent `Category` of the forum.
	@Parent(key: "category_id") var category: Category
    
    /// The parent `User` who created the forum.
	@Parent(key: "creator_id") var creator: User
    
    /// The child `ForumPost`s within the forum.
    @Children(for: \.$forum) var posts: [ForumPost]
    
    /// The `ForumReaders` pivots contain read counts for each user who has read this forum thread. 
    @Siblings(through: ForumReaders.self, from: \.$forum, to: \.$user) var readers: [User]

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new Forum.
    ///
    /// - Parameters:
    ///   - title: The title for the forum.
    ///   - categoryID: The category to which the forum belongs.
    ///   - creatorID: The ID of the creator of the forum.
    ///   - isLocked: Whether the forum is administratively locked.
    init(
        title: String,
        category: Category,
        creator: User,
        isLocked: Bool = false
    ) throws {
        self.title = title
        self.$category.id = try category.requireID()
        self.$category.value = category
        self.$creator.id = try creator.requireID()
        self.$creator.value = creator
        self.moderationStatus = .normal
    }
}
