import XCTVapor
@testable import swiftarr

class CanonicalLinkTextTests: XCTestCase {

	private func linkText(for url: String) -> String? {
		FormatPostTextTag.canonicalLinkText(pathComponents: URL(string: url)!.pathComponents)
	}

	// MARK: - LFG routes (current site paths)

	func testLFGRoot() {
		XCTAssertEqual(linkText(for: "https://twitarr.com/lfg"), "[LFGs Link]")
		XCTAssertEqual(linkText(for: "https://twitarr.com/lfg/"), "[LFGs Link]")
	}

	func testLFGJoined() {
		XCTAssertEqual(linkText(for: "https://twitarr.com/lfg/joined"), "[Joined LFGs Link]")
	}

	func testLFGOwned() {
		XCTAssertEqual(linkText(for: "https://twitarr.com/lfg/owned"), "[Your LFGs Link]")
	}

	func testLFGFAQ() {
		XCTAssertEqual(linkText(for: "https://twitarr.com/lfg/faq"), "[LFG FAQ Link]")
	}

	func testLFGSpecific() {
		XCTAssertEqual(
			linkText(for: "https://twitarr.com/lfg/ADDBA5D9-1154-4033-88AE-07B12F3AE162"),
			"[LFG Link]"
		)
	}

	// MARK: - Legacy /fez paths still posted in older content

	func testLegacyFezPathsStillLabeledAsLFG() {
		XCTAssertEqual(linkText(for: "https://twitarr.com/fez"), "[LFGs Link]")
		XCTAssertEqual(linkText(for: "https://twitarr.com/fez/joined"), "[Joined LFGs Link]")
		XCTAssertEqual(linkText(for: "https://twitarr.com/fez/owned"), "[Your LFGs Link]")
		XCTAssertEqual(linkText(for: "https://twitarr.com/fez/faq"), "[LFG FAQ Link]")
		XCTAssertEqual(
			linkText(for: "https://twitarr.com/fez/ADDBA5D9-1154-4033-88AE-07B12F3AE162"),
			"[LFG Link]"
		)
	}

	// MARK: - Other canonical paths still rewrite

	func testTweetsPath() {
		XCTAssertEqual(linkText(for: "https://twitarr.com/tweets"), "[Twitarr Tweet Link]")
	}

	func testUnrecognizedSitePath() {
		XCTAssertEqual(linkText(for: "https://twitarr.com/photostream"), "[Twitarr Link]")
	}

	func testPathTooShortIsNotRewritten() {
		XCTAssertNil(FormatPostTextTag.canonicalLinkText(pathComponents: ["/"]))
		XCTAssertNil(FormatPostTextTag.canonicalLinkText(pathComponents: []))
	}
}
