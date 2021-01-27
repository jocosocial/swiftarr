import Foundation
import Fluent

/// A `Pivot` holding a sibllings relation between `User` and `Twarrt`.

final class TwarrtLikes: Model {
    static let schema = "twarrt+likes"

    // MARK: Properties
    
    /// The ID of the pivot.
    @ID(key: .id) var id: UUID?
    
    /// The type of like reaction. Needs to be optional to conform to `ModifiablePivot`'s
    /// required `init(_:_:)`.
    @Field(key: "liketype") var likeType: LikeType?
    
    // MARK: Relations
    
    /// The associated `User` who likes this.
	@Parent(key: "user") var user: User

    /// The associated `Twarrt` that was liked.
    @Parent(key: "twarrt") var twarrt: Twarrt

    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new TwarrtLikes pivot.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - twarrt: The right hand `Twarrt` model.
    init(_ user: User, _ twarrt: Twarrt) throws{
        self.$user.id = try user.requireID()
        self.$user.value = user
        self.$twarrt.id = try twarrt.requireID()
        self.$twarrt.value = twarrt
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
}
