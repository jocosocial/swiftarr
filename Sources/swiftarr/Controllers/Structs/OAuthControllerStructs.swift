import Vapor
import Fluent

// MARK: - OAuth Client Data Structures

/// Data structure for returning OAuth client data in API responses with grant counts
public struct OAuthClientDataWithGrants: Content, Sendable {
	var client: OAuthClientData
	var grantCount: Int
}

/// Data structure for returning OAuth client data in API responses
public struct OAuthClientData: Content, Sendable {
	var id: UUID
	var clientId: String
	var clientSecret: String
	var name: String
	var description: String
	var website: String
	var privacyPolicyUrl: String?
	var logoUrl: String?
	var backgroundUrl: String?
	var redirectURIs: [String]
	var grantTypes: [String]
	var responseTypes: [String]
	var scopes: [String]
	var scopeObjects: [OAuthScope] // This property conforms to Sendable now
	var isConfidential: Bool
	var isEnabled: Bool
	var createdAt: Date?
	var updatedAt: Date?
	
	init(_ client: OAuthClient) throws {
		self.id = try client.requireID()
		self.clientId = client.clientId
		self.clientSecret = client.clientSecret
		self.name = client.name
		self.description = client.description
		self.website = client.website
		self.privacyPolicyUrl = client.privacyPolicyUrl
		self.logoUrl = client.logoUrl
		self.backgroundUrl = client.backgroundUrl
		self.redirectURIs = client.redirectURIs.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
		self.grantTypes = client.grantTypes.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
		self.responseTypes = client.responseTypes.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
		
		// Parse the scopes string and convert to OAuthScope objects
		let scopeStrings = client.scopes.split(separator: " ").map { String($0) }
		self.scopes = scopeStrings
		self.scopeObjects = OAuthScope.parse(client.scopes)
		
		self.isConfidential = client.isConfidential
		self.isEnabled = client.isEnabled
		self.createdAt = client.createdAt
		self.updatedAt = client.updatedAt
	}
}

/// Data structure for creating a new OAuth client
public struct OAuthClientCreateData: Content {
	var name: String
	var description: String
	var website: String
	var privacyPolicyUrl: String?
	var logoUrl: String?
	var backgroundUrl: String?
	var redirectURIs: [String]
	var grantTypes: [String]
	var responseTypes: [String]
	var scopes: [String]
	var isConfidential: Bool
	
	/// Get the scopes as OAuthScope objects
	var scopeObjects: [OAuthScope] {
		return scopes.compactMap { OAuthScope(rawValue: $0) }
	}
	
	/// Get the scopes as a space-separated string
	var scopesString: String {
		return scopes.joined(separator: " ")
	}
}

/// Data structure for updating an OAuth client
public struct OAuthClientUpdateData: Content {
	var name: String
	var description: String
	var website: String
	var privacyPolicyUrl: String?
	var logoUrl: String?
	var backgroundUrl: String?
	var redirectURIs: [String]
	var grantTypes: [String]
	var responseTypes: [String]
	var scopes: [String]
	var isConfidential: Bool
	var isEnabled: Bool
	
	/// Get the scopes as OAuthScope objects
	var scopeObjects: [OAuthScope] {
		return scopes.compactMap { OAuthScope(rawValue: $0) }
	}
	
	/// Get the scopes as a space-separated string
	var scopesString: String {
		return scopes.joined(separator: " ")
	}
}
