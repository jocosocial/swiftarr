import Foundation
import Vapor
import FluentPostgreSQL

/// A `RegistrationCode` associates a specific pre-generated code with a specific `User`
/// account, as well as tracks when the association occurred.
///
/// To maintain accountability for conduct on Twit-arr, a user must first register their
/// primary account before gaining the ability to post any content, either public or private.
/// This is done with a unique registration code provided to each participant by Management.
/// The full set of codes (which contain no identifying information) is provided to the
/// Twit-arr admins prior to the event, and they are loaded by a `Migration` during system
/// startup.

final class RegistrationCode: Codable {
    // MARK: Properties
    
    /// The registration code's ID, provisioned automatically.
    var id: UUID?
    
    /// The ID of the User to which this code is associated, if any.
    var userID: UUID?
    
    /// The registration code, normalized to lowercase without spaces.
    var code: String
    
    /// Timestamp of the model's last update, set automatically.
    /// Used to track when the code was assigned.
    var updatedAt: Date?

    // MARK: Initialization
    
    /// Initializes a new RegistrationCode.
    ///
    /// - Parameters:
    ///   - userID: The ID of the User to which the code is associated, `nil` if not yet
    ///   assigned.
    ///   - code: The registration code string.
    init(userID: UUID? = nil, code: String) {
        self.userID = userID
        self.code = code
    }
}
