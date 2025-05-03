import Fluent
import Vapor

/// Represents an OAuth client application registered with this server.
final class OAuthClient: Model, Content, Authenticatable {
	static let schema = "oauth_clients"
	
	@ID(key: .id)
	var id: UUID?
	
	/// The client ID used in OAuth flows
	@Field(key: "client_id")
	var clientId: String
	
	/// The client secret used in OAuth flows
	@Field(key: "client_secret")
	var clientSecret: String
	
	/// Human-readable name of the client application
	@Field(key: "name")
	var name: String
	
	/// Description of the client application's purpose
	@Field(key: "description")
	var description: String
	
	/// Website or homepage URL of the client
	@Field(key: "website")
	var website: String
	
	/// URL to the client's privacy policy
	@Field(key: "privacy_policy_url")
	var privacyPolicyUrl: String?
	
	/// URL to the client's logo image
	@Field(key: "logo_url")
	var logoUrl: String?
	
	/// URL to the client's background image
	@Field(key: "background_url")
	var backgroundUrl: String?
	
	/// Redirect URIs allowed for this client (comma-separated)
	@Field(key: "redirect_uris")
	var redirectURIs: String
	
	/// Grant types allowed for this client (comma-separated)
	@Field(key: "grant_types")
	var grantTypes: String
	
	/// Response types allowed for this client (comma-separated)
	@Field(key: "response_types") 
	var responseTypes: String
	
	/// Scopes allowed for this client (space-separated)
	@Field(key: "scopes")
	var scopes: String
	
	/// Whether the client is confidential (can securely store secrets)
	@Field(key: "is_confidential")
	var isConfidential: Bool
	
	/// Whether this client is enabled
	@Field(key: "is_enabled")
	var isEnabled: Bool
	
	/// When this client was created
	@Timestamp(key: "created_at", on: .create)
	var createdAt: Date?
	
	/// Last time this client was updated
	@Timestamp(key: "updated_at", on: .update)
	var updatedAt: Date?
	
	init() {}
	
	init(
		id: UUID? = nil,
		clientId: String,
		clientSecret: String,
		name: String,
		description: String,
		website: String,
		privacyPolicyUrl: String? = nil,
		logoUrl: String? = nil,
		backgroundUrl: String? = nil,
		redirectURIs: String,
		grantTypes: String,
		responseTypes: String,
		scopes: String,
		isConfidential: Bool,
		isEnabled: Bool = true
	) {
		self.id = id
		self.clientId = clientId
		self.clientSecret = clientSecret
		self.name = name
		self.description = description
		self.website = website
		self.privacyPolicyUrl = privacyPolicyUrl
		self.logoUrl = logoUrl
		self.backgroundUrl = backgroundUrl
		self.redirectURIs = redirectURIs
		self.grantTypes = grantTypes
		self.responseTypes = responseTypes
		self.scopes = scopes
		self.isConfidential = isConfidential
		self.isEnabled = isEnabled
	}
}
