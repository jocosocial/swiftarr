import Fluent
import Vapor

final class OAuthGrant: Model, Content, @unchecked Sendable {
    static let schema = "oauth_grants"
    
    @ID(key: .id)
    var id: UUID?
    
    /// The OAuth client that was granted access
    @Parent(key: "client_id")
    var client: OAuthClient
    
    /// The user who granted access
    @Parent(key: "user_id")
    var user: User
    
    /// The scopes granted by the user
    @Field(key: "scopes")
    var scopes: String
    
    /// When the grant was created
    @Timestamp(key: "created_at", on: .create)
    var createdAt: Date?
    
    /// When the grant was last updated (e.g., if scopes change)
    @Timestamp(key: "updated_at", on: .update)
    var updatedAt: Date?
    
    /// Default initializer
    init() {}
    
    /// Creates a new OAuth grant between a user and client with specific scopes
    init(clientID: UUID, userID: UUID, scopes: String) {
        self.$client.id = clientID
        self.$user.id = userID
        self.scopes = scopes
    }
    
    /// Convenience initializer from client and user objects
    init(client: OAuthClient, user: User, scopes: String) throws {
        self.$client.id = try client.requireID()
        self.$user.id = try user.requireID()
        self.scopes = scopes
    }
    
    /// Convenience method to get the scopes as a set of OAuthScope enum values
    func getScopeObjects() -> [OAuthScope] {
        return OAuthScope.parse(scopes)
    }
    
    /// Check if this grant covers all the requested scopes
    func coversScopes(_ requestedScopes: String) -> Bool {
        let grantedScopeSet = Set(scopes.split(separator: " ").map { String($0) })
        let requestedScopeSet = Set(requestedScopes.split(separator: " ").map { String($0) })
        
        // Check if all requested scopes are included in the granted scopes
        return requestedScopeSet.isSubset(of: grantedScopeSet)
    }
}