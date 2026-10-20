import XCTVapor
@testable import swiftarr

/// Tests the JSON that notification websocket clients receive. Clients rely on `contentID` to deep link to the content
/// and on `secondaryContentID` to know which parent (the forum) a post belongs to.
class SocketNotificationPayloadTests: XCTestCase {

	private let forumID = UUID()

	// `type` is a synthesized-Codable enum, so it encodes as `{"forumMention": {}}`.
	private func payload(_ type: NotificationType) throws -> [String: Any] {
		let msg = SocketNotificationData(type, info: "info", id: type.objectID())
		let data = try JSONEncoder().encode(msg)
		return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
	}

	// MARK: - Forum events include the forum

	func testForumMention_IncludesPostAndForum() throws {
		let json = try payload(.forumMention(42, forumID))
		XCTAssertNotNil((json["type"] as? [String: Any])?["forumMention"])
		XCTAssertEqual(json["contentID"] as? String, "42")
		XCTAssertEqual(json["secondaryContentID"] as? String, forumID.uuidString)
	}

	func testModeratorForumMention_IncludesPostAndForum() throws {
		let json = try payload(.moderatorForumMention(42, forumID))
		XCTAssertNotNil((json["type"] as? [String: Any])?["moderatorForumMention"])
		XCTAssertEqual(json["contentID"] as? String, "42")
		XCTAssertEqual(json["secondaryContentID"] as? String, forumID.uuidString)
	}

	func testTwitarrTeamForumMention_IncludesPostAndForum() throws {
		let json = try payload(.twitarrTeamForumMention(42, forumID))
		XCTAssertNotNil((json["type"] as? [String: Any])?["twitarrTeamForumMention"])
		XCTAssertEqual(json["contentID"] as? String, "42")
		XCTAssertEqual(json["secondaryContentID"] as? String, forumID.uuidString)
	}

	func testAlertwordPost_IncludesPostAndForum() throws {
		let json = try payload(.alertwordPost("kraken", 42, forumID))
		XCTAssertNotNil((json["type"] as? [String: Any])?["alertwordPost"])
		XCTAssertEqual(json["contentID"] as? String, "42")
		XCTAssertEqual(json["secondaryContentID"] as? String, forumID.uuidString)
	}

	// MARK: - Other events are unchanged

	func testTwarrtMention_HasNoSecondaryContentID() throws {
		let json = try payload(.twarrtMention(7))
		XCTAssertEqual(json["contentID"] as? String, "7")
		XCTAssertNil(json["secondaryContentID"])
	}

	func testAlertwordTwarrt_HasNoSecondaryContentID() throws {
		let json = try payload(.alertwordTwarrt("kraken", 7))
		XCTAssertEqual(json["contentID"] as? String, "7")
		XCTAssertNil(json["secondaryContentID"])
	}

	func testChatUnreadMsg_HasNoSecondaryContentID() throws {
		let fezID = UUID()
		let json = try payload(.chatUnreadMsg(fezID, .open))
		XCTAssertEqual(json["contentID"] as? String, fezID.uuidString)
		XCTAssertNil(json["secondaryContentID"])
	}

	func testPhoneCall_HasNoSecondaryContentID() throws {
		let callID = UUID()
		let data = try JSONEncoder().encode(SocketNotificationData(forCallAnswered: callID))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		XCTAssertEqual(json["contentID"] as? String, callID.uuidString)
		XCTAssertNil(json["secondaryContentID"])
	}

	// MARK: - Missing forum info

	func testForumMention_WithoutForum_OmitsSecondaryContentID() throws {
		let json = try payload(.forumMention(42))
		XCTAssertEqual(json["contentID"] as? String, "42")
		XCTAssertNil(json["secondaryContentID"])
	}

	// MARK: - Bookkeeping isn't affected by the forum

	func testForumID_DoesNotChangeRedisFieldNames() {
		XCTAssertEqual(NotificationType.forumMention(42, forumID).redisFieldName(), NotificationType.forumMention(0).redisFieldName())
		XCTAssertEqual(
			NotificationType.alertwordPost("kraken", 42, forumID).redisFieldName(),
			NotificationType.alertwordPost("kraken", 0).redisFieldName()
		)
	}
}
