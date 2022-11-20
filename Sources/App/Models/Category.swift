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
	static let schema = "category"
	
	// MARK: Properties
	
	/// The category's ID.
	@ID(key: .id) var id: UUID?
	
	/// The title of the category.
	@Field(key: "title") var title: String
	
	/// A short string describing what the Category is for. Color commentary for the category.
	@Field(key: "purpose") var purpose: String
	
	/// TRUE if this category holds forums for Events. 
	@Field(key: "is_event_category") var isEventCategory: Bool
	
	/// Minimum access level to view posts in this category. Usually set to `.quarantined`. But, a category reserved for moderators only
	/// could have this set to `.moderator`.
	@Enum(key: "view_access_level") var accessLevelToView: UserAccessLevel
	
	/// Minimum access level to create threads in this category. Usually set to `.verified`.  Setting this to a value less than verified won't work as
	/// those users cannot create any content. This setting does not govern posting in existing threads. An admin could create a thread in an admin-only
	/// forum and leave it unlocked so that anyone that can see the thread can post in it. Or, they could lock the thread, preventing posting.
	@Enum(key: "create_access_level") var accessLevelToCreate: UserAccessLevel
	
	/// If non-nil, the UserRoleType that a User is required to posess in order to view items in this category. This test is bypassed for Moderator users.
	/// For everyone else, both the Role test and the accessLevel test must pass in order to view.
	@OptionalEnum(key: "required_role") var requiredRole: UserRoleType?
	
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
	init(title: String,  purpose: String, viewAccess: UserAccessLevel = .quarantined, createForumAccess: UserAccessLevel = .verified,
			isEventCategory: Bool = false, requiredRole: UserRoleType? = nil) {
		self.title = title
		self.purpose = purpose
		self.accessLevelToView = viewAccess
		self.accessLevelToCreate = createForumAccess
		self.forumCount = 0
		self.isEventCategory = isEventCategory
		self.requiredRole = requiredRole
	}
}

struct CreateCategorySchema: AsyncMigration {
	func prepare(on database: Database) async throws {
		let userAccessLevel = try await database.enum("user_access_level").read()
		try await database.schema("category")
				.id()
				.field("title", .string, .required)
				.unique(on: "title")
				.field("purpose", .string, .required)
				.field("is_event_category", .bool, .required)
				.field("view_access_level", userAccessLevel, .required)
				.field("create_access_level", userAccessLevel, .required)
				.field("required_role", .string)
				.field("forumCount", .int32, .required)
				.field("created_at", .datetime)
				.field("updated_at", .datetime)
				.field("deleted_at", .datetime)
				.create()
	}
	
	func revert(on database: Database) async throws {
		try await database.schema("category").delete()
	}
}

