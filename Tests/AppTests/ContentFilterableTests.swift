import XCTVapor
@testable import swiftarr

class ContentFilterableTests: XCTestCase {

	// Minimal ContentFilterable conformance for testing.
	private struct TestContent: ContentFilterable {
		let strings: [String]
		init(_ strings: String...) { self.strings = strings }
		func contentTextStrings() -> [String] { strings }
	}

	// MARK: - buildCleanWordsArray

	func testBuildCleanWordsArray_LowercasesAndStripsPunctuation() {
		let result = TestContent.buildCleanWordsArray("Hello, World!")
		XCTAssertEqual(result, ["hello", "world"])
	}

	func testBuildCleanWordsArray_DropsDigitsAndSymbols() {
		// Filter keeps only letters and whitespace, so "abc123 xyz" becomes "abc xyz".
		let result = TestContent.buildCleanWordsArray("abc123 xyz")
		XCTAssertEqual(result, ["abc", "xyz"])
	}

	func testBuildCleanWordsArray_Deduplicates() {
		let result = TestContent.buildCleanWordsArray("the the THE")
		XCTAssertEqual(result, ["the"])
	}

	func testBuildCleanWordsArray_EmptyString_ReturnsEmptySet() {
		XCTAssertEqual(TestContent.buildCleanWordsArray(""), [])
	}

	// MARK: - getMentionsSet

	func testGetMentionsSet_FindsSingleMention() {
		XCTAssertEqual(TestContent.getMentionsSet(for: "hi @skyler"), ["skyler"])
	}

	func testGetMentionsSet_FindsMultipleMentions() {
		XCTAssertEqual(
			TestContent.getMentionsSet(for: "@heidi likes @sam"),
			["heidi", "sam"]
		)
	}

	func testGetMentionsSet_ExcludesTrailingPunctuation() {
		// Period is a valid username separator inside, but trailing period at the end
		// of a sentence should not be part of the captured username.
		XCTAssertEqual(TestContent.getMentionsSet(for: "ping @sam."), ["sam"])
	}

	func testGetMentionsSet_AllowsSeparatorInsideUsername() {
		XCTAssertEqual(TestContent.getMentionsSet(for: "@sky.ler is here"), ["sky.ler"])
	}

	func testGetMentionsSet_EmptyOnNoAtSign() {
		XCTAssertEqual(TestContent.getMentionsSet(for: "no mentions here"), [])
	}

	func testGetMentionsSet_RequiresWhitespaceOrStartBeforeAt() {
		// "foo@bar" should NOT yield 'bar' — the @ must be preceded by start-of-string or whitespace.
		XCTAssertEqual(TestContent.getMentionsSet(for: "email foo@bar.com"), [])
	}

	// MARK: - getHashtags

	func testGetHashtags_FindsSimpleHashtag() {
		XCTAssertEqual(TestContent("loving #cribbage today").getHashtags(), ["cribbage"])
	}

	func testGetHashtags_RequiresAtLeastTwoCharsAfterHash() {
		// "#a" is too short (total of 2 chars including #); "#ab" is exactly the minimum.
		XCTAssertEqual(TestContent("#a #ab").getHashtags(), ["ab"])
	}

	func testGetHashtags_DropsTrailingPunctuation() {
		XCTAssertEqual(TestContent("#cribbage!").getHashtags(), ["cribbage"])
	}

	func testGetHashtags_IgnoresEmbeddedHash() {
		// '#' must be at the start of a whitespace-delimited word.
		XCTAssertEqual(TestContent("not a #hashtag is foo#bar").getHashtags(), ["hashtag"])
	}

	func testGetHashtags_RejectsHashtagOver50Chars() {
		let long = "#" + String(repeating: "a", count: 50) // total 51 chars → over the 50-char cap
		XCTAssertEqual(TestContent(long).getHashtags(), [])
	}

	// MARK: - containsMutewords

	func testContainsMutewords_TrueWhenWordPresent() {
		let content = TestContent("watch out for spoilers ahead")
		XCTAssertTrue(content.containsMutewords(using: ["spoiler"]))
	}

	func testContainsMutewords_CaseInsensitive() {
		let content = TestContent("Watch out for SPOILERS")
		XCTAssertTrue(content.containsMutewords(using: ["spoiler"]))
	}

	func testContainsMutewords_FalseWhenNoMatch() {
		let content = TestContent("just a normal post")
		XCTAssertFalse(content.containsMutewords(using: ["spoiler", "ending"]))
	}

	func testContainsMutewords_EmptyMutewords_ReturnsFalse() {
		XCTAssertFalse(TestContent("anything").containsMutewords(using: []))
	}

	// MARK: - filterOutStrings

	func testFilterOutStrings_NilWords_ReturnsSelf() {
		let content = TestContent("anything goes here")
		XCTAssertNotNil(content.filterOutStrings(using: nil))
	}

	func testFilterOutStrings_NoMatch_ReturnsSelf() {
		let content = TestContent("anything goes here")
		XCTAssertNotNil(content.filterOutStrings(using: ["spoiler"]))
	}

	func testFilterOutStrings_HasMatch_ReturnsNil() {
		let content = TestContent("contains a spoiler")
		XCTAssertNil(content.filterOutStrings(using: ["spoiler"]))
	}
}
