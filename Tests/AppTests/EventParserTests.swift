import XCTVapor
@testable import swiftarr

class EventParserTests: XCTestCase {

	private let parser = EventParser()

	// MARK: - unescapedTextValue

	func testUnescapedTextValue_PassesThroughPlainText() {
		XCTAssertEqual(parser.unescapedTextValue("hello world"), "hello world")
	}

	func testUnescapedTextValue_DecodesAmpersandEntity() {
		XCTAssertEqual(parser.unescapedTextValue("Tom &amp; Jerry"), "Tom & Jerry")
	}

	func testUnescapedTextValue_DecodesEscapedComma() {
		XCTAssertEqual(parser.unescapedTextValue(#"alpha\,beta"#), "alpha,beta")
	}

	func testUnescapedTextValue_DecodesEscapedSemicolon() {
		XCTAssertEqual(parser.unescapedTextValue(#"alpha\;beta"#), "alpha;beta")
	}

	func testUnescapedTextValue_DecodesLowercaseNewlineEscape() {
		XCTAssertEqual(parser.unescapedTextValue(#"line1\nline2"#), "line1\nline2")
	}

	func testUnescapedTextValue_DecodesUppercaseNewlineEscape() {
		// RFC 5545 allows both \n and \N
		XCTAssertEqual(parser.unescapedTextValue(#"line1\Nline2"#), "line1\nline2")
	}

	func testUnescapedTextValue_DecodesEscapedBackslash() {
		XCTAssertEqual(parser.unescapedTextValue(#"path\\to\\file"#), #"path\to\file"#)
	}

	func testUnescapedTextValue_HandlesMultipleEscapesInOneString() {
		XCTAssertEqual(
			parser.unescapedTextValue(#"Hello\, world\nLine 2 &amp; more"#),
			"Hello, world\nLine 2 & more"
		)
	}
}
