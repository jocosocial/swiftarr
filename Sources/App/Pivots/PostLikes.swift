import Foundation
import Fluent

/// A `Pivot` holding a siblings relation between `User` and `ForumPost`.

final class PostLikes: Model {
    static let schema = "post+likes"

    // MARK: Properties
    
    /// The ID of the pivot.
    @ID(key: .id) var id: UUID?
    
    /// The type of like reaction. Needs to be optional to conform to `ModifiablePivot`'s
    /// required `init(_:_:)`.
    @Field(key: "liketype") var likeType: LikeType?
    
    // MARK: Relationships
    
    /// The associated `User` who likes this.
	@Parent(key: "user") var user: User

    /// The associated `ForumPost` that was liked.
    @Parent(key: "forumPost") var post: ForumPost

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new PostLikes pivot.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - post: The right hand `ForumPost` model.
    init(_ userID: UUID, _ post: ForumPost) throws {
        self.$user.id = userID
        self.$post.id = try post.requireID()
        self.$post.value = post
    }
    
    /// Convenience initializer to provide `.likeType` initializaion.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - post: The right hand `ForumPost` model.
    ///   - likeType: The type of like reaction for this pivot.
    convenience init(_ userID: UUID, _ post: ForumPost, likeType: LikeType) throws {
		try self.init(userID, post)
        self.likeType = likeType
    }
}
