import XCTVapor
@testable import swiftarr

/// Regression tests for the plain-text auto-link pass (`FormatPostTextTag.processUrlMatches`).
///
/// The plain-text path first runs `htmlEscaped()`, so any HTML a user *typed* arrives as escaped
/// entities (`&lt;a href=&quot;…&quot;&gt;…&lt;/a&gt;`). The URL matcher must link only the bare, untagged URLs and
/// leave the escaped (thereby inert) typed HTML byte-for-byte intact. Previously the matcher ran
/// over the whole string and could reach into a typed tag's `href="…"` (or an `<img>`'s `src="…"`),
/// swallowing the trailing `&quot;&gt;…` into one mangled double-nested link with a stray `;`.
final class PlainTextUrlLinkTests: XCTestCase {

	private func link(_ string: String) -> String {
		var s = string
		FormatPostTextTag.processUrlMatches(string: &s)
		return s
	}

	// MARK: - Typed (escaped) HTML stays inert

	func testTypedHTMLWithURLsRendersInertAndUnchanged() {
		// The reported regression: typed <img> (canonical-host src) and typed <a> (href with a path)
		// must render as inert literal text, byte-for-byte unchanged. No live link is created from the
		// URLs hidden inside the tags, nothing is mangled, and no stray ';' is introduced.
		let input =
			"&lt;img src=&quot;https://cdn.joco.hollandamerica.com/img/map.png&quot; width=&quot;300&quot; alt=&quot;Twitarr Map&quot;&gt; "
			+ "&lt;a href=&quot;https://www.google.com/maps/place/LA&quot;&gt;world&lt;/a&gt;"
		let out = link(input)
		XCTAssertEqual(out, input)
	}

	func testTypedLinkWithCanonicalHostSrcIsNotShortened() {
		// joco.hollandamerica.com is a canonical hostname, so a *bare* occurrence would be rewritten
		// to a wiki-style linkbox. Inside a typed tag it must stay verbatim (the host stays canonical).
		let input = "&lt;a href=&quot;https://joco.hollandamerica.com/lfg/joined&quot;&gt;joined&lt;/a&gt;"
		let out = link(input)
		XCTAssertEqual(out, input)
		XCTAssertTrue(out.contains("joco.hollandamerica.com"), "canonical host inside typed tag must stay: \(out)")
		XCTAssertFalse(out.contains("[Joined LFGs Link]"), "typed link must not be relabeled: \(out)")
	}

	// MARK: - Bare URLs are still auto-linked

	func testBareURLStillLinkedWhenTypedHTMLPresent() {
		// A typed <a> next to a bare URL: the typed tag stays inert and escaped, while the bare URL
		// (a non-canonical host) is auto-linked to a live <a> with the full URL as its text.
		let input =
			"&lt;a href=&quot;https://www.google.com/maps/place/LA&quot;&gt;world&lt;/a&gt; plus https://example.com/page."
		let out = link(input)
		XCTAssertTrue(
			out.contains("&lt;a href=&quot;https://www.google.com/maps/place/LA&quot;&gt;world&lt;/a&gt;"),
			"typed <a> must stay inert/escaped, not mangled: \(out)"
		)
		XCTAssertTrue(
			out.contains("<a href=\"https://example.com/page\">https://example.com/page</a>."),
			"the bare URL must be auto-linked: \(out)"
		)
	}

	func testBareCanonicalURLIsShortenedAndInertTagUntouched() {
		// A bare canonical URL on a known site path is rewritten to its wiki-style linkbox, while the
		// adjacent typed <a> is left verbatim. This is the two halves of the plain-text pass working
		// together rather than the matcher collapsing them into one mangled match.
		let input = "&lt;a href=&quot;https://example.com/x&quot;&gt;inert&lt;/a&gt; see https://twitarr.com/forums/12."
		let out = link(input)
		XCTAssertTrue(out.contains("&lt;a href=&quot;https://example.com/x&quot;&gt;inert&lt;/a&gt;"), "typed <a> must stay inert: \(out)")
		XCTAssertFalse(out.contains("<a href=\"https://twitarr.com/forums/12\">https://twitarr.com/forums/12</a>"), "canonical bare URL must be shortened, not emitted as full URL: \(out)")
		XCTAssertTrue(out.contains("href=\"/forums/12\""), "canonical bare URL should be origin-relative: \(out)")
	}

	func testTrailingPeriodAfterBareURLPreserved() {
		// The trailing-period chomp must still work now that masked regions are restored afterwards:
		// the '.' that ended a sentence is kept as visible text outside the link.
		let out = link("check https://example.com/page.")
		XCTAssertTrue(out.contains("<a href=\"https://example.com/page\">https://example.com/page</a>."), "expected trailing '.' preserved: \(out)")
	}

	func testMultipleBareURLsAndOneTypedTag() {
		// Several bare URLs plus one typed tag: every bare URL is linked, the typed tag stays inert.
		let input =
			"&lt;a href=&quot;https://example.com/a&quot;&gt;typed&lt;/a&gt; "
			+ "https://one.com/1 and https://two.com/2."
		let out = link(input)
		XCTAssertTrue(out.contains("&lt;a href=&quot;https://example.com/a&quot;&gt;typed&lt;/a&gt;"), "typed <a> must stay inert: \(out)")
		XCTAssertTrue(out.contains("<a href=\"https://one.com/1\">https://one.com/1</a>"), "first bare URL must link: \(out)")
		XCTAssertTrue(out.contains("<a href=\"https://two.com/2\">https://two.com/2</a>."), "second bare URL must link: \(out)")
	}

	func testBareURLImmediatelyAdjacentToTypedTag() {
		// No space between the bare URL and the typed tag: the URL must stop exactly where the typed
		// (escaped) tag begins, and the tag must stay inert. This is the adjacency the URL body class
		// [^\s()<>{}\[\]]+ would otherwise swallow past a weak placeholder into one mangled match.
		let input = "see https://example.com/page&lt;img src=&quot;https://cdn.joco.hollandamerica.com/x.png&quot; width=&quot;24&quot;&gt;"
		let out = link(input)
		XCTAssertTrue(out.contains("<a href=\"https://example.com/page\">https://example.com/page</a>"), "bare URL must link and stop at the typed tag: \(out)")
		XCTAssertTrue(out.contains("&lt;img src=&quot;https://cdn.joco.hollandamerica.com/x.png&quot; width=&quot;24&quot;&gt;"), "typed <img> must stay inert: \(out)")
		XCTAssertFalse(out.contains("page\u{0001}"), "no control-char token may leak into the link: \(out)")
		XCTAssertFalse(out.contains("[MASK"), "no un-restored placeholder may leak: \(out)")
	}
}
