import Redis
import Vapor

/// A type of event that can change the value of the global notification handler's `UserNotificationData` result.
///
/// When certain database-mutating events occur, the notification bookkeeping methods need to be called to keep our
/// cached notification counts up to date. The notification counts themselves are database-denormalizing, but they're a cache
/// intended to improve the performance of the global notification method.
///
/// How notifications are stored in Redis:
/// - Announcements: `ActiveAnnouncementIDs` holds announcement IDs for all active announcements, Its updated frequently
/// 	to catch expiring announcements.
/// - Mentions: Fields `twarrtMention` and `forumMention` in hash-valued key `NotificationHash-\(userID)` hold the total
/// 	number of @mentions for each user--this should be equal to the # of results a text search for `@<username>` will return. Counts are
/// 	updated on each post, post edit, and post deletion.
/// - Alertwords: All alertwords by all users are kept in a sorted set keyed by `alertwords`. The value for each entry in the set is the number of users
/// 	watching on that alertword. When someone posts, we get all fields in `alertwords` with values > 0. We then intersect the words in the post
/// 	with the words from alertwords. For any words in the intersection, we get the set-valued key `alertwordusers-\(word)` to get the set of
/// 	users watching on that particular word. We then increment the count of the field `alertwordTweet-\(word)` in key `NotificationHash-\(userID)`.
/// - LFG Posts/Seamails: When a post is created, we increment a field named with the chats' ID in the `UnreadLFGs-\(userID)` or `UnreadSeamails-\(userID)` key.
/// 	When a post is deleted, we decrement the same field, only for users that haven't seen the post (their unseen count is less than how far back the deleted post is).
/// - Next Event Time: Every time an event is followed/unfollowed, we calculate the time of the next event in the followed list, storing that in the `nextFollowedEventTime` field
/// 	in `NotificationHash-\(userID)`.
///
/// How notifications are marked 'viewed' in Redis:
/// - Announcements:  Each user stores the # of their highest-read announcement in the `announcement` field of the hash-valued key `NotificationHash-\(userID)`.
/// 	The number of announcements with IDs > the highest-read announceemnt are 'new' to that user. This means an announceement could appear and then expire unseen
/// 	by a user, and their unseen count would continue to be correct.
/// - Mentions: The # of mentions the user has viewed are stored in `twarrtMention_viewed` in the `NotificationHash-\(userID)` key, and set equal
/// 	to the relevant @mention count when a user's own mentions are viewed (that is, twarrts/posts are requested with a query of `mentionSelf` or similar).
/// - Alertwords: Similar to Mentions; the # of alertword hits that have been viewed is stored in `alertwordTweet-\(word)_viewed`. The difference between this
/// 	field and `alertwordTweet-\(word)` equals the number of new, unseen alertword hits. The `_viewed` field is set equal to the count field upon viewing hits.
/// - Fez Posts: When the fez is viewed (more corectly, the getSingleFez api call is made), we set the # of unseen posts for the fez to 0.
/// - Next Event Time: Never gets deleted, but can get expired when the current time is > the event time.
///
enum NotificationType {
// Notifies Everyone
	/// An app-wide announcement. Associated value is the ID of the announcement.
	case announcement(Int)

// Added to Chat - only fires when someone else adds you to their chat
	///  Only for 'open' seamails. The owner of the chata has added this user.
	case addedToChat(UUID, FezType)

// New Chat Messages
	/// A new message posted to a fez. Associated value is the ID of the fez. (NOT the id of the new message).
	case chatUnreadMsg(UUID, FezType)

// Starting Soon
	/// An upcoming event that the user has followed.
	case nextFollowedEventTime(Date?, UUID?)
	/// An event the user is following is about to start.
	case followedEventStarting(UUID)
	/// An upcoming LFG that the user has joined.
	case nextJoinedLFGTime(Date?, UUID?)
	/// An LFG the user is joined is about to start.
	case joinedLFGStarting(UUID)
	/// A Personal Event the user has created or was added to is about to start.
	case personalEventStarting(UUID)
	/// An LFG or Private Event the user has joined has been cancelled.
	case chatCanceled(UUID, FezType)

// @mentions and Alertwords
	/// A twarrt has been posted that contained a word that a user was alerting on. Associated value is a tuple. First is the alert word that matched.
	/// Second is the twarrt id. Could also happen if an existing twarrt was edited, and the edit adds the alert word to the text.
	case alertwordTwarrt(String, Int)
	/// A new forum post that contains a word that a user was alerting on. Associated value is a tuple. First is the alert word that matched.
	/// Second is the post ID. Could also happen if an existing post was edited, and the edit adds the alert word to the text.
	case alertwordPost(String, Int)
	/// A new or edited twarrt that now @mentions a user. Associated value is the twarrt ID.
	case twarrtMention(Int)
	/// A new or edited forum post that now @mentions a user. Associated value is the post ID.
	case forumMention(Int)
	/// A new or edited forum post that now @mentions @moderator. Associated value is the post ID.
	case moderatorForumMention(Int)
	/// A new or edited forum post that now @mentions @twitarrteam. Associated value is the post ID.
	case twitarrTeamForumMention(Int)

// Micro Karaoke
	/// A Micro Karaoke song the user contributed to is ready for viewing. Associated value is song ID
	case microKaraokeSongReady(Int)

	/// Returns the hash field name used to store info about this notification type in Redis.
	func redisFieldName() -> String {
		switch self {
		case .announcement: return "announcement"
		
		case .addedToChat(let msgID, _): return msgID.uuidString
		case .chatCanceled(let msgID, _): return msgID.uuidString
		case .chatUnreadMsg(let msgID, _): return msgID.uuidString
		
		case .nextFollowedEventTime: return "nextFollowedEventTime"
		case .followedEventStarting: return "followedEventStarting"
		case .nextJoinedLFGTime: return "nextJoinedLFGTime"
		case .joinedLFGStarting: return "joinedLFGStarting"
		case .personalEventStarting: return "personalEventStarting"

		case .alertwordTwarrt(let str, _): return "alertwordTweet-\(str)"
		case .alertwordPost(let str, _): return "alertwordPost-\(str)"
		case .twarrtMention: return "twarrtMention"
		case .forumMention: return "forumMention"
		case .moderatorForumMention: return "moderatorForumMention"
		case .twitarrTeamForumMention: return "twitarrTeamForumMention"
		
		case .microKaraokeSongReady: return "microKaraokeSongReady"
		}
	}

	/// Some notification types store both 'current counts' and 'viewed counts'. Thie builds the Redis field name for the viewed counts.
	func redisViewedFieldName() -> String {
		return redisFieldName() + "_viewed"
	}

	/// Returns the Redis Key used to store info about this notification type in Redis.
	func redisKeyName(userID: UUID) -> RedisKey {
		switch self {
		case .announcement: return "NotificationHash-\(userID)"
		
		case .addedToChat: return "UnreadChats-\(userID)"
		case .chatUnreadMsg: return "UnreadSeamails-\(userID)"
		case .chatCanceled: return "NotificationHash-\(userID)"
		
		case .nextFollowedEventTime: return "NotificationHash-\(userID)"
		case .followedEventStarting: return "NotificationHash-\(userID)"
		case .nextJoinedLFGTime: return "NotificationHash-\(userID)"
		case .joinedLFGStarting: return "NotificationHash-\(userID)"
		case .personalEventStarting: return "NotificationHash-\(userID)"

		case .alertwordTwarrt: return "NotificationHash-\(userID)"
		case .alertwordPost: return "NotificationHash-\(userID)"
		case .twarrtMention: return "NotificationHash-\(userID)"
		case .forumMention: return "NotificationHash-\(userID)"
		case .moderatorForumMention: return "NotificationHash-\(userID)"
		case .twitarrTeamForumMention: return "NotificationHash-\(userID)"

		case .microKaraokeSongReady: return "NotificationHash-\(userID)"
		}
	}

	/// The global notificaiton method pulls all the notification data out of this key and builds its data transfer struct from it.
	static func redisHashKeyForUser(_ userID: UUID) -> RedisKey {
		return "NotificationHash-\(userID)"
	}

	/// A shortcut method to get the RedisKey to use to store notification data about a chat.
//	static func redisKeyForChat(_ fez: FriendlyFez, userID: UUID) throws -> RedisKey {
//xxx
//		case .open, .closed: return NotificationType.chatUnreadMsg(fez.fezType).redisKeyName(userID: userID)
//		
//		}
//		return try [.open, .closed].contains(fez.fezType)
//			? NotificationType.seamailUnreadMsg(fez.requireID()).redisKeyName(userID: userID)
//			: NotificationType.fezUnreadMsg(fez.requireID()).redisKeyName(userID: userID)
//	}

	// Returns the db object ID for the given notification type
	func objectID() -> String {
		switch self {
		case .announcement(let id): return String(id)
		
		case .addedToChat(let uuid, _): return String(uuid)
		case .chatUnreadMsg(let uuid, _): return String(uuid)
		case .chatCanceled(let uuid, _): return String(uuid)

		case .nextFollowedEventTime(_, let uuid): return uuid != nil ? String(uuid!) : ""
		case .followedEventStarting(let id): return String(id)
		case .nextJoinedLFGTime(_, let uuid): return uuid != nil ? String(uuid!) : ""
		case .joinedLFGStarting(let id): return String(id)
		case .personalEventStarting(let id): return String(id)

		case .alertwordTwarrt(_, let id): return String(id)
		case .alertwordPost(_, let id): return String(id)
		case .twarrtMention(let id): return String(id)
		case .forumMention(let id): return String(id)
		case .moderatorForumMention(let id): return String(id)
		case .twitarrTeamForumMention(let id): return String(id)
		
		case .microKaraokeSongReady(let songID): return String(songID)
		}
	}
}
