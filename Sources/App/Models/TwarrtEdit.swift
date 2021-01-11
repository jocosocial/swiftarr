import Vapor
import FluentPostgreSQL

/// When a `Twarrt` is edited, a `TwarrtEdit` is created and associated with the
/// twarrt.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

struct TwarrtEdit: Codable {
     typealias Database = PostgreSQLDatabase
    // MARK: Properties
    
    /// The edit's ID.
    var id: UUID?
    
    /// The ID of the twarrt that was edited.
    let twarrtID: Int
    
    /// The previous contents of the post.
    var twarrtContent: PostContentData
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    // MARK: Initialization
    
    /// Initializes a new TwarrtEdit.
    ///
    /// - Parameters:
    ///   - twarrtID: The ID of the Twarrt that was edited.
    ///   - twarrtContent: The previous contents of the Twarrt.
    init(
        twarrtID: Int,
        twarrtContent: PostContentData
    ) {
        self.twarrtID = twarrtID
        self.twarrtContent = twarrtContent
    }
}
