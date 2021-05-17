import Vapor
import Fluent


/// An individual post within a `FriendlyFez` discussion. A FezPost must contain
/// either text content or image content, or both.

final class FezPost: Model {
	static let schema = "fezposts"
	
	// MARK: Properties
    
    /// The post's ID.
    @ID(custom: "id") var id: Int?
    
    /// The text content of the post.
    @Field(key: "text") var text: String
    
    /// The filename of any image content of the post.
    @Field(key: "image") var image: String?
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    @Timestamp(key: "deleted_at", on: .delete) var deletedAt: Date?
    
	// MARK: Relations
    
    /// The `FriendlyFez` type `Barrel` to which the post belongs.
    @Parent(key: "friendly_fez") var fez: FriendlyFez
    
    /// The post's author.
    @Parent(key: "author") var author: User

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new FezPost.
    ///
    /// - Parameters:
    ///   - fezID: The ID of the post's FriendlyFez.
    ///   - authorID: The ID of the author of the post.
    ///   - text: The text content of the post.
    ///   - image: The filename of any image content of the post.
    init(
        fez: FriendlyFez,
        author: User,
        text: String,
        image: String?
    ) throws {
        self.$fez.id = try fez.requireID()
        self.$fez.value = fez
        self.$author.id = try author.requireID()
        self.$author.value = author
        
        // Generally I'm in favor of "validate input, sanitize output" but I hate "\r\n" with the fury of a thousand suns.
        self.text = text.replacingOccurrences(of: "\r\n", with: "\r")
        self.image = image
    }
}
