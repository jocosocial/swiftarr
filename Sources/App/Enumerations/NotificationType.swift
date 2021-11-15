import Vapor
import Redis

/// A type of event that can change the value of the global notification handler's <doc:UserNotificationData> result.
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
/// - Fez Posts/Seamails: When a post is created, we increment a field named with the fezzes' ID in the `UnreadFezzes-\(userID)` or `UnreadSeamails-\(userID)` key.
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
	case announcement(Int)
	case fezUnreadMsg(UUID)
	case seamailUnreadMsg(UUID)
	case alertwordTwarrt(String)
	case alertwordPost(String)
	case twarrtMention
	case forumMention
	case nextFollowedEventTime(Date?)
	
	// Returns the hash field name used to store info about this notification type in Redis.
	func redisFieldName() -> String {
		switch self {
			case .announcement: return "announcement"
			case .fezUnreadMsg(let msgID): return msgID.uuidString
			case .seamailUnreadMsg(let msgID): return msgID.uuidString
			case .alertwordTwarrt(let str): return "alertwordTweet-\(str)"
			case .alertwordPost(let str): return "alertwordPost-\(str)"
			case .twarrtMention: return "twarrtMention"
			case .forumMention: return "forumMention"
			case .nextFollowedEventTime: return "nextFollowedEventTime"
		}
	}
	
	// Some notification types store both 'current counts' and 'viewed counts'. Thie builds the Redis field name
	// for the viewed counts.
	func redisViewedFieldName() -> String {
		return redisFieldName() + "_viewed"
	}
	
	// Returns the Redis Key used to store info about this notification type in Redis.
	func redisKeyName(userID: UUID) -> RedisKey {
		switch self {
			case .announcement: return "NotificationHash-\(userID)"
			case .fezUnreadMsg: return "UnreadFezzes-\(userID)"
			case .seamailUnreadMsg: return "UnreadSeamails-\(userID)"
			case .alertwordTwarrt: return "NotificationHash-\(userID)"
			case .alertwordPost: return "NotificationHash-\(userID)"
			case .twarrtMention: return "NotificationHash-\(userID)"
			case .forumMention: return "NotificationHash-\(userID)"
			case .nextFollowedEventTime: return "NotificationHash-\(userID)"
		}
	}
	
	// The global notificaiton method pulls all the notification data out of this key and builds its data transfer struct from it. 
	static func redisHashKeyForUser(_ userID: UUID) -> RedisKey {
		 return "NotificationHash-\(userID)"
	}
	
	// A shortcut method to get the RedisKey to use to store notification data about a fez.
	static func redisKeyForFez(_ fez: FriendlyFez, userID: UUID) throws -> RedisKey {
		return try fez.fezType == .closed ? NotificationType.seamailUnreadMsg(fez.requireID()).redisKeyName(userID: userID) :
				NotificationType.fezUnreadMsg(fez.requireID()).redisKeyName(userID: userID)
	}
}


/* WebSockets
	WS routes must be API-level, authed with token. Unlikely we'll allow sockets for unauthed.
	
	new+active announcements
	new+total twarrt mentions
	new+total forum mentions
	new semail messages
	new fez messages
	for each alertword: twarrt and forum new+total mention counts
	
	disabled features, global
 */
