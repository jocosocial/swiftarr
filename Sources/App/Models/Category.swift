import Vapor
import Foundation
import FluentPostgreSQL

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
    
    init(
        title: String,
        isRestricted: Bool = false
    ) {
        self.title = title
        self.isRestricted = isRestricted
    }
}
