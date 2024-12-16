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
	/// The mod set a temporary quarantine on the user.
	case tempQuarantine
	/// The mod cleared a temporary quarantine on the user.
	case tempQuarantineCleared

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
}
