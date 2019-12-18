import Vapor
import FluentPostgreSQL

/// An individual post within the Twit-arr stream. A Twarrt must contain either text
/// content or image content, or both.

final class Twarrt: Codable {
    // MARK: Properties
    
    /// The twarrt's ID.
    var id: Int?
    
    /// The ID of the twarrt's author.
    var authorID: UUID
    
    /// The text content of the twarrt.
    var text: String
    
    /// The filename of any image content of the twarrt.
    var image: String
    
    /// The ID of the twarrt being replied to.
    var replyToID: Int?
    
    /// Whether the twarrt is in quarantine, unable to be replied to directly.
    var isQuarantined: Bool
    
    /// Whether the twarrt has been reviewed as non-violating content by the Moderator team.
    var isReviewed: Bool
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?
    
    // MARK: Initialization
    
    /// Initialized a new Twarrt.
    ///
    /// - Parameters:
    ///   - authorID: The ID of the author of the twarrt.
    ///   - text: The text content of the twarrt.
    ///   - image: The filename of any image content of the twarrt.
    init(
        authorID: UUID,
        text: String,
        image: String = "",
        replyToID: Int? = nil,
        isQuarantined: Bool = false,
        isReviewed: Bool = false
    ) {
        self.authorID = authorID
        self.text = text
        self.image = image
        self.replyToID = replyToID
        self.isQuarantined = isQuarantined
        self.isReviewed = isReviewed
    }
}
