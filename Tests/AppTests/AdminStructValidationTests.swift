import XCTVapor
@testable import swiftarr

class AdminStructValidationTests: XCTestCase {

	private let decoder = ValidatingJSONDecoder()

	private func validationErrors<T: Decodable>(_ type: T.Type, _ json: String) throws -> [String] {
		let data = json.data(using: .utf8)!
		let result = try decoder.validate(type, from: data)
		return result?.validationFailures.map { $0.errorString } ?? []
	}

	private func iso8601ms(_ date: Date) -> String {
		ISO8601DateFormatter([.withInternetDateTime, .withFractionalSeconds]).string(from: date)
	}

	// MARK: - AnnouncementCreateData

	func testAnnouncement_Valid() throws {
		let future = iso8601ms(Date().addingTimeInterval(3600))
		let json = #"{"text":"hello","displayUntil":"\#(future)"}"#
		XCTAssertEqual(try validationErrors(AnnouncementCreateData.self, json), [])
	}

	func testAnnouncement_TextEmpty() throws {
		let future = iso8601ms(Date().addingTimeInterval(3600))
		let json = #"{"text":"","displayUntil":"\#(future)"}"#
		let errs = try validationErrors(AnnouncementCreateData.self, json)
		XCTAssertTrue(errs.contains("Text cannot be empty"), "errs=\(errs)")
	}

	func testAnnouncement_TextTooLong() throws {
		let long = String(repeating: "a", count: 2000)
		let future = iso8601ms(Date().addingTimeInterval(3600))
		let json = #"{"text":"\#(long)","displayUntil":"\#(future)"}"#
		let errs = try validationErrors(AnnouncementCreateData.self, json)
		XCTAssertTrue(errs.contains("Announcement text has a 2000 char limit"), "errs=\(errs)")
	}

	func testAnnouncement_DisplayUntilInPast_Fails() throws {
		let past = iso8601ms(Date().addingTimeInterval(-3600))
		let json = #"{"text":"hello","displayUntil":"\#(past)"}"#
		let errs = try validationErrors(AnnouncementCreateData.self, json)
		XCTAssertTrue(errs.contains("Announcement DisplayUntil date must be in the future."), "errs=\(errs)")
	}

	// MARK: - HuntCreateData

	func testHunt_Valid_OnePuzzle() throws {
		let json = #"""
		{
			"title":"Hunt",
			"description":"desc",
			"puzzles":[{"title":"P1","body":"clue","answer":"42","hints":{}}]
		}
		"""#
		XCTAssertEqual(try validationErrors(HuntCreateData.self, json), [])
	}

	func testHunt_NoPuzzles_Fails() throws {
		let json = #"{"title":"Hunt","description":"desc","puzzles":[]}"#
		let errs = try validationErrors(HuntCreateData.self, json)
		XCTAssertTrue(errs.contains("Puzzles cannot be empty"), "errs=\(errs)")
	}
}
