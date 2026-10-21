/// Describes the type of action a moderator took. This enum is used both in the ModeratorAction Model, and in several Moderation DTOs.
/// Be careful when modifying this. Not all ModeratorActionTypes are applicable to all ReportTypes.
enum ModeratorActionType: String, Codable {
	/// The moderator has created a post, but is posting as @moderator or @twitarrTeam. 'Post' could be a twarrt, forum post, or fez post.
	case post
	/// The moderator edited a piece of content owned by somebody else. For `user` content, this means the profile fields (custom avatar images can't be
	/// edited by mods, only deleted).
	case edit
	/// The moderator deleted somebody else's content. For `user` content, this means the user photo (users and profile fields can't be deleted).
	case delete
	/// The moderator moved somebody's content to another place. Currently this means they moved a forum to a new category.
	case move

	/// The moderator has quarantined a user or a piece of content. Quarantined content still exists, but the server replaces the contents with a quarantine message.
	/// A quarantined user can still read content, but cannot post or edit.
	case quarantine
	/// If enough users report on some content (e.g. a twarrt or forum post), that content will get auto-quarantined. A mod can review the content and if it's not in violation
	/// they can set it's modStatus to `markReviewed` to indicate the content is OK. This protects the content from auto-quarantining.
	case markReviewed
	/// The moderator has locked a piece of content. Locking prevents the owner from modifying the content; locking a forum or fez prevents new messages
	/// from being posted.
	case lock
	/// The moderator has unlocked a piece of content.
	case unlock
	/// The moderator has pinned a forum post or thread.
	case pin
	/// The moderator has unpinned a forum post or thread.
	case unpin

	/// The mod set the `userAccessLevel` of a user to `.unverified`
	case accessLevelUnverified
	/// The mod set the `userAccessLevel` of a user to `.banned`
	case accessLevelBanned
	/// The mod set the `userAccessLevel` of a user to `.quarantined`
	case accessLevelQuarantined
	/// The mod set the `userAccessLevel` of a user to `.verified`
	case accessLevelVerified
	/// The mod promoted a user to `.moderator`
	case accessLevelModerator
	/// The mod promoted a user to `.twitarrteam`
	case accessLevelTwitarrTeam
	/// The mod promoted a user to `.tho`
	case accessLevelTHO
	/// The mod set a temporary quarantine on the user.
	case tempQuarantine
	/// The mod cleared a temporary quarantine on the user.
	case tempQuarantineCleared
	/// An account manager searched for a user by their registration code.
	case regCodeSearched
	/// An account manager viewed a user's registration code.
	case regCodeViewed
	/// An account manager re-enabled one-time registration-code password recovery (unlocked the account).
	case accountUnlocked

	static func setFromModerationStatus(_ status: ContentModerationStatus) -> Self {
		switch status {
		case .normal: return .unlock
		case .autoQuarantined: return .quarantine
		case .quarantined: return .quarantine
		case .locked: return .lock
		case .modReviewed: return .markReviewed
		}
	}

	/// Returns nil for access levels that can't be set normally
	static func setFromAccessLevel(_ level: UserAccessLevel) -> Self? {
		switch level {
		case .unverified: return .accessLevelUnverified
		case .banned: return .accessLevelBanned
		case .quarantined: return .accessLevelQuarantined
		case .verified: return .accessLevelVerified
		default: return nil
		}
	}
	
	/// A human-readable name for this action, e.g. for display in the moderator log.
	func visibleName() -> String {
		switch self {
		case .post: return "Posted"
		case .edit: return "Edited"
		case .delete: return "Deleted"
		case .move: return "Moved"
		case .quarantine: return "Quarantined"
		case .markReviewed: return "Marked Reviewed"
		case .lock: return "Locked"
		case .unlock: return "Unlocked"
		case .pin: return "Pinned"
		case .unpin: return "Unpinned"
		case .accessLevelUnverified: return "Set Access Level to Unverified"
		case .accessLevelBanned: return "Set Access Level to Banned"
		case .accessLevelQuarantined: return "Set Access Level to Quarantined"
		case .accessLevelVerified: return "Set Access Level to Verified"
		case .accessLevelModerator: return "Promoted to Moderator"
		case .accessLevelTwitarrTeam: return "Promoted to TwitarrTeam"
		case .accessLevelTHO: return "Promoted to THO"
		case .tempQuarantine: return "Temporarily Quarantined"
		case .tempQuarantineCleared: return "Cleared Temporary Quarantine"
		case .regCodeSearched: return "Searched by Registration Code"
		case .regCodeViewed: return "Viewed Registration Code"
		case .accountUnlocked: return "Unlocked Account"
		}
	}
}
