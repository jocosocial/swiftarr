import Vapor

/// What a user must hold to read a privileged mailbox--and, equivalently, who the mailbox's phantom
/// account fans out to when it's addressed or participates in a chat. Expressing this as data (rather
/// than writing "is this user a moderator or does this user have role X" by hand at each call site)
/// means the roster expansion and the access check can never drift apart.
enum PrivilegedMailboxRequirement {
	case accessLevel(UserAccessLevel)
	case role(UserRoleType)
	/// Satisfied by either holding `role`, or having at least `accessLevel`--e.g. the pending
	/// Community Support mailbox (#517), which any holder of its role can read, as can any
	/// TwitarrTeam-and-above user regardless of role.
	case roleOrAccessLevel(UserRoleType, UserAccessLevel)

	/// Whether a user with the given accessLevel/roles may read this mailbox.
	func isSatisfied(accessLevel: UserAccessLevel, roles: Set<UserRoleType>) -> Bool {
		switch self {
		case .accessLevel(let requiredLevel): return accessLevel.hasAccess(requiredLevel)
		case .role(let requiredRole): return roles.contains(requiredRole)
		case .roleOrAccessLevel(let requiredRole, let requiredLevel):
			return roles.contains(requiredRole) || accessLevel.hasAccess(requiredLevel)
		}
	}

	/// Convenience overload for callers that already have a `UserCacheData`.
	func isSatisfied(by user: UserCacheData) -> Bool {
		isSatisfied(accessLevel: user.accessLevel, roles: user.userRoles)
	}

	/// All real (non-phantom) users who satisfy this requirement--the roster this mailbox fans out to.
	func members(on req: Request) -> [UserCacheData] {
		switch self {
		case .accessLevel(let level): return req.userCache.allUsersWithAccessLevel(level)
		case .role(let role): return req.userCache.allUsersWithRole(role)
		case .roleOrAccessLevel(let role, let level):
			let byLevel = req.userCache.allUsersWithAccessLevel(level)
			let byRole = req.userCache.allUsersWithRole(role).filter { user in !byLevel.contains { $0.userID == user.userID } }
			return byLevel + byRole
		}
	}
}

/// Describes one privileged shared mailbox: a non-loginable phantom `User` (see `PrivilegedUser`) that
/// stands in for "every real user who satisfies `requirement`". A chat addressed to, or containing, the
/// phantom account is really addressed to every member of that roster, each of whom gets their own
/// Redis unread count under `inbox` (see `MailInbox`).
///
/// `PrivilegedMailbox.all` is the single source of truth for every "@moderator"/"@TwitarrTeam"-shaped
/// mailbox's *notification bookkeeping*: the chat-unread fan-out, the `?foruser=` access checks, and
/// the nightly consistency job all key off this table, so adding a new mailbox (see issue #517) means
/// appending a row here, adding a `MailInbox` case, and seeding its phantom account.
/// It does NOT cover authoring or UI: `FezController.createChat`'s `createdByModerator`/
/// `createdByTwitarrTeam` fields, `PostContentData.effectiveAuthor`, `SiteSeamailController`'s
/// `postAsModerator`/`postAsTwitarrTeam` fields, and `ForumController.processForumMentions` still
/// hardcode the moderator/TwitarrTeam pair and need their own updates for a new mailbox to be usable
/// end-to-end.
struct PrivilegedMailbox: Sendable {
	let user: PrivilegedUser
	let inbox: MailInbox
	let requirement: PrivilegedMailboxRequirement
	/// The `Abort(.forbidden)` reason when a user without `requirement` asks for this mailbox by name
	/// (e.g. `?foruser=`).
	let accessDeniedReason: String

	/// Order matters: a chat that somehow contains more than one phantom account resolves to the
	/// *first* matching mailbox here (see `forChat`). This preserves existing behavior, where
	/// TwitarrTeam has always taken precedence over moderator.
	static let all: [PrivilegedMailbox] = [
		PrivilegedMailbox(
			user: .TwitarrTeam,
			inbox: .twitarrTeamSeamail,
			requirement: .accessLevel(.twitarrteam),
			accessDeniedReason: "Only TwitarrTeam members can access TwitarrTeam seamail."
		),
		PrivilegedMailbox(
			user: .moderator,
			inbox: .moderatorSeamail,
			requirement: .accessLevel(.moderator),
			accessDeniedReason: "Only moderators can access moderator seamail."
		),
		// Last on purpose: a chat containing several phantom accounts resolves to the first row, and Community Support must not
		// take precedence over the moderator or TwitarrTeam inbox.
		PrivilegedMailbox(
			user: .CommunitySupport,
			inbox: .communitySupportSeamail,
			requirement: .roleOrAccessLevel(.communitysupport, .twitarrteam),
			accessDeniedReason: "Only Community Support team members can access Community Support seamail."
		),
	]

	/// The cached phantom account for this mailbox, or nil if the seed migration that creates it
	/// hasn't run on this instance.
	func phantomUser(on req: Request) -> UserCacheData? {
		req.userCache.getUser(username: user.rawValue)
	}

	/// All real users who may read this mailbox.
	func members(on req: Request) -> [UserCacheData] {
		requirement.members(on: req)
	}

	/// Whether `user` may read this mailbox.
	func isSatisfied(by user: UserCacheData) -> Bool {
		requirement.isSatisfied(by: user)
	}

	/// Whether a user with the given accessLevel/roles may read this mailbox. Callers that don't have
	/// a `UserCacheData` (e.g. `ConsistencyJobs`, which works from `User` models) should use this
	/// instead of reaching into `requirement` directly.
	func isSatisfied(accessLevel: UserAccessLevel, roles: Set<UserRoleType>) -> Bool {
		requirement.isSatisfied(accessLevel: accessLevel, roles: roles)
	}

	/// Case-insensitive match against a `?foruser=`-style query param, e.g. "moderator"/"twitarrteam".
	/// Returns nil both for an unrecognized name and for a `PrivilegedUser` that isn't a mailbox (e.g.
	/// "admin"/"tho", which are service accounts, not shared mailboxes).
	static func matching(queryParam: String) -> PrivilegedMailbox? {
		guard let user = PrivilegedUser(fromQueryParam: queryParam) else {
			return nil
		}
		return all.first { $0.user == user }
	}

	/// The first mailbox (in `all`'s order) whose phantom account is a member of the given chat
	/// participant list, or nil if none of the phantom accounts are present. Pass `satisfiedBy` to additionally
	/// require that user to hold that mailbox's access requirement--used when resolving which persona
	/// a caller may view a fez's members-only data as; omit it to resolve the fez's own privileged
	/// inbox regardless of who's asking.
	static func forChat(participantArray: [UUID], satisfiedBy user: UserCacheData? = nil, on req: Request) -> PrivilegedMailbox? {
		all.first { mailbox in
			guard let phantom = mailbox.phantomUser(on: req), participantArray.contains(phantom.userID) else {
				return false
			}
			if let user, !mailbox.isSatisfied(by: user) {
				return false
			}
			return true
		}
	}
}
