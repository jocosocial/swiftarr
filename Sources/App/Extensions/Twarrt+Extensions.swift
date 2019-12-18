import Vapor
import FluentPostgreSQL

// model uses Int as primary key
extension Twarrt: PostgreSQLModel {}

// model can be passed as HTTP body data
extension Twarrt: Content {}

// model can be used as endpoint paramter
extension Twarrt: Parameter {}

extension Twarrt: Migration {}

// MARK: - Timestamping Conformance

extension Twarrt {
    /// Required key for `\.createdAt` functionality.
    static var createdAtKey: TimestampKey? { return \.createdAt }
    /// Required key for `\.updatedAt` functionality.
    static var updatedAtKey: TimestampKey? { return \.updatedAt }
    /// Required key for `\.deletedAt` soft delete functionality.
    static var deletedAtKey: TimestampKey? { return \.deletedAt }
}

// MARK: - Relations

extension Twarrt {
    /// The parent `User` who authored the twarrt.
    var author: Parent<Twarrt, User> {
        return parent(\.authorID)
    }
    
    /// The child `TwarrtEdit` accountability records of the twarrt.
    var edits: Children<Twarrt, TwarrtEdit> {
        return children(\.twarrtID)
    }
    
    /// The sibling `User`s who have "liked" the twarrt.
    var likes: Siblings<Twarrt, User, TwarrtLikes> {
        return siblings()
    }
}

// MARK: - Functions

extension Twarrt {
    /// Converts a `Twarrt` model to a version omitting data that is not for public consumption.
    func convertToData(bookmarked: Bool, userLike: LikeType?, likeCount: Int) throws -> TwarrtData {
        return try TwarrtData(
            postID: self.requireID(),
            createdAt: self.createdAt ?? Date(),
            authorID: self.authorID,
            text: self.text,
            image: self.image,
            replyToID: self.replyToID,
            isBookmarked: bookmarked,
            userLike: userLike,
            likeCount: likeCount
        )
    }
}

extension Future where T: Twarrt {
    /// Converts a `Future<Twarrt>` to a `Future<TwarrtData>`. This extension provides
    /// the convenience of simply using `twarrt.convertToData()` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToData(bookmarked: Bool, userLike: LikeType?, likeCount: Int) -> Future<TwarrtData> {
        return self.map {
            (twarrt) in
            return try twarrt.convertToData(
                bookmarked: bookmarked,
                userLike: userLike,
                likeCount: likeCount
            )
        }
    }
}
