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
	// Community Support: a shared mailbox for the Community Support team. Like moderator and TwitarrTeam it's a phantom account
	// nobody logs in as, but membership is by `UserRoleType.communitysupport` (or TwitarrTeam and above) rather than by access level.
	case CommunitySupport
}

extension PrivilegedUser {
	/// Usernames that ordinary users can't register or rename to, case-insensitively. The other privileged names are protected by the
	/// username uniqueness check, but `CommunitySupport` is created by a migration that may run on a database where somebody has
	/// already taken the name; validation keeps them from taking it after the fact.
	static func isReservedUsername(_ username: String) -> Bool {
		PrivilegedUser.CommunitySupport.matches(username)
	}

	/// True if the username belongs to a shared-mailbox phantom account (see `PrivilegedMailbox.all`). Moderator and TwitarrTeam are protected
	/// from things like being blocked by their access level, but the CommunitySupport account is only `.verified`--code that exempts accounts
	/// based on `accessLevel >= .moderator` must also check this, or users could block the team's shared mailbox and lose its replies.
	static func isSharedMailboxAccount(_ username: String) -> Bool {
		let name = username.lowercased()
		return PrivilegedMailbox.all.contains { $0.user.queryParam == name }
	}

	/// Whether `name` names this account, ignoring case: the check for `?foruser=` values, `postAs` values, and `@mention` names (without the "@").
	func matches(_ name: String) -> Bool {
		name.lowercased() == queryParam
	}

	/// The cached phantom account for this user, or nil if the migration that creates it hasn't run on this instance.
	func cachedUser(on req: Request) -> UserCacheData? {
		req.userCache.getUser(username: rawValue)
	}

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

	/// Whether callerAccessLevel may author this privileged account for the content type.
	func canPostAs(from callerAccessLevel: UserAccessLevel, for content: AuthorableContentType) -> Bool {
		switch content {
		case .announcement:
			switch self {
			case .TwitarrTeam:
				return callerAccessLevel == .twitarrteam || callerAccessLevel == .admin
			case .THO:
				return callerAccessLevel == .tho || callerAccessLevel == .admin
			case .admin:
				return callerAccessLevel.hasAccess(.twitarrteam)
			case .moderator:
				return false
			case .CommunitySupport:
				// Posting as Community Support is gated on a role, not an access level; see `PostContentData.postAsCommunitySupport`.
				return false
			}
		}
	}
}
