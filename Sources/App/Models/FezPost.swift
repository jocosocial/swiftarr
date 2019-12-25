import Vapor
import FluentPostgreSQL

/// An individual post within a `FriendlyFez` discussion. A FezPost must contain
/// either text content or image content, or both.

final class FezPost: Codable {
    // MARK: Properties
    
    /// The post's ID.
    var id: Int?
    
    /// The ID of the `FriendlyFez` to which the post belongs.
    var fezID: UUID
    
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
    
    /// Initializes a new FezPost.
    ///
    /// - Parameters:
    ///   - fezID: The ID of the post's FriendlyFez.
    ///   - authorID: The ID of the author of the post.
    ///   - text: The text content of the post.
    ///   - image: The filename of any image content of the post.
    init(
        fezID: UUID,
        authorID: UUID,
        text: String,
        image: String = ""
    ) {
        self.fezID = fezID
        self.authorID = authorID
        self.text = text
        self.image = image
    }
}
