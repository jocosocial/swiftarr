import Foundation
import Vapor
import Fluent


/// A `UserNote` is intended as a free-form test field that will appear on a `UserProfile`,
/// in which the viewing `User` can make notes about the profile's user.
///
/// It is not visible to the profile's owner nor to any other user; it is for the viewing
/// user's use only. In other words, different users viewing the same profile will each see
/// their own viewer-specific `UserNote` text.

final class UserNote: Model {
	static let schema = "usernotes"

    // MARK: Properties
    
    /// The note's ID, provisioned automatically.
    @ID(key: .id) var id: UUID?
    
    /// The text of the note.
    @Field(key: "note") var note: String
    
    /// Timestamp of the model's creation, set automatically.
	@Timestamp(key: "created_at", on: .create) var createdAt: Date?
    
    /// Timestamp of the model's last update, set automatically.
    @Timestamp(key: "updated_at", on: .update) var updatedAt: Date?
    
	// MARK: Relations

    /// The `User` owning the note.
    @Parent(key: "author") var author: User
    
    /// The `UserProfile` to which the note is associated.
    @Parent(key: "profile") var profile: UserProfile
    
    // MARK: Initialization
    
    // Used by Fluent
 	init() { }
 	
    /// Creates a new UserNote.
    ///
    /// - Parameters:
    ///   - author: The note's author.
    ///   - profile: The associated `UserProfile`.
    ///   - note: The text of the note.
    init(author: User, profile: UserProfile, note: String = "") throws {
        self.$author.id = try author.requireID()
        self.$author.value = author
        self.profile = profile
        self.note = note
    }
}
