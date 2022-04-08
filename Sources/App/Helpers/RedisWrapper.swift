import Foundation
import Vapor
import Redis

extension Request.Redis {
// MARK: Notification State Change
	func addUsersWithStateChange(_ userIDs: [UUID]) async throws {
		_ = try await sadd(userIDs, to: "UsersWithNotificationStateChange").get()
	}
	
	func testAndClearStateChange(_ userID: UUID) async throws -> Bool {
		return try await srem(userID, from: "UsersWithNotificationStateChange").get() != 0
	}


// MARK: User Hash
	func userHashRedisKey(userID: UUID) -> RedisKey {
		return RedisKey("NotificationHash-\(userID)")
	}
	
	func getUserHash(userID: UUID) async throws -> [String: RESPValue] {
		let hash = try await hgetall(from: userHashRedisKey(userID: userID)).get()
		return hash
	}
	
	func getIntFromUserHash(_ hash: [String: RESPValue], field: NotificationType, viewed: Bool = false) -> Int {
		return hash[viewed ? field.redisFieldName() : field.redisViewedFieldName()]?.int ?? 0
	}
	
	func getUUIDFromUserHash(_ hash: [String: RESPValue], field: NotificationType) -> UUID? {
		if let value = hash[field.redisFieldName()]?.string {
			return UUID(value)
		}
		return nil
	}
	
	func getNextEventFromUserHash(_ hash: [String: RESPValue]) -> (Date, UUID)? {
		if let values = hash["nextFollowedEvent"]?.string?.split(separator: " "), values.count == 2, let doubleDate = Double(values[0]),
				let eventID = UUID(uuidString: String(values[1])) {
			return (Date(timeIntervalSince1970: doubleDate), eventID)
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
		

// MARK: Karaoke Song Managers
	static let karaokeManagerRedisKey = RedisKey("KaraokeSongManagers")

	func getKaraokeManagers() async throws -> [UUID] {
		let managersIDOptionals = try await smembers(of: Request.Redis.karaokeManagerRedisKey, as: UUID.self).get()
		return managersIDOptionals.compactMap { $0 }
	}
	
	func isKaraokeManager(_ userID: UUID) async throws -> Bool {
		return try await sismember(userID, of: Request.Redis.karaokeManagerRedisKey).get()
	}
	
	func addKaraokeManager(userID: UUID) async throws {
		let numAdds = try await sadd(userID, to: Request.Redis.karaokeManagerRedisKey).get()
		if numAdds == 0 {
			throw Abort(.badRequest, reason: "Cannot promote to Karaoke Manager: user is already a Karaoke Manager.")
		}
	}
	
	func removeKaraokeManager(userID: UUID) async throws {
		let numRemoves = try await srem(userID, from: Request.Redis.karaokeManagerRedisKey).get()
		if numRemoves == 0 {
			throw Abort(.badRequest, reason: "Cannot demote: User isn't a Karaoke Manager.")
		}
	}
	
// MARK: Hashtags
	static let hashtagsRedisKey = RedisKey("hashtags")

	func getHashtags(matching: String) async throws -> [String] {
		let strings = try await zrangebylex(from: Request.Redis.hashtagsRedisKey, 
				withValuesBetween: (min: .inclusive(matching), max: .inclusive("\(matching)\u{FF}")), 
				limitBy: (offset: 0, count: 10)).get()
		return strings.map { $0.description }
	}
	
	func addHashtags(_ hashtags: Set<String>) async throws {
		let hashtagTuples = hashtags.map { ($0, 0.0 ) }
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

	static let alertwordsRedisKey = RedisKey("alertwords")
	
	// Gets all alertwords set by all users. Used to perform a set intersection against the words in a new post or twarrt.
	func getAllAlertwords() async throws -> Set<String> {
		let alertWordArray = try await smembers(of: Request.Redis.alertwordsRedisKey).get()
		let alertSet = Set(alertWordArray.compactMap { String.init(fromRESP: $0) })
		return alertSet
	}
	
	func addAlertword(_ word: String) async throws {
		let _ = try await sadd(word, to: Request.Redis.alertwordsRedisKey).get()
	}
	
	func removeAlertword(_ word: String) async throws {
		let _ = try await srem(word, from: Request.Redis.alertwordsRedisKey).get()
	}
	
	// Gets a list of users that are alerting on a particular alertword
	func getUsersForAlertword(_ word: String) async throws -> [UUID] {
		let userIDs = try await smembers(of: "alertwordUsers-\(word)", as: UUID.self).get().compactMap { $0 }
		return userIDs
	}


// MARK: Announcements
	static let activeAnnouncementRedisKey = RedisKey("ActiveAnnouncementIDs")

	func getActiveAnnouncementIDs() async throws -> [Int]? {
		let alertIDStr = try await get(Request.Redis.activeAnnouncementRedisKey, as: String.self).get()
		return alertIDStr?.split(separator: " ").compactMap { Int($0) }
	}
	
	func setActiveAnnouncementIDs(_ ids: [Int]) async throws {
		let idStr = ids.map { String($0) }.joined(separator: " ")
		let _ = try await set(Request.Redis.activeAnnouncementRedisKey, to: idStr, onCondition: .none, expiration: .seconds(60)).get()
	}
	
	// Clears the cache, forcing a recalculation of the active announcements
	func resetActiveAnnouncementIDs() async throws {
		_ = try await delete(Request.Redis.activeAnnouncementRedisKey).get()
	}

// MARK: Seamails
	enum MailInbox {
		case seamail
		case moderatorSeamail
		case twitarrTeamSeamail
		case lfgMessages
	}
	
	func unreadMailRedisKey(_ userID: UUID, inbox: MailInbox) -> RedisKey {
		switch inbox {
			case .seamail: return RedisKey("UnreadSeamails-\(userID)")
			case .moderatorSeamail: return RedisKey("UnreadModSeamails-\(userID)")
			case .twitarrTeamSeamail: return RedisKey("UnreadTTSeamails-\(userID)")
			case .lfgMessages: return RedisKey("UnreadFezzes-\(userID)")
		}
	}

	func getSeamailUnreadCounts(userID: UUID, inbox: MailInbox) async throws -> Int {
		let seamailHash = try await	hvals(in: unreadMailRedisKey(userID, inbox: inbox), as: Int.self).get()
		let unreadSeamailCount = seamailHash.reduce(0) { $1 ?? 0 > 0 ? $0 + 1 : $0 }
		return unreadSeamailCount
	}
	
	func markSeamailRead(type: NotificationType, in inbox: MailInbox, userID: UUID) async throws {
		_ = try await hset(type.redisFieldName(), to: 0, in: unreadMailRedisKey(userID, inbox: inbox)).get()
	}

	// Call this when a message is added to a LFG or seamail
	func newUnreadMessage(msgID: UUID, userID: UUID, inbox: MailInbox) async throws {
		_ = try await hincrby(1, field: msgID.uuidString, in: unreadMailRedisKey(userID, inbox: inbox)).get()
	}
	
	// Call this when a message in a LFG or seamail is deleted
	func deletedUnreadMessage(msgID: UUID, userID: UUID, inbox: MailInbox) async throws {
		_ = try await hincrby(-1, field: msgID.uuidString, in: unreadMailRedisKey(userID, inbox: inbox)).get()
	}
	
	// Call this when a LFG is deleted. Currently Seamail threads can't be deleted.
	func markLFGDeleted(msgID: UUID, userID: UUID) async throws {
		_ = try await hdel(msgID.uuidString, from: unreadMailRedisKey(userID, inbox: .lfgMessages)).get()
	}
	
// MARK: Blocks
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
}

extension RedisClient {
	
// MARK: Settings
	func readSetting(_ field: String) async throws -> RESPValue {
		return try await hget(field, from: "Settings").get()
	}
	
	func writeSetting(_ field: String, value: RESPValue) async throws -> Bool {
		return try await hset(field, to: value, in: "Settings").get()
	}
}

extension Application.Redis {

	// Redis stores blocks as users you've blocked AND users who have blocked you,
	// for all subaccounts of both you and the other user.
	func getBlocks(for userUUID: UUID) throws -> [UUID] {
		let redisKey: RedisKey = "rblocks:\(userUUID.uuidString)"
		let blocks = try smembers(of: redisKey, as: UUID.self).wait()
		return blocks.compactMap { $0 }
	}
}
