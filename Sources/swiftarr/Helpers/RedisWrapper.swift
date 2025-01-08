import Foundation
@preconcurrency import Redis
import Vapor

/// This extends Request.Redis with a bunch of function wrappers that (mostly) make a single Redis call. The function names describe what
/// the functions do in Swiftarr API terms, keeping the Redis keys and specific commands used internal to this file. When looking at the Redis
/// database you can refer to this file to see what various keys are used for, and having all the Redis code here makes it much easier to reason
/// about changes to how we structure data in Redis.
///
/// Unlike Postgres with Fluent, Redis doesn't provide us with a centralized data model for how the db is structured. Having code all over the app
/// call hset directly makes it difficult to answer questions like, "What fields should exist in this hash set?" So, all that is centralized here.
extension RedisClient {
	// MARK: Notification State Change
	//
	// Every user session keeps track of the notifications for that user, as basically every page in the UI has
	// to show state info on the user's active unseen notifications. When a new notification is added we add
	// their userID to this redis set, and then check it on every page we deliver to see if we need to rebuild the
	// session data.
	func addUsersWithStateChange(_ userIDs: [UUID]) async throws {
		_ = try await sadd(userIDs, to: "UsersWithNotificationStateChange").get()
	}

	func testAndClearStateChange(_ userID: UUID) async throws -> Bool {
		return try await srem(userID, from: "UsersWithNotificationStateChange").get() != 0
	}

	// MARK: User Hash
	//
	// This key is a hash for each user. Each entry in the hash tracks either the total number of a type of notification
	// that has been produced, or the total number of those notifications the user has 'seen'. Generally we compute
	// the number of unseen notifications for a notification type by subtracting seen from total. Doing it this way lets
	// us revise the total (if, for example, an announcement is deleted, or a tweet with an @mention is edited to no longer have
	// that @mention) and not screw up the system.
	//
	// A side effect is that we generally only update the 'seen' value by declaring the user 'up to date' with that notification
	// type, and seen gets set to be equal to total.
	//
	// Note that some of the hash keys (like alertwords) use the word as part of the hash key.
	func userHashRedisKey(userID: UUID) -> RedisKey {
		return RedisKey("NotificationHash-\(userID)")
	}

	func getUserHash(userID: UUID) async throws -> [String: RESPValue] {
		let hash = try await hgetall(from: userHashRedisKey(userID: userID)).get()
		return hash
	}

	func getIntFromUserHash(_ hash: [String: RESPValue], field: NotificationType, viewed: Bool = false) -> Int {
		return hash[viewed ? field.redisViewedFieldName() : field.redisFieldName()]?.int ?? 0
	}

	func getUUIDFromUserHash(_ hash: [String: RESPValue], field: NotificationType) -> UUID? {
		if let value = hash[field.redisFieldName()]?.string {
			return UUID(value)
		}
		return nil
	}

	func getNextEventFromUserHash(_ hash: [String: RESPValue]) -> (Date, UUID)? {
		if let values = hash["nextFollowedEvent"]?.string?.split(separator: " "), values.count == 2,
			let doubleDate = Double(values[0]),
			let eventID = UUID(uuidString: String(values[1]))
		{
			return (Date(timeIntervalSince1970: doubleDate), eventID)
		}
		return nil
	}

	func getNextLFGFromUserHash(_ hash: [String: RESPValue]) -> (Date, UUID)? {
		if let values = hash["nextJoinedLFG"]?.string?.split(separator: " "), values.count == 2,
			let doubleDate = Double(values[0]),
			let lfgID = UUID(uuidString: String(values[1]))
		{
			return (Date(timeIntervalSince1970: doubleDate), lfgID)
		}
		return nil
	}

	func markAllViewedInUserHash(field: NotificationType, userID: UUID) async throws {
		let hitCount = try await hget(field.redisFieldName(), from: userHashRedisKey(userID: userID)).get()
		if hitCount != .null {
			_ = try await hset(field.redisViewedFieldName(), to: hitCount, in: userHashRedisKey(userID: userID)).get()
		}
	}

	func setIntInUserHash(to value: Int, field: NotificationType, userID: UUID) async throws {
		_ = try await hset(field.redisFieldName(), to: value, in: userHashRedisKey(userID: userID)).get()
	}

	func incrementIntInUserHash(field: NotificationType, userID: UUID, incAmount: Int = 1) async throws {
		_ = try await hincrby(incAmount, field: field.redisFieldName(), in: userHashRedisKey(userID: userID)).get()
	}

	func incrementAlertwordTwarrtInUserHash(word: String, userID: UUID, incAmount: Int = 1) async throws {
		_ = try await hincrby(incAmount, field: "alertwordTweet-\(word)", in: userHashRedisKey(userID: userID)).get()
	}

	func incrementAlertwordPostInUserHash(word: String, userID: UUID, incAmount: Int = 1) async throws {
		_ = try await hincrby(incAmount, field: "alertwordPost-\(word)", in: userHashRedisKey(userID: userID)).get()
	}

	func setNextEventInUserHash(date: Date?, eventID: UUID?, userID: UUID) async throws {
		if let date = date, let eventID = eventID {
			let value = "\(date.timeIntervalSince1970) \(eventID)"
			_ = try await hset("nextFollowedEvent", to: value, in: userHashRedisKey(userID: userID)).get()
		}
		else {
			_ = try await hdel("nextFollowedEvent", from: userHashRedisKey(userID: userID)).get()
		}
	}

	func setNextLFGInUserHash(date: Date?, lfgID: UUID?, userID: UUID) async throws {
		if let date = date, let lfgID = lfgID {
			let value = "\(date.timeIntervalSince1970) \(lfgID)"
			_ = try await hset("nextJoinedLFG", to: value, in: userHashRedisKey(userID: userID)).get()
		}
		else {
			_ = try await hdel("nextJoinedLFG", from: userHashRedisKey(userID: userID)).get()
		}
	}

	// MARK: Hashtags
	//
	// This is an ordered set of all the hashtags anyone has used. Because of how zrangebylex works, the 'scores' are all 0.
	// We use an ordered set because zrangebylex lets us query for all hashtags that start with a substring, but that only
	// works when all the scores are the same. It'd be nicer if we could increment a tag's score each time it's used, and
	// getHashtags could then return tags matching a substring, ordered by frequency of use.
	static var hashtagsRedisKey: RedisKey {
		return RedisKey("hashtags")
	}

	func getHashtags(matching: String) async throws -> [String] {
		let strings = try await zrangebylex(
			from: Request.Redis.hashtagsRedisKey,
			withValuesBetween: (min: .inclusive(matching), max: .inclusive("\(matching)\u{FF}")),
			limitBy: (offset: 0, count: 10)
		)
		.get()
		return strings.map { $0.description }
	}

	func addHashtags(_ hashtags: Set<String>) async throws {
		let hashtagTuples = hashtags.map { ($0, 0.0) }
		_ = try await zadd(hashtagTuples, to: Request.Redis.hashtagsRedisKey).get()
	}

	// MARK: Alertwords
	//
	// One key - set of all alertwords, or a hash with all alertwords + count of how many users have that word
	// For each alertword - a key with userIDs that have that word
	// For each user - a key with their alertwords
	//
	// OR
	//
	// Table of alert words - one word per row
	// Pivot tying each alert word to each user that has it
	// Each time a user modifies their alertwords, rebuild a Redis key, set with all alertwords
	// This way, each alert could have a count field, and each pivot could have a 'seenCount' field.

	static var alertwordsRedisKey: RedisKey {
		RedisKey("alertwords")
	}

	func getAlertwordUsersRedisKey(_ word: String) -> RedisKey {
		return RedisKey("alertwordUsers-\(word)")
	}

	// Gets all alertwords set by all users. Used to perform a set intersection against the words in a new post or twarrt.
	func getAllAlertwords() async throws -> Set<String> {
		let alertWordArray = try await smembers(of: Request.Redis.alertwordsRedisKey).get()
		let alertSet = Set(alertWordArray.compactMap { String.init(fromRESP: $0) })
		return alertSet
	}

	func addAlertword(_ word: String, userID: UUID) async throws {
		let _ = try await sadd(word, to: Request.Redis.alertwordsRedisKey).get()
		let _ = try await sadd(userID, to: getAlertwordUsersRedisKey(word)).get()
	}

	// Delete an alertword. This should only be called when there are no more users who have
	// this word in their list.
	func removeAlertword(_ word: String) async throws {
		let _ = try await srem(word, from: Request.Redis.alertwordsRedisKey).get()
	}

	// Delete an alertword for a particular user.
	func removeUserAlertword(_ word: String, userID: UUID) async throws {
		let _ = try await srem(userID, from: getAlertwordUsersRedisKey(word)).get()
		let _ = try await hdel("alertwordPost-\(word)", from: userHashRedisKey(userID: userID)).get()
	}

	// Gets a list of users that are alerting on a particular alertword
	func getUsersForAlertword(_ word: String) async throws -> [UUID] {
		let userIDs = try await smembers(of: getAlertwordUsersRedisKey(word), as: UUID.self).get().compactMap { $0 }
		return userIDs
	}

	// MARK: Announcements
	//
	// Each announcement gets a monotonically increasing ID, and announcements have an 'end time' where they
	// automatically stop being shown. This lets us quickly get the currently-active announcement IDs.
	static var activeAnnouncementRedisKey: RedisKey {
		return RedisKey("ActiveAnnouncementIDs")
	}

	func getActiveAnnouncementIDs() async throws -> [Int]? {
		let alertIDStr = try await get(Request.Redis.activeAnnouncementRedisKey, as: String.self).get()
		return alertIDStr?.split(separator: " ").compactMap { Int($0) }
	}

	func setActiveAnnouncementIDs(_ ids: [Int]) async throws {
		let idStr = ids.map { String($0) }.joined(separator: " ")
		let _ = try await set(
			Request.Redis.activeAnnouncementRedisKey,
			to: idStr,
			onCondition: .none,
			expiration: .seconds(60)
		)
		.get()
	}

	// Clears the cache, forcing a recalculation of the active announcements
	func resetActiveAnnouncementIDs() async throws {
		_ = try await delete(Request.Redis.activeAnnouncementRedisKey).get()
	}

	// This returns a tuple where the first Int is the number of chats the user has been added to but not yet viewed,
	// and the second Int is number of chats with unread messages (not the total number of unread messages).
	func getChatUnreadCounts(userID: UUID, inbox: MailInbox) async throws -> (Int, Int) {
		let hash = try await hvals(in: inbox.unreadMailRedisKey(userID), as: Int.self).get()
		let counts = hash.reduce((0, 0)) {
			if let hashVal = $1 {
				if hashVal > 9000 {
					return ($0.0 + 1, $0.1)
				}
				return ($0.0, $0.1 + 1)
			}
			return $0
		}
		return counts
	}

	// Get the unread message count for a given chat in a mailinbox for a user.
	// nil if the value or chat does not exist.
	func getChatUnreadCount(_ chatID: UUID, for userID: UUID, in inbox: MailInbox) async throws -> Int? {
		return try await hget(chatID.uuidString, from: inbox.unreadMailRedisKey(userID), as: Int.self).get()
	}

	// This returns an array of UUIDs representing each Chat ID that is unread according to Redis.
	func getUnreadChats(userID: UUID, inbox: MailInbox) async throws -> [UUID] {
		let keys = try await hkeys(in: inbox.unreadMailRedisKey(userID)).get()
		return keys.compactMap { UUID(uuidString: $0) }
	}

	// `type` must be a Chat notification type. Marks the given chat as fully read.
	func markChatRead(type: NotificationType, in inbox: MailInbox? = nil, userID: UUID) async throws {
		switch type {
		case .chatUnreadMsg(_, let chatType), .addedToChat(_, let chatType):
			let actualInbox = (inbox ?? MailInbox.mailboxForChatType(type: chatType))
			//			_ = try await hset(type.redisFieldName(), to: 0, in: actualInbox.unreadMailRedisKey(userID)).get()
			_ = try await hdel(type.redisFieldName(), from: actualInbox.unreadMailRedisKey(userID)).get()
		default: break
		}
	}

	// Mark a given chat as fully read in Redis.
	func markChatRead(_ fezID: UUID, in inbox: MailInbox, for userID: UUID) async throws {
		_ = try await hdel(String(fezID), from: inbox.unreadMailRedisKey(userID)).get()
	}

	// Call this when a user is added to a chat. In the key "Unread<mailboxname>-<userID>", sets the value
	// of hash "<chatID>" to 10000. When new messages happen in the chat, the value gets incremented by 1;
	// the 'new user' value is large so that we can easily discern chats the user was added to (and has not yet read),
	// while also not reporting both that the user was added and that they have new messages (for the same chat).
	func userAddedToChat(chatID: UUID, userID: UUID, inbox: MailInbox) async throws {
		_ = try await hset(chatID.uuidString, to: 10000, in: inbox.unreadMailRedisKey(userID)).get()
	}

	// Call this when a message is added to a LFG or seamail
	func newUnreadMessage(chatID: UUID, userID: UUID, inbox: MailInbox) async throws {
		_ = try await hincrby(1, field: chatID.uuidString, in: inbox.unreadMailRedisKey(userID)).get()
	}

	// Call this when a message in a LFG or seamail is deleted.
	func deletedUnreadMessage(msgID: UUID, userID: UUID, inbox: MailInbox) async throws {
		_ = try await hincrby(-1, field: msgID.uuidString, in: inbox.unreadMailRedisKey(userID)).get()
	}

	// Call this when a LFG is deleted. Currently Seamail threads can't be deleted.
	func markLFGDeleted(msgID: UUID, userID: UUID) async throws {
		_ = try await hdel(msgID.uuidString, from: MailInbox.lfgMessages.unreadMailRedisKey(userID)).get()
	}

	// MARK: Blocks
	//
	// Blocks are bidirectional filtering of all content between two parent accounts, including all sub-accounts.
	// Postgres stores a list of userIDs that an account has chosen to block. That list always adds the
	// userID of the blockee to the block list of the parent account (if any) of the blocker. This lets the blocker
	// view their blocks, remove a block (importantly, still showing the user that was blocked, not their parent acct),
	// while the blockee sees nothing.
	//
	// To actually enforce blocks we use Redis sets. For each user we make a key of all the userIDs whose content
	// are blocked, regardless of whether the block is incoming or outgoing.
	// If user A blocks user B, "rblocks:A" will contain B's userID and userIDs of accounts under B's parent, and "rblocks:B"
	// will contain all userIDs under A's parent.
	func addBlockedUsers(_ blockedUsers: [UUID], blockedBy requester: UUID) async throws {
		_ = try await sadd(blockedUsers, to: "rblocks:\(requester)").get()
	}

	func removeBlockedUsers(_ blockedUsers: [UUID], blockedBy requester: UUID) async throws {
		_ = try await srem(blockedUsers, from: "rblocks:\(requester)").get()
	}

	// Redis stores blocks as users you've blocked AND users who have blocked you,
	// for all subaccounts of both you and the other user.
	func getBlocks(for userUUID: UUID) async throws -> [UUID] {
		let redisKey: RedisKey = "rblocks:\(userUUID.uuidString)"
		let blocks = try await smembers(of: redisKey, as: UUID.self).get()
		return blocks.compactMap { $0 }
	}

	// MARK: Settings
	//
	// Values in Settings.swift are stored in Redis, using a Redis hash.
	func readSetting(_ field: String) async throws -> RESPValue {
		return try await hget(field, from: "Settings").get()
	}

	func writeSetting(_ field: String, value: RESPValue) async throws -> Bool {
		return try await hset(field, to: value, in: "Settings").get()
	}

	// MARK: Special Purpose
	//
	// These should only be used for data consistency validation, not for general purpose.
	//
	// Sets the unread count
	// for a given MailInbox for given user to a given value.
	func setChatUnreadCount(_ value: Int, chatID: UUID, userID: UUID, inbox: MailInbox) async throws {
		_ = try await hset(chatID.uuidString, to: value, in: inbox.unreadMailRedisKey(userID)).get()
	}
}
