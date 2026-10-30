import XCTVapor
@testable import swiftarr

/// Tests the JSON that notification websocket clients receive. Clients rely on `contentID` to deep link to the content
/// and on `secondaryContentID` to know which parent (the forum) a post belongs to.
class SocketNotificationPayloadTests: XCTestCase {

	private let forumID = UUID().uuidString

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
		XCTAssertEqual(json["secondaryContentID"] as? String, forumID)
	}

	func testModeratorForumMention_IncludesPostAndForum() throws {
		let json = try payload(.moderatorForumMention(42, forumID))
		XCTAssertNotNil((json["type"] as? [String: Any])?["moderatorForumMention"])
		XCTAssertEqual(json["contentID"] as? String, "42")
		XCTAssertEqual(json["secondaryContentID"] as? String, forumID)
	}

	func testTwitarrTeamForumMention_IncludesPostAndForum() throws {
		let json = try payload(.twitarrTeamForumMention(42, forumID))
		XCTAssertNotNil((json["type"] as? [String: Any])?["twitarrTeamForumMention"])
		XCTAssertEqual(json["contentID"] as? String, "42")
		XCTAssertEqual(json["secondaryContentID"] as? String, forumID)
	}

	func testAlertwordPost_IncludesPostAndForum() throws {
		let json = try payload(.alertwordPost("kraken", 42, forumID))
		XCTAssertNotNil((json["type"] as? [String: Any])?["alertwordPost"])
		XCTAssertEqual(json["contentID"] as? String, "42")
		XCTAssertEqual(json["secondaryContentID"] as? String, forumID)
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

	// MARK: - notificationID (notification log de-dupe)

	func testNotificationID_WhenProvided_IsIncludedInPayload() throws {
		let notificationID = UUID()
		let msg = SocketNotificationData(.twarrtMention(7), info: "info", id: "7", notificationID: notificationID)
		let data = try JSONEncoder().encode(msg)
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		XCTAssertEqual(json["notificationID"] as? String, notificationID.uuidString)
	}

	func testNotificationID_WhenOmitted_IsNotInPayload() throws {
		let json = try payload(.twarrtMention(7))
		XCTAssertNil(json["notificationID"])
	}

	func testPhoneCall_HasNoNotificationID() throws {
		let data = try JSONEncoder().encode(SocketNotificationData(forCallAnswered: UUID()))
		let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
		XCTAssertNil(json["notificationID"])
	}

	// MARK: - NotificationTypeData.databaseKey (Notification log storage)

	// `type` itself must keep encoding as `{"caseName": {}}` for the live socket push (clients depend on this
	// shape), so the notification log stores a separately-computed string key instead of a `RawValue`. Every
	// case must round-trip through that key, or rows written for that case can never be read back.
	func testNotificationTypeData_DatabaseKey_RoundTripsForEveryCase() throws {
		for type in SocketNotificationData.NotificationTypeData.allCases {
			let key = type.databaseKey
			let decoded = try XCTUnwrap(
				SocketNotificationData.NotificationTypeData(databaseKey: key),
				"Failed to decode databaseKey \"\(key)\" back to \(type)"
			)
			XCTAssertEqual(decoded, type)
		}
	}

	func testNotificationTypeData_DatabaseKey_UnknownKeyDecodesToNil() {
		XCTAssertNil(SocketNotificationData.NotificationTypeData(databaseKey: "notARealCase"))
	}

	// MARK: - NotificationLogData(_:) (Notification log read path)

	// A row written under a case that's since been renamed/removed must not take down the whole log fetch--
	// see `AlertController.notificationLogHandler(_:)`, which drops rows this returns nil for instead of
	// propagating a throw.
	func testNotificationLogData_UnrecognizedTypeKey_ReturnsNil() throws {
		let entry = NotificationLogEntry()
		entry.id = UUID()
		entry.typeKey = "notARealCaseAnymore"
		entry.info = "whatever"
		entry.contentID = "0"
		XCTAssertNil(try NotificationLogData(entry))
	}
}
