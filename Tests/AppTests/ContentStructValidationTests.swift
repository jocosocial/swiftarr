import XCTVapor
@testable import swiftarr

// Tests for the RCFValidatable conformances on content-creation request structs:
// ForumCreateData, NoteCreateData, PostContentData.
class ContentStructValidationTests: XCTestCase {

	private let decoder = ValidatingJSONDecoder()

	private func validationErrors<T: Decodable>(_ type: T.Type, _ json: String) throws -> [String] {
		let data = json.data(using: .utf8)!
		let result = try decoder.validate(type, from: data)
		return result?.validationFailures.map { $0.errorString } ?? []
	}

	private let validFirstPost = #"{"text":"hello","images":[],"postAsModerator":false,"postAsTwitarrTeam":false}"#

	// MARK: - ForumCreateData

	func testForumCreate_Valid() throws {
		let json = #"{"title":"My Forum","firstPost":\#(validFirstPost)}"#
		XCTAssertEqual(try validationErrors(ForumCreateData.self, json), [])
	}

	func testForumCreate_TitleTooShort() throws {
		let json = #"{"title":"x","firstPost":\#(validFirstPost)}"#
		let errs = try validationErrors(ForumCreateData.self, json)
		XCTAssertTrue(errs.contains("forum title has a 2 character minimum"), "errs=\(errs)")
	}

	func testForumCreate_TitleTooLong() throws {
		let title = String(repeating: "a", count: 101)
		let json = #"{"title":"\#(title)","firstPost":\#(validFirstPost)}"#
		let errs = try validationErrors(ForumCreateData.self, json)
		XCTAssertTrue(errs.contains("forum title has a 100 character limit"), "errs=\(errs)")
	}

	// MARK: - NoteCreateData

	func testNoteCreate_Valid() throws {
		XCTAssertEqual(try validationErrors(NoteCreateData.self, #"{"note":"hi"}"#), [])
	}

	func testNoteCreate_Empty() throws {
		let errs = try validationErrors(NoteCreateData.self, #"{"note":""}"#)
		XCTAssertTrue(errs.contains("post text cannot be empty."), "errs=\(errs)")
	}

	func testNoteCreate_TooLong() throws {
		let long = String(repeating: "a", count: 1000)
		let errs = try validationErrors(NoteCreateData.self, #"{"note":"\#(long)"}"#)
		XCTAssertTrue(errs.contains(where: { $0.contains("over the 1000 character limit") }), "errs=\(errs)")
	}

	func testNoteCreate_TooManyLines() throws {
		// 26 lines (25 newlines) — over the 25-line limit. Use JSON-escaped \n.
		let lines = (1...26).map { "L\($0)" }.joined(separator: "\\n")
		let errs = try validationErrors(NoteCreateData.self, #"{"note":"\#(lines)"}"#)
		XCTAssertTrue(errs.contains("posts are limited to 25 lines of text"), "errs=\(errs)")
	}

	func testNoteCreate_CRLFNormalizedBeforeLineCount() throws {
		// Spec: \r\n is normalized to \r before counting lines, so this is 25 lines, not 50.
		let segments = (1...25).map { "L\($0)" }.joined(separator: "\\r\\n")
		let errs = try validationErrors(NoteCreateData.self, #"{"note":"\#(segments)"}"#)
		// Should NOT trip the 25-line limit.
		XCTAssertFalse(errs.contains("posts are limited to 25 lines of text"), "errs=\(errs)")
	}

	// MARK: - PostContentData

	func testPostContent_Valid() throws {
		let errs = try validationErrors(PostContentData.self, #"{"text":"hello","images":[],"postAsModerator":false,"postAsTwitarrTeam":false}"#)
		XCTAssertEqual(errs, [])
	}

	func testPostContent_Empty() throws {
		let errs = try validationErrors(PostContentData.self, #"{"text":"","images":[],"postAsModerator":false,"postAsTwitarrTeam":false}"#)
		XCTAssertTrue(errs.contains("post text cannot be empty."), "errs=\(errs)")
	}

	func testPostContent_TextTooLong() throws {
		let long = String(repeating: "a", count: 2048)
		let errs = try validationErrors(PostContentData.self, #"{"text":"\#(long)","images":[],"postAsModerator":false,"postAsTwitarrTeam":false}"#)
		XCTAssertTrue(errs.contains(where: { $0.contains("over the 2048 character limit") }), "errs=\(errs)")
	}

	func testPostContent_TooManyImages() throws {
		let nineImages = (1...9).map { _ in #"{"filename":null,"image":null}"# }.joined(separator: ",")
		let json = #"{"text":"hi","images":[\#(nineImages)],"postAsModerator":false,"postAsTwitarrTeam":false}"#
		let errs = try validationErrors(PostContentData.self, json)
		XCTAssertTrue(errs.contains("posts are limited to 8 image attachments"), "errs=\(errs)")
	}

	func testPostContent_TooManyLines() throws {
		let lines = (1...26).map { "L\($0)" }.joined(separator: "\\n")
		let errs = try validationErrors(PostContentData.self, #"{"text":"\#(lines)","images":[],"postAsModerator":false,"postAsTwitarrTeam":false}"#)
		XCTAssertTrue(errs.contains("posts are limited to 25 lines of text"), "errs=\(errs)")
	}
}
