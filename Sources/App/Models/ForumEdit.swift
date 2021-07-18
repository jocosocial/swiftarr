import Vapor
import Fluent


/// When a `Forum` is edited, a `ForumEdit` is created to save the previous title text.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

final class ForumEdit: Model {
	static let schema = "forum_edits"

	// MARK: Properties
    
    /// The edit's ID.
    @ID(key: .id) var id: UUID?
        
    /// The previous title of the forum.
    @Field(key: "title") var title: String
        
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
	// MARK: Relations
    
    /// The parent `Forum` of the edit.
    @Parent(key: "forum") var forum: Forum

    /// The `User` that performed the edit.
    @Parent(key: "editor") var editor: User
        
    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	        
	/// Initializes a new ForumEdit with the current title of a `Forum`. Call on the post BEFORE editing it
	/// to save previous contents.
    ///
    /// - Parameters:
    ///   - forum: The Forum that will be edited.
    ///   - editor: The User making the change.
    init(forum: Forum, editor: User) throws
    {
        self.$forum.id = try forum.requireID()
        self.$forum.value = forum
        self.title = forum.title
        self.$editor.id = try editor.requireID()
        self.$editor.value = editor
    }
}
