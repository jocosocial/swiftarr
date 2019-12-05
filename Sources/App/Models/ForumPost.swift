import Vapor
import FluentPostgreSQL

/// An individual post within a `Forum`. A ForumPost must contain either text
/// content or image content, or both.

final class ForumPost: Codable {
    // MARK: Properties
    
    /// The post's ID.
    var id: Int?
    
    /// The ID of the forum to which the post belongs.
    var forumID: UUID
    
    /// The ID of the post's author.
    var authorID: UUID
    
    /// The text content of the post.
    var text: String
    
    /// The filename of any image content of the post.
    var image: String
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?
    
    // MARK: Initialization
    
    /// Initializes a new ForumPost.
    ///
    /// - Parameters:
    ///   - forumID: The ID of the post's forum.
    ///   - authorID: The ID of the author of the post.
    ///   - text: The text content of the post.
    ///   - image: The filename of any image content of the post.
    init(
        forumID: UUID,
        authorID: UUID,
        text: String,
        image: String = ""
    ) {
        self.forumID = forumID
        self.authorID = authorID
        self.text = text
        self.image = image
    }
}
