import Vapor
import Fluent


/// Categories are used to organize Twit-arr `Forum`s into a managable structure. All `Forum`s
/// belong to a single `Category`. A category is classified as one of two types: "admin"
/// (an administratively controlled set of forums) or "user" (users can create forums).

final class Category: Model {
	static let schema = "categories"
	
    // MARK: Properties
    
    /// The category's ID.
    @ID(key: .id) var id: UUID?
    
    /// The title of the category.
    @Field(key: "title") var title: String
    
    /// Whether the category requires `.moderator` for additions.
    @Field(key: "isRestricted") var isRestricted: Bool
    
    /// The number of forums containted in this Category. Should always be equal to forums.count.
    @Field(key: "forumCount") var forumCount: Int32
    
    /// Timestamp of the model's creation, set automatically.
    @Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?

	// MARK: Relations
	
    /// The `Forum`s belonging to the category.
    @Children(for: \.$category) var forums: [Forum]

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new Category.
    ///
    /// - Parameters:
    ///   - title: The title for the the category.
    ///   - isRestricted: Whether users can create forums in the category.
    init(
        title: String,
        isRestricted: Bool = false
    ) {
        self.title = title
        self.isRestricted = isRestricted
        self.forumCount = 0
    }
}
