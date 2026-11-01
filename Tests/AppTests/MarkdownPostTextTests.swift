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

	// MARK: - addMentionLinkClasses tests

	private func addClasses(_ html: String) -> String {
		FormatPostTextTag.addMentionLinkClasses(html)
	}

	func testStaffMentionGetsLinkDanger() {
		let input = "<a href=\"/username/admin\">@admin</a>"
		XCTAssertEqual(addClasses(input), "<a class=\"link-danger\" href=\"/username/admin\">@admin</a>")
	}

	func testStaffMentionCaseInsensitive() {
		// Even if the URL has different casing, it should still be detected as staff.
		let input = "<a href=\"/username/THO\">@THO</a>"
		XCTAssertEqual(addClasses(input), "<a class=\"link-danger\" href=\"/username/THO\">@THO</a>")

		let input2 = "<a href=\"/username/TwitarrTeam\">@TwitarrTeam</a>"
		XCTAssertEqual(addClasses(input2), "<a class=\"link-danger\" href=\"/username/TwitarrTeam\">@TwitarrTeam</a>")

		let input3 = "<a href=\"/username/moderator\">@moderator</a>"
		XCTAssertEqual(addClasses(input3), "<a class=\"link-danger\" href=\"/username/moderator\">@moderator</a>")
	}

	func testRegularMentionGetsLinkPrimary() {
		let input = "<a href=\"/username/challfry\">@challfry</a>"
		XCTAssertEqual(addClasses(input), "<a class=\"link-primary\" href=\"/username/challfry\">@challfry</a>")
	}

	func testHashtagGetsLinkPrimary() {
		let input = "<a href=\"/forumpost/search?hashtag=arr\">#arr</a>"
		XCTAssertEqual(addClasses(input), "<a class=\"link-primary\" href=\"/forumpost/search?hashtag=arr\">#arr</a>")
	}

	func testMultipleLinksInOneHTML() {
		let input = "<p><a href=\"/username/THO\">@THO</a> and <a href=\"/username/challfry\">@challfry</a> and <a href=\"/forumpost/search?hashtag=fun\">#fun</a></p>"
		let expected = "<p><a class=\"link-danger\" href=\"/username/THO\">@THO</a> and <a class=\"link-primary\" href=\"/username/challfry\">@challfry</a> and <a class=\"link-primary\" href=\"/forumpost/search?hashtag=fun\">#fun</a></p>"
		XCTAssertEqual(addClasses(input), expected)
	}

	func testUnrelatedLinksUntouched() {
		let input = "<a href=\"/forums/12\">Forum</a>"
		XCTAssertEqual(addClasses(input), input)
	}
}