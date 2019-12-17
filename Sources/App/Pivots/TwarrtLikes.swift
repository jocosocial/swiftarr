import FluentPostgreSQL
import Foundation

/// A `Pivot` holding a sibllings relation between `User` and `Twarrt`.

final class TwarrtLikes: PostgreSQLUUIDPivot, ModifiablePivot {
    // MARK: Properties
    
    /// The ID of the pivot.
    var id: UUID?
    
    /// The type of like reaction. Needs to be optional to conform to `ModifiablePivot`'s
    /// required `init(_:_:)`.
    var likeType: LikeType?
    
    // MARK: Initialization
    
    /// Initializes a new TwarrtLikes pivot.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - twarrt: The right hand `Twarrt` model.
    init(_ user: User, _ twarrt: Twarrt) throws {
        self.userID = try user.requireID()
        self.twarrtID = try twarrt.requireID()
    }
    
    /// Convenience initializer to provide `.likeType` initialization.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - twarrt: The right hand `Twarrt` model.
    ///   - likeType: The type of like reaction for this pivot.
    convenience init(_ user: User, _ twarrt: Twarrt, likeType: LikeType) throws {
        try self.init(user, twarrt)
        self.likeType = likeType
    }
    
    // MARK: ModifiablePivot Conformance
    
    /// The associated identifier type for `User`.
    var userID: User.ID
    /// The associated identifier type for `Twarrt`.
    var twarrtID: Twarrt.ID
    
    typealias Left = User
    typealias Right = Twarrt
    
    /// Required key for `Pivot` protocol.
    static let leftIDKey: LeftIDKey = \.userID
    /// Required key for `Pivot` protocol.
    static let rightIDKey: RightIDKey = \.twarrtID
}
