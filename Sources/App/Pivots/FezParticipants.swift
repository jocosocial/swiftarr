import Foundation
import Fluent

/// A `Pivot` holding a siblings relation between `User` and `FriendlyFez`.

final class FezParticipant: Model {
    static let schema = "fez+participants"

// MARK: Properties
    /// The ID of the pivot.
    @ID(key: .id) var id: UUID?
    
    /// How many posts in this fez that this user has read. Used by the notification lifecycle and
    /// to scroll the post view to show the first unread message.
    @Field(key: "read_count") var readCount: Int

    /// How many posts in this fez that this user cannot see, due to mutes and blocks.
    @Field(key: "hidden_count") var hiddenCount: Int
        
// MARK: Relationships
    /// The associated `User` who likes this.
	@Parent(key: "user") var user: User

    /// The associated `FriendlyFez` the user is a member of.
    @Parent(key: "friendly_fez") var fez: FriendlyFez

// MARK: Initialization
    // Used by Fluent
 	init() { }
 	
    /// Initializes a new `FezParticipant` pivot.
    ///
    /// - Parameters:
    ///   - user: The left hand `User` model.
    ///   - post: The right hand `FriendlyFez` model.
    init(_ user: User, _ post: FriendlyFez) throws {
        self.$user.id = try user.requireID()
        self.$user.value = user
        self.$fez.id = try post.requireID()
        self.$fez.value = post
        self.readCount = 0
        self.hiddenCount = 0
    }
}
