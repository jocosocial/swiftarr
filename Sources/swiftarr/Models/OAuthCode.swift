import Fluent
import Vapor

/// Represents an OAuth authorization code issued during the authorization code flow.
final class OAuthCode: Model, Content {
	static let schema = "oauth_codes"
	
	@ID(key: .id)
	var id: UUID?
	
	/// The authorization code string
	@Field(key: "code")
	var code: String
	
	/// Relation to the client that requested this code
	@Parent(key: "client_id")
	var client: OAuthClient
	
	/// Relation to the user who authorized this code
	@Parent(key: "user_id")
	var user: User
	
	/// Redirect URI that was used in the original request
	@Field(key: "redirect_uri")
	var redirectURI: String
	
	/// Scopes authorized for this code (space-separated)
	@Field(key: "scopes")
	var scopes: String
	
	/// Code challenge for PKCE
	@Field(key: "code_challenge")
	var codeChallenge: String?
	
	/// Code challenge method for PKCE
	@Field(key: "code_challenge_method")
	var codeChallengeMethod: String?
	
	/// When this code expires
	@Field(key: "expires_at")
	var expiresAt: Date
	
	/// Whether this code has been used
	@Field(key: "is_used")
	var isUsed: Bool
	
	/// The nonce value provided during authorization (if any)
	@Field(key: "nonce")
	var nonce: String?
	
	/// Creation timestamp
	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?
	
	init() {}
	
	init(
		id: UUID? = nil,
		code: String,
		clientID: UUID,
		userID: UUID,
		redirectURI: String,
		scopes: String,
		codeChallenge: String? = nil,
		codeChallengeMethod: String? = nil,
		expiresAt: Date,
		nonce: String? = nil
	) {
		self.id = id
		self.code = code
		self.$client.id = clientID
		self.$user.id = userID
		self.redirectURI = redirectURI
		self.scopes = scopes
		self.codeChallenge = codeChallenge
		self.codeChallengeMethod = codeChallengeMethod
		self.expiresAt = expiresAt
		self.isUsed = false
		self.nonce = nonce
	}
}
