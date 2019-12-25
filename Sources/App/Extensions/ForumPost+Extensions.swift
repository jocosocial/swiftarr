import Vapor
import FluentPostgreSQL

// model uses Int as primary key
extension ForumPost: PostgreSQLModel {}

// model can be passed as HTTP body data
extension ForumPost: Content {}

// model can be used as endpoint parameter
extension ForumPost: Parameter {}

// MARK: - Custom Migration

extension ForumPost: Migration {
    /// Required by `Migration` protocol. Creates the table, with foreign key  constraint
    /// to `Forum`.
    ///
    /// - Parameter connection: The connection to the database, usually the Request.
    /// - Returns: Void.
    static func prepare(on connection: PostgreSQLConnection) -> Future<Void> {
        return Database.create(self, on: connection) {
            (builder) in
            try addProperties(to: builder)
            // foreign key constraint to Forum
            builder.reference(from: \.forumID, to: \Forum.id)
        }
    }
}

// MARK: - Timestamping Conformance

extension ForumPost {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}

// MARK: - Relations

extension ForumPost {
    /// The parent `User`  who authored the post.
    var author: Parent<ForumPost, User> {
        return parent(\.authorID)
    }
    
    /// The child `ForumEdit` accountability records of the post.
    var edits: Children<ForumPost, ForumEdit> {
        return children(\.postID)
    }

    /// The parent `Forum` of the post.
    var forum: Parent<ForumPost, Forum> {
        return parent(\.forumID)
    }
    
    /// The sibling `User`s who have "liked" the post.
    var likes: Siblings<ForumPost, User, PostLikes> {
        return siblings()
    }
}

// MARK: - Functions

extension ForumPost {
    /// Converts an `ForumPost` model to a version omitting data that not for public
    /// consumption.
    func convertToData(bookmarked: Bool, userLike: LikeType?, likeCount: Int) throws -> PostData {
        return try PostData(
            postID: self.requireID(),
            createdAt: self.createdAt ?? Date(),
            authorID: self.authorID,
            text: self.isQuarantined ? "This post is under moderator review." : self.text,
            image: self.isQuarantined ? "" : self.image,
            isBookmarked: bookmarked,
            userLike: userLike,
            likeCount: likeCount
        )
    }
}

extension Future where T: ForumPost {
    /// Converts a `Future<ForumPost>` to a `Future<PostData>`. This extension provides
    /// the convenience of simply using `post.convertToData()` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToData(bookmarked: Bool, userLike: LikeType?, likeCount: Int) -> Future<PostData> {
        return self.map {
            (forumPost) in
            return try forumPost.convertToData(
                bookmarked: bookmarked,
                userLike: userLike,
                likeCount: likeCount
            )
        }
    }
}

