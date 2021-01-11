import Foundation
import Vapor
import FluentPostgreSQL

/// A `UserNote` is intended as a free-form test field that will appear on a `UserProfile`,
/// in which the viewing `User` can make notes about the profile's user.
///
/// It is not visible to the profile's owner nor to any other user; it is for the viewing
/// user's use only. In other words, different users viewing the same profile will each see
/// their own viewer-specific `UserNote` text.

final class UserNote: Codable {
     typealias Database = PostgreSQLDatabase
    // MARK: Properties
    
    /// The note's ID, provisioned automatically.
    var id: UUID?
    
    /// The ID of the `User` owning the note.
    var userID: UUID
    
    /// The ID of the `UserProfile` to which the note is associated.
    var profileID: UUID
    
    /// The text of the note.
    var note: String
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    /// Timestatmp of the model's last update, set automatically.
    var updatedAt: Date?
    
    // MARK: Initialization
    
    /// Creates a new UserNote.
    ///
    /// - Parameters:
    ///   - userID: The ID of the note's owner.
    ///   - profileID: The ID of the associated profile.
    ///   - note: The text of the note.
    init(userID: UUID, profileID: UUID, note: String = "") {
        self.userID = userID
        self.profileID = profileID
        self.note = note
    }
}
