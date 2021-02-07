import Vapor
import Fluent


/// An individual post within a `Forum`. A ForumPost must contain either text
/// content or image content, or both.

final class ForumPost: Model {
	static let schema = "forumposts"
	
    // MARK: Properties
    
    /// The post's ID. Sorting posts in a thread by ID should produce the correct ordering, but
    /// post IDs are unique through all forums, and won't be sequential in any forum.
	@ID(custom: "id") var id: Int?
    
    /// The text content of the post.
    @Field(key: "text") var text: String
    
    /// The filename of any image content of the post.
    @Field(key: "image") var image: String
    
    /// Whether the post is in quarantine.
    @Field(key: "isQuarantined") var isQuarantined: Bool
    
    /// Whether the post has been reviewed as non-violating content by the Moderator team.
    @Field(key: "isReviewed") var isReviewed: Bool

    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
 
	// MARK: Relations

    /// The parent `Forum` of the post.
    @Parent(key: "forum") var forum: Forum
    
    /// The parent `User`  who authored the post.
    @Parent(key: "author") var author: User
    
    /// The child `ForumEdit` accountability records of the post.
    @Children(for: \.$post) var edits: [ForumEdit]
    
    /// The sibling `User`s who have "liked" the post.
    @Siblings(through: PostLikes.self, from: \.$post, to: \.$user) var likes
    
    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new ForumPost.
    ///
    /// - Parameters:
    ///   - forum: The post's forum.
    ///   - author: The author of the post.
    ///   - text: The text content of the post.
    ///   - image: The filename of any image content of the post.
    init(
        forum: Forum,
        author: User,
        text: String,
        image: String = ""
    ) throws {
        self.$forum.id = try forum.requireID()
        self.$forum.value = forum
        self.$author.id = try author.requireID()
        self.$author.value = author
        self.text = text
        self.image = image
        self.isQuarantined = false
        self.isReviewed = false
    }
}
