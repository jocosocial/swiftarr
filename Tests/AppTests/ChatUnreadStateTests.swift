import Redis
import XCTVapor

@testable import swiftarr

// Tests for splitting a raw "Unread<mailbox>-<userID>" Redis hash into added-to chat IDs vs. unread chat counts,
// and for surfacing those IDs on UserNotificationData.
class ChatUnreadStateTests: XCTestCase {

	private let addedToValue = 10000

	private func state(_ hash: [String: Int?]) -> ChatUnreadState {
		return ChatUnreadState(unreadMailHash: hash)
	}

	// MARK: - ChatUnreadState

	func testEmptyInboxHasNoAddedToChats() throws {
		let result = state([:])
		XCTAssertEqual(result.addedToChatIDs, [])
		XCTAssertEqual(result.addedToChatCount, 0)
		XCTAssertEqual(result.unreadChatCount, 0)
	}

	func testAddedToChatIsReportedByID() throws {
		let chatID = UUID()
		let result = state([chatID.uuidString: addedToValue])
		XCTAssertEqual(result.addedToChatIDs, [chatID])
		XCTAssertEqual(result.addedToChatCount, 1)
		XCTAssertEqual(result.unreadChatCount, 0)
	}

	func testUnreadMessagesDoNotProduceAddedToIDs() throws {
		let chatID = UUID()
		let result = state([chatID.uuidString: 3])
		XCTAssertEqual(result.addedToChatIDs, [])
		XCTAssertEqual(result.unreadChatCount, 1)
	}

	// A chat the user was added to that then gets new messages stays above the added-to threshold, so it must
	// keep being reported as an added-to chat and must not also be counted as an unread chat.
	func testAddedToChatWithNewMessagesStaysAddedTo() throws {
		let chatID = UUID()
		let result = state([chatID.uuidString: addedToValue + 7])
		XCTAssertEqual(result.addedToChatIDs, [chatID])
		XCTAssertEqual(result.unreadChatCount, 0)
	}

	func testAddedToIDsAndUnreadCountsAreSeparated() throws {
		let addedFirst = UUID()
		let addedSecond = UUID()
		let unread = UUID()
		let result = state([
			addedFirst.uuidString: addedToValue,
			addedSecond.uuidString: addedToValue + 1,
			unread.uuidString: 2,
		])
		XCTAssertEqual(Set(result.addedToChatIDs), Set([addedFirst, addedSecond]))
		XCTAssertEqual(result.addedToChatCount, 2)
		XCTAssertEqual(result.unreadChatCount, 1)
	}

	// addedToChatCount is derived from addedToChatIDs, so the count a client sees always matches the ID list.
	func testAddedToCountMatchesIDCount() throws {
		let hash = Dictionary(uniqueKeysWithValues: (0..<5).map { _ in (UUID().uuidString, Int?.some(addedToValue)) })
		let result = state(hash)
		XCTAssertEqual(result.addedToChatCount, result.addedToChatIDs.count)
		XCTAssertEqual(result.addedToChatCount, 5)
	}

	// Redis returns nil for hash values that can't be coerced to Int; those entries shouldn't count as anything.
	func testNilHashValuesAreIgnored() throws {
		let chatID = UUID()
		let result = state([chatID.uuidString: nil, UUID().uuidString: nil])
		XCTAssertEqual(result.addedToChatIDs, [])
		XCTAssertEqual(result.unreadChatCount, 0)
	}

	// Defensive: a malformed hash field can't be turned into a chat ID, but it shouldn't crash or be reported.
	func testNonUUIDFieldIsNotReportedAsAddedTo() throws {
		let result = state(["not-a-uuid": addedToValue])
		XCTAssertEqual(result.addedToChatIDs, [])
		XCTAssertEqual(result.addedToChatCount, 0)
	}

	// The threshold is "> 9000"; a chat with 9000 unread messages is still just an unread chat.
	func testValueAtThresholdIsUnreadNotAddedTo() throws {
		let chatID = UUID()
		let result = state([chatID.uuidString: 9000])
		XCTAssertEqual(result.addedToChatIDs, [])
		XCTAssertEqual(result.unreadChatCount, 1)
	}

	// MARK: - UserNotificationData

	func testNotificationDataCarriesAddedToIDsPerInbox() throws {
		let seamailID = UUID()
		let lfgID = UUID()
		let privateEventID = UUID()
		let data = UserNotificationData(
			seamailState: state([seamailID.uuidString: addedToValue, UUID().uuidString: 1]),
			lfgState: state([lfgID.uuidString: addedToValue]),
			privateEventState: state([privateEventID.uuidString: addedToValue]),
			activeAnnouncementIDs: [],
			newAnnouncementCount: 0,
			nextEventTime: nil,
			nextEvent: nil,
			nextLFGTime: nil,
			nextLFG: nil,
			microKaraokeFinishedSongCount: 0
		)
		XCTAssertEqual(data.addedToSeamailIDs, [seamailID])
		XCTAssertEqual(data.addedToLFGIDs, [lfgID])
		XCTAssertEqual(data.addedToPrivateEventIDs, [privateEventID])
		XCTAssertEqual(data.addedToSeamailCount, 1)
		XCTAssertEqual(data.addedToLFGCount, 1)
		XCTAssertEqual(data.addedToPrivateEventCount, 1)
		XCTAssertEqual(data.newSeamailMessageCount, 1)
		XCTAssertEqual(data.newFezMessageCount, 0)
		XCTAssertEqual(data.newPrivateEventMessageCount, 0)
	}

	// The logged-out struct must not leak any chat IDs.
	func testLoggedOutNotificationDataHasEmptyAddedToIDs() throws {
		let data = UserNotificationData()
		XCTAssertEqual(data.addedToSeamailIDs, [])
		XCTAssertEqual(data.addedToLFGIDs, [])
		XCTAssertEqual(data.addedToPrivateEventIDs, [])
	}

	// The new fields are additive, so they must round-trip through the JSON clients actually receive.
	func testAddedToIDsRoundTripThroughJSON() throws {
		let lfgID = UUID()
		let original = UserNotificationData(
			seamailState: state([:]),
			lfgState: state([lfgID.uuidString: addedToValue]),
			privateEventState: state([:]),
			activeAnnouncementIDs: [],
			newAnnouncementCount: 0,
			nextEventTime: nil,
			nextEvent: nil,
			nextLFGTime: nil,
			nextLFG: nil,
			microKaraokeFinishedSongCount: 0
		)
		let encoded = try JSONEncoder().encode(original)
		let decoded = try JSONDecoder().decode(UserNotificationData.self, from: encoded)
		XCTAssertEqual(decoded.addedToLFGIDs, [lfgID])
		XCTAssertEqual(decoded.addedToSeamailIDs, [])
		XCTAssertEqual(decoded.addedToPrivateEventIDs, [])
		XCTAssertEqual(decoded.addedToLFGCount, 1)
	}
}
