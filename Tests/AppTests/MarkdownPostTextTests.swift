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

	func testWrapperInsideFencedBlockIsPreserved() {
		// A fenced block documenting the tag keeps its <Markdown>/</Markdown> lines.
		XCTAssertEqual(
			strip("<Markdown>\n```\n<Markdown>\n</Markdown>\n```\n</Markdown>"),
			"\n```\n<Markdown>\n</Markdown>\n```\n"
		)
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

	func testJocomojiInsideLinkBecomeImages() {
		// Unlike mentions/hashtags, a jocomoji <img> is valid link text, so it still converts
		// inside an existing <a>.
		XCTAssertEqual(
			rewrite("<p><a href=\"https://x.com\">hi :pirate: there</a></p>"),
			"<p><a href=\"https://x.com\">hi <img src=\"/img/emoji/small/pirate.png\" width=18 height=18> there</a></p>"
		)
	}

	func testOverlappingJocomojiDontProduceBrokenHTML() {
		// Two jocomoji that share a colon (":die:ship:") overlap; only the earlier one is
		// applied so we don't emit a stray "img src=..." fragment.
		XCTAssertEqual(
			rewrite("<p>:die:ship:</p>"),
			"<p><img src=\"/img/emoji/small/die.png\" width=18 height=18>ship:</p>"
		)
		XCTAssertEqual(
			rewrite("<p>:arr:pirate:</p>"),
			"<p><img src=\"/img/emoji/small/arr.png\" width=18 height=18>pirate:</p>"
		)
	}

	// MARK: - addMentionLinkClasses tests

	private func addClasses(_ html: String) -> String {
		FormatPostTextTag.addMentionLinkClasses(html)
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
		// A single HTML string mixing mention and hashtag links: every link must be classified,
		// proving both the mention and hashtag passes run and replace all matches.
		let input = "<p><a href=\"/username/THO\">@THO</a> and <a href=\"/username/challfry\">@challfry</a> and <a href=\"/forumpost/search?hashtag=fun\">#fun</a></p>"
		let expected = "<p><a class=\"link-danger\" href=\"/username/THO\">@THO</a> and <a class=\"link-primary\" href=\"/username/challfry\">@challfry</a> and <a class=\"link-primary\" href=\"/forumpost/search?hashtag=fun\">#fun</a></p>"
		XCTAssertEqual(addClasses(input), expected)
	}

	func testUnrelatedLinksUntouched() {
		let input = "<a href=\"/forums/12\">Forum</a>"
		XCTAssertEqual(addClasses(input), input)
	}

	// MARK: - formatEscapedMarkdown (AST-level code escaping)

	private func render(_ markdown: String) -> String {
		FormatPostTextTag.formatEscapedMarkdown(markdown)
	}

	func testFencedCodeBlockContentIsEscaped() {
		// The <Markdown> sample inside a fenced block must be escaped so the browser renders it
		// as literal text instead of parsing it as a (hidden) element.
		XCTAssertEqual(
			render("```\n<Markdown>\n```"),
			"<pre><code>&lt;Markdown&gt;\n</code></pre>\n"
		)
	}

	func testInlineCodeContentIsEscaped() {
		// The same leak happens with inline code spans; escape those too.
		XCTAssertEqual(
			render("use `<Markdown>` here"),
			"<p>use <code>&lt;Markdown&gt;</code> here</p>\n"
		)
	}

	func testCodeOperatorsAndAmpersandAreEscaped() {
		// `<`, `>`, and `&` in a code sample all need escaping for correct rendering.
		XCTAssertEqual(
			render("```\nif (a < b && c > d) { }\n```"),
			"<pre><code>if (a &lt; b &amp;&amp; c &gt; d) { }\n</code></pre>\n"
		)
	}

	func testCodeRegionTagsArePreserved() {
		// Only the content between the code tags is escaped; the tags and language class stay intact.
		// Note the quotes stay live (`"x"`): the formatter escapes `&`/`<`/`>` in code but not quotes.
		// That's safe because the `<`/`>` are escaped (so this is text, not a live tag) and renders
		// identically in the browser to the `&quot;` form.
		XCTAssertEqual(
			render("```html\n<a href=\"x\">y</a>\n```"),
			"<pre><code class=\"language-html\">&lt;a href=\"x\"&gt;y&lt;/a&gt;\n</code></pre>\n"
		)
	}

	func testNonCodeRegionsAreUntouched() {
		// Content outside code regions (e.g. real links) is left alone.
		XCTAssertEqual(render("[Forum](/forums/12)"), "<p><a href=\"/forums/12\">Forum</a></p>\n")
	}

	func testFencedBlockContainingLiteralCodeTagsDoesNotCloseEarly() {
		// The reported regression: a sample that itself contains a literal <code>…</code> must be
		// escaped as a single unit. The inner </code> must NOT be treated as the real closing tag
		// (the old string-scan let it close the block early and re-open live markup after it).
		// The @mention inside the block also stays literal, because the block is now correctly
		// recognized as a single skip region.
		let input = "```\nthis is some <Markdown> <code>hi</code> and it mentions @admin\n```"
		let html = FormatPostTextTag.formatEscapedMarkdown(input)
		let styled = FormatPostTextTag.applyInlineRewrites(html)
		XCTAssertEqual(
			"<div class=\"markdown-body\">\(styled)</div>",
			"<div class=\"markdown-body\"><pre><code>this is some &lt;Markdown&gt; &lt;code&gt;hi&lt;/code&gt; and it mentions @admin\n</code></pre>\n</div>"
		)
	}

	// MARK: - Raw HTML is neutralized (only Markdown syntax may produce tags)

	/// Full render pipeline for a `<Markdown>` post: strip wrapper, parse+neutralize, apply forum
	/// rewrites, then neutralize dangerous URL schemes. Mirrors `FormatPostTextTag`'s Markdown branch exactly.
	private func renderFull(_ markdown: String) -> String {
		let cleaned = FormatPostTextTag.stripMarkdownWrapper(markdown)
		let html = FormatPostTextTag.formatEscapedMarkdown(cleaned)
		let styled = FormatPostTextTag.neutralizeDangerousSchemes(FormatPostTextTag.applyInlineRewrites(html))
		return "<div class=\"markdown-body\">\(styled)</div>"
	}

	func testScriptBlockIsNeutralized() {
		// A block-level <script> must render as inert literal text, never as a live tag.
		let out = renderFull("<Markdown>\n<script>alert('xss')</script>\n</Markdown>")
		XCTAssertTrue(out.contains("&lt;script&gt;"), "raw <script> should be shown as escaped text: \(out)")
		XCTAssertFalse(out.contains("<script"), "no live <script> tag may be rendered: \(out)")
	}

	func testInlineHTMLIsNeutralized() {
		// Inline raw HTML with an event handler must render as inert text, never as a live element.
		let out = renderFull("<Markdown>\nhi <img src=x onerror=alert(1)> there\n</Markdown>")
		XCTAssertTrue(out.contains("&lt;img"), "raw <img> should be shown as escaped text: \(out)")
		XCTAssertFalse(out.contains("<img"), "no live <img> tag may be rendered: \(out)")
	}

	func testSvgInlineIsNeutralized() {
		let out = renderFull("<Markdown>\nhi <svg onload=alert(1)> there\n</Markdown>")
		XCTAssertFalse(out.contains("<svg"), "no live <svg> tag may be rendered: \(out)")
	}

	func testRawHTMLEnterTagIsNotRendered() {
		// The exact case the requirement targets: a raw <a> typed by the user must not become a
		// live link — only a Markdown [text](url) link may produce an <a>.
		let rawA = renderFull("<Markdown>\n<a href=\"/evil\">click me</a>\n</Markdown>")
		XCTAssertFalse(rawA.contains("<a href=\"/evil\""), "a raw <a> must not render as a live link: \(rawA)")
		XCTAssertTrue(rawA.contains("&lt;a href=\"/evil\"&gt;"), "a raw <a> should show as escaped text: \(rawA)")
		let mdA = renderFull("<Markdown>\n[click me](/forums/12)\n</Markdown>")
		XCTAssertTrue(mdA.contains("<a href=\"/forums/12\""), "a Markdown link must still render as a live link: \(mdA)")
	}

	// MARK: - Sanitization (URLs & attributes on Markdown-generated tags)

	func testJavaScriptLinkHrefIsNoOpped() {
		let out = renderFull("<Markdown>\n[click](javascript:alert(1))\n</Markdown>")
		XCTAssertFalse(out.contains("alert(1)"), "the javascript: payload must be stripped: \(out)")
		XCTAssertTrue(out.contains("href=\"javascript:void(0)\""), "the href must be no-opped to javascript:void(0): \(out)")
	}

	func testJavaScriptImageSrcIsNoOpped() {
		let out = renderFull("<Markdown>\n![img](javascript:alert(1))\n</Markdown>")
		XCTAssertFalse(out.contains("alert(1)"), "the javascript: src payload must be stripped: \(out)")
		XCTAssertTrue(out.contains("src=\"javascript:void(0)\""), "the src must be no-opped to javascript:void(0): \(out)")
	}

	func testDataUriSrcIsNoOpped() {
		let out = renderFull("<Markdown>\n![img](data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==)\n</Markdown>")
		XCTAssertFalse(out.contains("data:"), "the data: URI must be stripped: \(out)")
		XCTAssertTrue(out.contains("src=\"javascript:void(0)\""), "the src must be no-opped to javascript:void(0): \(out)")
	}

	func testVbscriptLinkHrefIsNoOpped() {
		let out = renderFull("<Markdown>\n[click](vbscript:alert(1))\n</Markdown>")
		XCTAssertFalse(out.contains("vbscript:"), "the vbscript: href must be stripped: \(out)")
		XCTAssertTrue(out.contains("href=\"javascript:void(0)\""), "the href must be no-opped to javascript:void(0): \(out)")
	}

	func testFenceClassAttributeInjectionIsStripped() {
		// A malicious fence language tries to break out of the class="..." attribute and inject
		// a live onmouseover handler. Escaping the input up front turns the injected quotes into
		// &quot;, so swift-markdown keeps them inside the class value and no live attribute is created.
		let out = renderFull("<Markdown>\n```x\"onmouseover=\"alert(1)\nbody\n```\n</Markdown>")
		XCTAssertFalse(out.contains("\"onmouseover="), "no live onmouseover attribute may be created: \(out)")
		XCTAssertFalse(out.contains(" alert("), "no live alert(1) may be created: \(out)")
		XCTAssertTrue(out.contains("language-x"), "the fence must still render as a code block: \(out)")
	}

	// MARK: - Sanitization preserves legitimate forum markup

	func testCodeBlockLanguageClassIsPreserved() {
		let out = renderFull("<Markdown>\n```js\nlet a = 1;\n```\n</Markdown>")
		XCTAssertTrue(out.contains("language-js"), "code language class must be preserved: \(out)")
	}

	func testMentionLinkAndJocomojiArePreserved() {
		let out = renderFull("<Markdown>\n@staffuser and :arr:\n</Markdown>")
		XCTAssertTrue(out.contains("/username/staffuser"), "mention link must be preserved: \(out)")
		XCTAssertTrue(out.contains("/img/emoji/small/arr.png"), "jocomoji image must be preserved: \(out)")
	}

	func testRelativeAndAbsoluteLinksArePreserved() {
		let out = renderFull("<Markdown>\n[forum](/forums/12) and [ext](https://example.com)\n</Markdown>")
		XCTAssertTrue(out.contains("/forums/12"), "relative link must be preserved: \(out)")
		XCTAssertTrue(out.contains("https://example.com"), "absolute link must be preserved: \(out)")
	}

	func testStrikethroughAndThematicBreakArePreserved() {
		// swift-markdown emits <del> for ~~strikethrough~~ and <hr> for a --- rule; both must
		// survive the pipeline so legitimate Markdown formatting isn't silently dropped.
		let out = renderFull("<Markdown>\n~~gone~~\n\n---\n\nafter\n</Markdown>")
		XCTAssertTrue(out.contains("del"), "strikethrough <del> must be preserved: \(out)")
		XCTAssertTrue(out.contains("<hr"), "thematic break <hr> must be preserved: \(out)")
	}
}