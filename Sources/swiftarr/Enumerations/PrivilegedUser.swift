import Fluent
import Vapor

// Creating this one place to write down the usernames of the privileged
// users that we create. It's hard to remember if the username is "TwitarrTeam",
// "twitarrteam", "Twitarrteam", etc. There are a lot of areas of the code that
// will need backfilled with these values.
enum PrivilegedUser: String, CaseIterable, Codable {
	// Twitarr Team
	case TwitarrTeam
	// Moderator
	case moderator
	// Admin
	case admin
	// THO
	case THO
}

extension PrivilegedUser {
	// Returns the url query parameter comparison version of the usernames.
	// Generally we use .lowercased() for url query param comparison.
	var queryParam: String {
		return self.rawValue.lowercased()
	}

	/// Service accounts that can authenticate with passwords via HTTP Basic Auth.
	/// These are builtin accounts with known passwords (from environment variables).
	/// Note: moderator and TwitarrTeam cannot authenticate as their passwords are randomly generated and discarded.
	/// Stored as lowercase for case-insensitive matching.
	static let serviceAccountsWithPasswords: Set<String> = ["admin", "prometheus", "tho"]

	/// Case-insensitive match against `queryParam` (lowercased `rawValue`).
	init?(fromQueryParam raw: String) {
		let needle = raw.lowercased()
		guard let match = PrivilegedUser.allCases.first(where: { $0.queryParam == needle }) else {
			return nil
		}
		self = match
	}

	/// Whether `callerAccessLevel` may author announcements as this privileged account.
	/// TwitarrTeam: self/TwitarrTeam/admin. THO: self/THO/admin. Admin: all three.
	/// Unknown values including moderator are not allowed.
	func canPostAs(from callerAccessLevel: UserAccessLevel) -> Bool {
		switch self {
		case .TwitarrTeam:
			return callerAccessLevel == .twitarrteam || callerAccessLevel == .admin
		case .THO:
			return callerAccessLevel == .tho || callerAccessLevel == .admin
		case .admin:
			return callerAccessLevel.hasAccess(.twitarrteam)
		case .moderator:
			return false
		}
	}
}
