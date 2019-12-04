import Vapor
import FluentPostgreSQL

/// Categories are used to organize Twit-arr `Forum`s into a managable structure. All `Forum`s
/// belong to a single `Category`.

final class Category: Codable {
    // MARK: Properties
    
    /// The category's ID.
    var id: Int?
    
    /// The title of the category.
    var title: String
    
    /// Whether the category requires `.moderator` for additions.
    var isRestricted: Bool
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    var updatedAt: Date?
    
    /// Timestamp of the model's soft-deletion, set automatically.
    var deletedAt: Date?

    // MARK: Initialization
    
    /// Initializes a new Category.
    ///
    /// - Parameters:
    ///   - title: The title for the the category.
    ///   - isRestricted: Whether users can create forums in the category.
    init(
        title: String,
        isRestricted: Bool = false
    ) {
        self.title = title
        self.isRestricted = isRestricted
    }
}
