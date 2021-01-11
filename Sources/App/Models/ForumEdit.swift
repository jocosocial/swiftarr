import Vapor
import FluentPostgreSQL

/// When a `ForumPost` is edited, a `ForumEdit` is created and associated with the profile.
///
/// This is done for accountability purposes and the data collected is intended to be viewable
/// only by users with an access level of `.moderator` or above.

struct ForumEdit: Codable {
	typealias Database = PostgreSQLDatabase
   // MARK: Properties
    
    /// The edit's ID.
    var id: UUID?
    
    /// The ID of the post that was edited.
    var postID: Int
    
    /// The previous contents of the post.
    var postContent: PostContentData
    
     /// Timestamp of the model's creation, set automatically.
     var createdAt: Date?

    // MARK: Initialization
    
    /// Initializes a new ForumEdit.
    ///
    /// - Parameters:
    ///   - postID: The ID of the ForumPost that was edited.
    ///   - postContent: The previous contents of the ForumPost.
    init(
        postID: Int,
        postContent: PostContentData
    ) {
        self.postID = postID
        self.postContent = postContent
    }
}
