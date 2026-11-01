import XCTVapor
@testable import swiftarr

class MarkdownPostTextTests: XCTestCase {

	// MARK: - stripMarkdownWrapper

	private func strip(_ input: String) -> String {
		FormatPostTextTag.stripMarkdownWrapper(input)
	}

	func testStripsWrapperTags() {
		XCTAssertEqual(strip("<Markdown>hello</Markdown>"), "hello")
		XCTAssertEqual(strip("<Markdown>\n\n**bold**\n\n</Markdown>"), "\n\n**bold**\n\n")
	}

	// MARK: - applyInlineRewrites

	private func rewrite(_ html: String) -> String {
		FormatPostTextTag.applyInlineRewrites(html)
	}

	func testJocomojiBecomeImages() {
		XCTAssertEqual(
			rewrite("<p>:arr: and :back-deck-juice:</p>"),
			"<p><img src=\"/img/emoji/small/arr.png\" width=18 height=18> and <img src=\"/img/emoji/small/back-deck-juice.png\" width=18 height=18></p>"
		)
	}

	func testMentionsBecomeLinks() {
		XCTAssertEqual(
			rewrite("<p>hello @admin and @challfry</p>"),
			"<p>hello <a class=\"link-danger\" href=\"/username/admin\">@admin</a> and <a class=\"link-primary\" href=\"/username/challfry\">@challfry</a></p>"
		)
	}

	func testHashtagsBecomeLinks() {
		XCTAssertEqual(
			rewrite("<p>this is #arr time</p>"),
			"<p>this is <a class=\"link-primary\" href=\"/forumpost/search?hashtag=arr\">#arr</a> time</p>"
		)
	}

	func testMentionNotConvertedInMiddleOfWord() {
		// The lookbehind requires whitespace or start-of-string before the @.
		XCTAssertEqual(rewrite("<p>email admin@example.com</p>"), "<p>email admin@example.com</p>")
	}

	func testHashtagNotConvertedInMiddleOfWord() {
		// The lookbehind requires whitespace or start-of-string before the #.
		XCTAssertEqual(rewrite("<p>price is abc#def</p>"), "<p>price is abc#def</p>")
	}

	func testColonsInTextAreNotJocomoji() {
		// A colon pair that doesn't match a known jocomoji name is left alone.
		XCTAssertEqual(rewrite("<p>time is 12:30 and :unknown:</p>"), "<p>time is 12:30 and :unknown:</p>")
	}

	func testExistingLinksArePreserved() {
		let input = "<p><a href=\"/forums/12\">Forum</a></p>"
		XCTAssertEqual(rewrite(input), input)
	}

	// MARK: - code / pre / a regions are skipped

	func testInlineCodeIsSkipped() {
		let input = "<p>use <code>code :pirate:</code> and @admin</p>"
		XCTAssertEqual(
			rewrite(input),
			"<p>use <code>code :pirate:</code> and <a class=\"link-danger\" href=\"/username/admin\">@admin</a></p>"
		)
	}

	func testFencedCodeBlockIsSkipped() {
		let input = "<pre><code>@admin #tag :pirate:\n</code></pre>"
		XCTAssertEqual(rewrite(input), input)
	}

	func testMentionInsideExistingLinkIsSkipped() {
		// An @mention that is already link text is not re-rewritten.
		let input = "<p><a href=\"/username/admin\">@admin</a></p>"
		XCTAssertEqual(rewrite(input), input)
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