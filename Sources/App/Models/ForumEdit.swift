import Vapor
import Fluent


/// When a `ForumPost` is edited, a `ForumEdit` is created and associated with the profile.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

final class ForumEdit: Model {
	static let schema = "forumedits"

	// MARK: Properties
    
    /// The edit's ID.
    @ID(key: .id) var id: UUID?
        
    /// The previous text of the post.
    @Field(key: "post_text") var postText: String
    
    /// The previous images, if any.
    @Field(key: "images") var images: [String]?
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
	// MARK: Relations
    
    /// The parent `ForumPost` of the edit.
    @Parent(key: "post_id") var post: ForumPost

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	        
	/// Initializes a new ForumEdit with the current contents of a post.. Call on the post BEFORE editing it
	/// to save previous contents.
    ///
    /// - Parameters:
    ///   - post: The Twarrt that will be edited.
    init(post: ForumPost) throws
    {
        self.$post.id = try post.requireID()
        self.$post.value = post
        self.postText = post.text
        self.images = post.images
    }
}
