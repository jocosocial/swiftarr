import Vapor
import FluentPostgreSQL

/// A collection of `ForumPost`s on a single topic. Only the `.creatorID` user
/// or one with .accessLevel of `.moderator` or above can edit a forum's title
/// or place it into a locked state.
///
/// - Note: A locked state (`.isLocked` == true) means that the forum is currently
///   read-only and is distinct from a forum's removal by soft-deletion.

final class Forum: Codable {
    // MARK: Properties
    
    /// The forum's ID.
    var id: UUID?
    
    /// The title of the forum.
    var title: String
    
    /// The ID of the forum's category.
    var categoryID: UUID
    
    /// The ID of the user who "owns" the forum.
    var creatorID: UUID
    
    /// Whether the forum is in an administratively locked state.
    var isLocked: Bool
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?
    
    // MARK: Initialization
    
    /// Initializes a new Forum.
    ///
    /// - Parameters:
    ///   - title: The title for the forum.
    ///   - categoryID: The category to which the forum belongs.
    ///   - creatorID: The ID of the creator of the forum.
    ///   - isLocked: Whether the forum is administratively locked.
    init(
        title: String,
        categoryID: UUID,
        creatorID: UUID,
        isLocked: Bool = false
    ) {
        self.title = title
        self.categoryID = categoryID
        self.creatorID = creatorID
        self.isLocked = isLocked
    }
}
