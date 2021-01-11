import Foundation
import Vapor
import FluentPostgreSQL
import Authentication

/// A `Token` model associates a randomly generated string with a `User`.
///
/// A Token is generated upon each login, and revoked by deletion upon each logout.
/// The `.token` value is used in between those events in an HTTP Bearer Authorization
/// header field to authenticate the user sending API requests. There is no
/// identifying user info in a `.token`; the association to a specific `User` is
/// done internally on the API server through this model.

final class Token: Codable {
     typealias Database = PostgreSQLDatabase

   // MARK: Properties
    
    /// The Token's ID, provisioned automatically.
    var id: UUID?
    
    /// The generated token value.
    var token: String
    
    /// The ID of the `User` associated to the Token.
    var userID: User.ID
    
    /// Timestamp of the model's creation, set automatically.
    var createdAt: Date?
    
    // MARK: Initializaton
    
    /// Initializes a new Token.
    ///
    /// - Parameters:
    ///   - token: The generated token string.
    ///   - userID: The ID of the `User` associated to the token.
    init(token: String, userID: User.ID) {
        self.token = token
        self.userID = userID
    }
}

