import XCTVapor
@testable import swiftarr

// Converting sched.com API sessions into Events.
class SchedSessionTests: XCTestCase {

	private func testData(_ name: String) throws -> Data {
		let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("TestData/\(name)")
		return try Data(contentsOf: url)
	}

	private func session(
		active: String = "Y",
		start: String = "2026-03-21 10:00",
		end: String = "2026-03-21 11:30",
		type: String = "Gaming",
		subtype: String? = nil,
		description: String? = nil,
		venue: String? = "Atrium",
		address: String? = nil
	) -> SchedSession {
		SchedSession(id: "abc123", active: active, name: "Test Session", eventStart: start, eventEnd: end,
				startTimeTS: 1_774_098_000, eventType: type, eventSubtype: subtype, description: description, venue: venue,
				address: address)
	}

	// MARK: - Full schedule

	// The API export and the .ics export were captured together. Switching sources must not look like a schedule change.
	func testExportMatchesICS() throws {
		let sessions = try SchedSession.decodeSessions(from: ByteBuffer(data: try testData("SchedExport2026.json")))
		let apiEvents = try sessions.compactMap { try $0.makeEvent() }
		let icsString = String(decoding: try testData("FullSchedule2026.ics"), as: UTF8.self)
		let icsEvents = try EventParser().parse(icsString)

		XCTAssertEqual(sessions.count, 518)
		XCTAssertEqual(apiEvents.count, 517, "Inactive sessions should be skipped")
		let icsByUID = Dictionary(uniqueKeysWithValues: icsEvents.map { ($0.uid, $0) })
		XCTAssertEqual(Set(apiEvents.map(\.uid)), Set(icsByUID.keys))
		for apiEvent in apiEvents {
			guard let icsEvent = icsByUID[apiEvent.uid] else {
				continue
			}
			XCTAssertEqual(apiEvent.startTime, icsEvent.startTime, apiEvent.uid)
			XCTAssertEqual(apiEvent.endTime, icsEvent.endTime, apiEvent.uid)
			XCTAssertEqual(apiEvent.title, icsEvent.title, apiEvent.uid)
			XCTAssertEqual(apiEvent.info, icsEvent.info, apiEvent.uid)
			XCTAssertEqual(apiEvent.location, icsEvent.location, apiEvent.uid)
			XCTAssertEqual(apiEvent.eventType, icsEvent.eventType, apiEvent.uid)
		}
		XCTAssertEqual(apiEvents.filter { $0.ageRating != nil }.count, 233)
	}

	// MARK: - makeEvent

	func testMakeEvent_InactiveSessionIsSkipped() throws {
		XCTAssertNil(try session(active: "N").makeEvent())
	}

	func testMakeEvent_TimesComeFromTimestampAndDuration() throws {
		let event = try XCTUnwrap(try session(start: "2026-03-21 23:30", end: "2026-03-22 01:00").makeEvent())
		XCTAssertEqual(event.startTime, Date(timeIntervalSince1970: 1_774_098_000))
		XCTAssertEqual(event.endTime.timeIntervalSince(event.startTime), 90 * 60)
	}

	func testMakeEvent_AcceptsTimesWithSeconds() throws {
		let event = try XCTUnwrap(try session(start: "2026-03-21 10:00:00", end: "2026-03-21 10:45:00").makeEvent())
		XCTAssertEqual(event.endTime.timeIntervalSince(event.startTime), 45 * 60)
	}

	func testMakeEvent_UnparseableTimeThrows() {
		XCTAssertThrowsError(try session(start: "tomorrow").makeEvent())
	}

	func testMakeEvent_LocationJoinsVenueAndAddress() throws {
		XCTAssertEqual(try session(address: "Deck 1, Midship").makeEvent()?.location, "Atrium, Deck 1, Midship")
		XCTAssertEqual(try session().makeEvent()?.location, "Atrium")
		XCTAssertEqual(try session(venue: nil, address: "Deck 1").makeEvent()?.location, "Deck 1")
	}

	func testMakeEvent_MissingDescriptionIsEmpty() throws {
		XCTAssertEqual(try session().makeEvent()?.info, "")
	}

	func testMakeEvent_AgeRatingFromSubtype() throws {
		for rating in AgeRating.allCases {
			XCTAssertEqual(try session(subtype: rating.label).makeEvent()?.ageRating, rating)
		}
		XCTAssertEqual(try session(subtype: "adults only").makeEvent()?.ageRating, .adultsOnly)
		XCTAssertNil(try session(subtype: "Something Else").makeEvent()?.ageRating)
		XCTAssertNil(try session().makeEvent()?.ageRating)
	}

	func testMakeEvent_EventTypeFromCategory() throws {
		XCTAssertEqual(try session(type: "Shadow Cruise").makeEvent()?.eventType, .shadow)
		XCTAssertEqual(try session(type: "Q&A / Panel").makeEvent()?.eventType, .qaPanel)
		XCTAssertEqual(try session(type: "Mystery").makeEvent()?.eventType, .general)
	}

	// MARK: - plainText

	func testPlainText_StripsTagsAndCollapsesWhitespace() {
		XCTAssertEqual(
			SchedSession.plainText(fromHTML: "Line one.<br /> <br /> See <a href=\"https://x.test\">this page</a>.\n"),
			"Line one. See this page."
		)
	}

	func testPlainText_KeepsNonBreakingSpaces() {
		XCTAssertEqual(SchedSession.plainText(fromHTML: "a.\u{a0}  b"), "a.\u{a0} b")
	}

	func testPlainText_DecodesAmpersandEntity() {
		XCTAssertEqual(SchedSession.plainText(fromHTML: "Tom &amp; Jerry"), "Tom & Jerry")
	}

	// MARK: - decodeSessions

	func testDecodeSessions_SchedErrorBodyThrows() {
		XCTAssertThrowsError(try SchedSession.decodeSessions(from: ByteBuffer(string: "ERR: Authorization failed.")))
	}

	func testDecodeSessions_NonJSONThrows() {
		XCTAssertThrowsError(try SchedSession.decodeSessions(from: ByteBuffer(string: "<html></html>")))
	}

	// MARK: - EventType(schedCategory:)

	func testEventTypeFromSchedCategory() {
		XCTAssertEqual(EventType(schedCategory: "GAMING"), .gaming)
		XCTAssertEqual(EventType(schedCategory: "Q&A"), .qaPanel)
		XCTAssertEqual(EventType(schedCategory: "panel"), .qaPanel)
		XCTAssertEqual(EventType(schedCategory: "Reading"), .readingPerformance)
		XCTAssertEqual(EventType(schedCategory: " Dining "), .dining)
		XCTAssertEqual(EventType(schedCategory: "General Info"), .general)
	}
}
