import XCTVapor
@testable import swiftarr

class MarkdownPostTextTests: XCTestCase {

	private func render(_ input: String) -> String {
		FormatPostTextTag.markdownPostText(input)
	}

	func testStripsWrapperTags() {
		XCTAssertEqual(render("<Markdown>hello</Markdown>"), "hello")
		XCTAssertEqual(render("<Markdown>\n\n**bold**\n\n</Markdown>"), "\n\n**bold**\n\n")
	}

	func testJocomojiBecomeMarkdownImages() {
		XCTAssertEqual(
			render("<Markdown>:arr: and :back-deck-juice:</Markdown>"),
			"![joco](/img/emoji/small/arr.png) and ![joco](/img/emoji/small/back-deck-juice.png)"
		)
	}

	func testMentionsBecomeMarkdownLinks() {
		XCTAssertEqual(
			render("<Markdown>hello @admin and @challfry</Markdown>"),
			"hello [@admin](/username/admin) and [@challfry](/username/challfry)"
		)
	}

	func testHashtagsBecomeMarkdownLinks() {
		XCTAssertEqual(
			render("<Markdown>this is #arr time</Markdown>"),
			"this is [#arr](/forumpost/search?hashtag=arr) time"
		)
	}

	func testMentionNotConvertedInMiddleOfWord() {
		// The lookbehind requires whitespace or start-of-string before the @.
		XCTAssertEqual(render("<Markdown>email admin@example.com</Markdown>"), "email admin@example.com")
	}

	func testHashtagNotConvertedInMiddleOfWord() {
		// The lookbehind requires whitespace or start-of-string before the #.
		XCTAssertEqual(render("<Markdown>price is abc#def</Markdown>"), "price is abc#def")
	}

	func testMarkdownFormattingIsPreserved() {
		XCTAssertEqual(
			render("<Markdown>**bold** *italic* `code` [link](/forums/12)</Markdown>"),
			"**bold** *italic* `code` [link](/forums/12)"
		)
	}

	func testColonsInTextAreNotJocomoji() {
		// A colon pair that doesn't match a known jocomoji name is left alone.
		XCTAssertEqual(render("<Markdown>time is 12:30 and :unknown:</Markdown>"), "time is 12:30 and :unknown:")
	}
}