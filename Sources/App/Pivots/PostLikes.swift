import FluentPostgreSQL
import Foundation

/// A `Pivot` holding a siblings relation between `User` and `ForumPost`.

final class PostLikes: PostgreSQLUUIDPivot, ModifiablePivot {
    // MARK: Properties
    
    /// The ID of the pivot.
    var id: UUID?
    
    /// The type of like reaction. Needs to be optional to conform to `ModifiablePivot`'s
    /// required `init(_:_:)`.
    var likeType: LikeType?
    
    // MARK: Initialization
    
    /// Initializes a new PostLikesPivot.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - post: The right hand `ForumPost` model.
    init(_ user: User, _ post: ForumPost) throws {
        self.userID = try user.requireID()
        self.postID = try post.requireID()
    }
    
    /// Convenience initializer to provide `.likeType` initializaion.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - post: The right hand `ForumPost` model.
    ///   - likeType: The type of like reaction for this pivot.
    convenience init(_ user: User, _ post: ForumPost, likeType: LikeType) throws {
        try self.init(user, post)
        self.likeType = likeType
    }
    
    // MARK: ModifiablePivot Conformance
    
    /// The associated identifier type for `User`.
    var userID: User.ID
    /// The associated identifier type for `ForumPost`.
    var postID: ForumPost.ID
    
    typealias Left = User
    typealias Right = ForumPost
    
    /// Required key for `Pivot` protocol.
    static let leftIDKey: LeftIDKey = \.userID
    /// Required key for `Pivot` protocol.
    static let rightIDKey: RightIDKey = \.postID
}
