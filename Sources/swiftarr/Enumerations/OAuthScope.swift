import Foundation

/// Represents the available OAuth scopes in the application.
///
/// OAuth scopes define the level of access that client applications
/// can request from users. Each scope represents a specific permission.
public enum OAuthScope: String, CaseIterable, Codable, Sendable {
	// OpenID Connect standard scopes
	case openid = "openid"           // Required for OpenID Connect functionality
	
	// Swiftarr-specific scopes
	case photostreamView = 			"twitarr:photostream:view"
	case photostreamSubmit = 		"twitarr:photostream:submit"
	case userUsername = 			"twitarr:user:username"
	case userPublicinfo = 			"twitarr:user:publicinfo"
	case userMessage = 				"twitarr:user:message"
	case userNotify = 				"twitarr:user:notify"
	case userViewAvatar = 			"twitarr:user:view-avatar"
	case userViewAccessLevel = 		"twitarr:user:view-access-level"
	
	/// The display name shown to users in consent screens and documentation
	var displayName: String {
		switch self {
		case .openid:
			return "Identify your Account"
		case .photostreamView:
			return "View Photostream Submissions"
		case .photostreamSubmit:
			return "Submit Photos to Photostream"
		case .userUsername:
			return "View Your Username"
		case .userPublicinfo:
			return "View Your Public Info (Team, Pronouns, Name, etc)"
		case .userMessage:
			return "Send Messages to You"
		case .userNotify:
			return "Send Push Notifications"
		case .userViewAvatar:
			return "View Your Avatar"
		case .userViewAccessLevel:
			return "View Your TwitArr Permissions"
		}
	}
	
	/// A human-readable description of what this scope allows
	var description: String {
		switch self {
		case .openid:
			return "Allows the application to authenticate you as a TwitArr user"
		case .photostreamView:
			return "Allows the application to view photos you've submitted to the photostream"
		case .photostreamSubmit:
			return "Allows the application to submit photos to the photostream on your behalf"
		case .userUsername:
			return "Allows the application to see your username"
		case .userPublicinfo:
			return "Allows the application to see your public profile information including your name, pronouns, and dinner team"
		case .userMessage:
			return "Allows the application to send direct messages and seamail to you"
		case .userNotify:
			return "Allows the application to send you push notifications"
		case .userViewAvatar:
			return "Allows the application to view your profile picture"
		case .userViewAccessLevel:
			return "Allows the application to see your access level on TwitArr (user, moderator, admin, etc.)"
		}
	}
	
	/// Gets all the available scopes as a space-separated string
	static var allScopesString: String {
		Self.allCases.map { $0.rawValue }.joined(separator: " ")
	}
	
	/// Parse a space-separated scope string into an array of OAuthScope values
	/// - Parameter scopeString: Space-separated string of scope values
	/// - Returns: Array of OAuthScope values
	static func parse(_ scopeString: String) -> [OAuthScope] {
		let scopeStrings = scopeString.split(separator: " ").map(String.init)
		return scopeStrings.compactMap { scopeStr in
			OAuthScope(rawValue: scopeStr)
		}
	}
	
	/// Convert an array of OAuthScope values to a space-separated string
	/// - Parameter scopes: Array of OAuthScope values
	/// - Returns: Space-separated string of scope values
	static func toString(_ scopes: [OAuthScope]) -> String {
		scopes.map { $0.rawValue }.joined(separator: " ")
	}
}
