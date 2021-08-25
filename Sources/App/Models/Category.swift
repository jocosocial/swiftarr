import Vapor
import Fluent

/**
	Categories are used to organize Twit-arr `Forum`s into a managable structure. All `Forum`s
	belong to a single `Category`.
	
	Each `Category` has a minimum userAccessLevel required to view the Category or view forums in the Category.
	Each `Category` also has a minimum userAccessLevel required to create new forums in the Category. 
	
	- See Also: [CategoryData](CategoryData) the DTO for returning info on Categories.
	- See Also: [CreateCategorySchema](CreateCategorySchema) the Migration for creating the Category table in the database.
*/
final class Category: Model {
	static let schema = "categories"
	
    // MARK: Properties
    
    /// The category's ID.
    @ID(key: .id) var id: UUID?
    
    /// The title of the category.
    @Field(key: "title") var title: String
    
    /// Minimum access level to view posts in this category. Usually set to `.quarantined`. But, a category reserved for moderators only
    /// could have this set to `.moderator`.
    @Field(key: "view_access_level") var accessLevelToView: UserAccessLevel
    
    /// Minimum access level to create threads in this category. Usually set to `.verified`.  Setting this to a value less than verified won't work as
    /// those users cannot create any content. This setting does not govern posting in existing threads. An admin could create a thread in an admin-only
    /// forum and leave it unlocked so that anyone that can see the thread can post in it. Or, they could lock the thread, preventing posting.
    @Field(key: "create_access_level") var accessLevelToCreate: UserAccessLevel
    
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
        viewAccess: UserAccessLevel = .quarantined,
        createForumAccess: UserAccessLevel = .verified
    ) {
        self.title = title
        self.accessLevelToView = viewAccess
        self.accessLevelToCreate = createForumAccess
        self.forumCount = 0
    }
}
