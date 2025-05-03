import Fluent
import Vapor

/// Represents an OAuth access token issued to a client application.
final class OAuthToken: Model, Content {
	static let schema = "oauth_tokens"
	
	@ID(key: .id)
	var id: UUID?
	
	/// The access token string
	@Field(key: "access_token")
	var accessToken: String
	
	/// The refresh token string (optional)
	@Field(key: "refresh_token")
	var refreshToken: String?
	
	/// Relation to the client that owns this token
	@Parent(key: "client_id")
	var client: OAuthClient
	
	/// Relation to the user who authorized this token
	@Parent(key: "user_id")
	var user: User
	
	/// Scopes authorized for this token (space-separated)
	@Field(key: "scopes")
	var scopes: String
	
	/// When this access token expires
	@Field(key: "expires_at")
	var expiresAt: Date
	
	/// When this refresh token expires (if any)
	@Field(key: "refresh_token_expires_at")
	var refreshTokenExpiresAt: Date?
	
	/// Whether this token has been revoked
	@Field(key: "is_revoked")
	var isRevoked: Bool
	
	/// Creation timestamp
	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?
	
	/// Update timestamp
	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?
	
	init() {}
	
	init(
		id: UUID? = nil,
		accessToken: String,
		refreshToken: String? = nil,
		clientID: UUID,
		userID: UUID,
		scopes: String,
		expiresAt: Date,
		refreshTokenExpiresAt: Date? = nil
	) {
		self.id = id
		self.accessToken = accessToken
		self.refreshToken = refreshToken
		self.$client.id = clientID
		self.$user.id = userID
		self.scopes = scopes
		self.expiresAt = expiresAt
		self.refreshTokenExpiresAt = refreshTokenExpiresAt
		self.isRevoked = false
	}
}
