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
    /// The sibling `User`s who have "liked" the twarrt.
    var likes: Siblings<Twarrt, User, TwarrtLikes> {
        return siblings()
    }
}

// MARK: - Functions

extension Twarrt {
    /// Converts a `Twarrt` model to a version omitting data that is of no interest to a user.
    func convertToData(withLike userLike: LikeType?, likeCount: Int) throws -> PostData {
        return try PostData(
            postID: self.requireID(),
            createdAt: self.createdAt ?? Date(),
            authorID: self.authorID,
            text: self.text,
            image: self.image,
            userLike: userLike,
            likeCount: likeCount
        )
    }
}

extension Future where T: Twarrt {
    /// Converts a `Future<Twarrt>` to a `Future<PostData>`. This extension provides
    /// the convenience of simply using `twarrt.convertToData()` and allowing the compiler to
    /// choose the appropriate version for the context.
    func convertToData(withLike userLike: LikeType?, likeCount: Int) -> Future<PostData> {
        return self.map {
            (twarrt) in
            return try twarrt.convertToData(withLike: userLike, likeCount: likeCount)
        }
    }
}
