//
//  CustomLeafTags.swift
//  App
//
//  Created by Chall Fry on 4/21/21.
//

import Foundation
import Leaf
import Markdown
import Vapor

/// This tag should output-sanitize all string values in self, replacing existing values.
/// For each string, it should encode the chars &<>"'/ into their HTML entities, preventing them from being interpreted as HTML
/// commands when Leaf inserts them into HTML Element contexts. For inserting into other contexts, other sanitizing should be done.
/// See https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html
///
/// Usage: #elem(String) -> String
//struct ElementSanitizerTag: LeafTag {
//	static func sanitize(_ str: String) -> String {
//		var string = str
//		// This isn't ~optimized~, but I think it optimizes for the case where no changes need to be made to the string.
//		for ch in string.indices.reversed() {
//			switch string[ch] {
//			case "&": string.replaceSubrange(ch..<string.index(after:ch), with: "&amp;")
//			case "<": string.replaceSubrange(ch..<string.index(after:ch), with: "&lt;")
//			case ">": string.replaceSubrange(ch..<string.index(after:ch), with: "&gt;")
//			case "'": string.replaceSubrange(ch..<string.index(after:ch), with: "&#x27;")
//			case "\"": string.replaceSubrange(ch..<string.index(after:ch), with: "&quot;")
//			case "/": string.replaceSubrange(ch..<string.index(after:ch), with: "&#x2F;")
//			default: continue
//			}
//		}
//
//		return string
//	}
//
//	func render(_ ctx: LeafContext) throws -> LeafData {
//		try ctx.requireParameterCount(1)
//		guard let string = ctx.parameters[0].string else {
//			return LeafData.string("")
//		}
//		return LeafData.string(ElementSanitizerTag.sanitize(string))
//	}
//}

// MARK: - Tags for Styling Posts, Announcements, Daily Themes

/// Runs the element sanitizer on the given string, and then converts Jocomoji (specific string tags with the form :tag:)
/// into inline images. Generally, use this tag for user text that isn't posts.
///
/// Usage: #addJocomoji(String) -> String
struct AddJocomojiTag: UnsafeUnescapedLeafTag {
	static let jocomoji = [
		"arr", "back-deck-juice", "buffet", "die-ship", "die", "hottub", "joco", "pirate", "ship-front",
		"ship", "tropical-drink", "wangwang", "zombie",
	]

	/// The inline `<img>` tag used to render a jocomoji by name. Shared by the standalone
	/// `addJocomoji` path and `FormatPostTextTag.rewriteInline` so the markup stays in one place.
	static func imgTag(for emojiTag: String) -> String {
		"<img src=\"/img/emoji/small/\(emojiTag).png\" width=18 height=18>"
	}

	static func process(_ str: String) -> String {
		var string = str
		for emojiTag in AddJocomojiTag.jocomoji {
			string = string.replacingOccurrences(
				of: ":\(emojiTag):",
				with: AddJocomojiTag.imgTag(for: emojiTag)
			)
		}
		return string
	}

	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard var string = ctx.parameters[0].string else {
			return LeafData.string("")
		}

		// Sanitize first to remove any existing tags. Also ensure the inline <img> tags we're about to add don't get nuked
		string = AddJocomojiTag.process(string.htmlEscaped())

		// Also convert newlines to HTML breaks.
		string = string.replacingOccurrences(of: "\r", with: "<br>")

		return LeafData.string(string)
	}
}

/// Runs the element sanitizer on the given string, converts Jocomoji (specific string tags with the form :tag:)
/// into inline images, and then converts substrings of the forum "@username"  and "#hashtag" into links.
///
/// Usage: #formatTwarrtText(String) -> String
/// Usage: #formatPostText(String) -> String
/// Usage: #formatFezText(String) -> String
/// Usage: #formatSeamailText(String) -> String
struct FormatPostTextTag: UnsafeUnescapedLeafTag {
	/// Staff mentions render with `link-danger`. Sourced from `PrivilegedUser` so the
	/// list of privileged usernames isn't duplicated in this file.
	static let staffUsernames: Set<String> = Set(PrivilegedUser.allCases.map { $0.queryParam })

	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard var string = ctx.parameters[0].string else {
			return LeafData.string("")
		}

		// Posts starting with the <Markdown> marker are rendered as Markdown via swift-markdown's
		// cmark parser. The parser emits fenced and inline code content verbatim (it does not
		// HTML-escape it), so a sample like `<Markdown>` in a code fence would otherwise leak a
		// live tag into the page that the browser mis-parses or hides — so escape the code regions
		// first. Then rewrite the forum's inline syntax (jocomoji, mentions, hashtags) into
		// <img>/<a> HTML. Code and preformatted blocks are left untouched; inside existing links
		// only jocomoji convert (an <img> is valid link text) while mentions/hashtags are skipped
		// (nested links are invalid HTML). This is safe because cmark has already run, so the
		// emitted tags are plain data to the browser rather than markdown to be re-parsed.
		// Bare URLs are auto-linked by cmark's autolink extension.
		if string.hasPrefix("<Markdown>") {
			let cleaned = Self.stripMarkdownWrapper(string)
			let html = Self.formatEscapedMarkdown(cleaned)
			let styled = Self.neutralizeDangerousSchemes(Self.applyInlineRewrites(html))
			return LeafData.string("<div class=\"markdown-body\">\(styled)</div>")
		}

		// Sanitize first so any user-supplied raw HTML is neutralized (and the <img>/<a> tags we add
		// next aren't escaped away). Then rewrite the forum's inline syntax (jocomoji, @mentions,
		// #hashtags) into <img>/<a> HTML. We reuse the same rewriteInline the Markdown path uses, so
		// both stay in lockstep: same regexes, same link markup, same case-insensitive staff coloring.
		string = Self.rewriteInline(string.htmlEscaped())

		string = string.replacingOccurrences(of: "\r\n", with: "\n")
		string = string.replacingOccurrences(of: "\r", with: "\n")

		// Also convert newlines to HTML breaks. Do this before link conversion due to a dumb bug with the regex parser
		// where \r\n sequences that appear before the regex match have their reported match length reduced.
		//
		// Note the replacement of "\r\n" and "\r" above. Dunno if that matters with the Markdown parser.
		//
		// I can't begin to comprehend the number of hours I wasted figuring out that Swift's print()
		// basically does a buffer overflow with newlines and prints the same content to the same line in-place
		// on the terminal.
		string = string.replacingOccurrences(of: "\n", with: "<br>")

		// Links in posts should be automatically clickable. Similarly, we desire to shorten Twitarr
		// specific links. Maybe someday we could parse them and give some linktext?
		// e.g. "http://192.168.0.19:8081/lfg/ADDBA5D9-1154-4033-88AE-07B12F3AE162"
		// could have linktext "[An LFG Link]" or somesuch.

		// Since we have multiple potential Twitarr hostnames (twitarr.com, joco.hollandamerica.com)
		// and to aid in development (localhost, etc) we can be configured with a set of canonical hostnames
		// to replace to whatever the origin of the users request came from. For example, if you are
		// browsing at https://twitarr.com a Twitarr link should not take you to http://joco.hollandamerica.com.
		// While it's not the end of the world it represents a poor experience for the user.

		// Find all matches in the entire text string (range 0 to end), then substitute the matches.
		// processUrlMatches masks neutralized (&lt;…&gt;) HTML regions first so the matcher can't
		// reach into a typed tag (e.g. its href="…") and swallow it into a mangled live link.
		Self.processUrlMatches(string: &string)

		return LeafData.string(string)
	}

	/// Strips the `<Markdown>` wrapper tags that mark a post as Markdown. Only the leading
	/// `<Markdown>` and the trailing `</Markdown>` are removed (they're our internal marker, not
	/// part of the body); any other occurrences—e.g. a code span or fenced block documenting the
	/// tag itself—are left alone so help text about the tag still renders.
	static func stripMarkdownWrapper(_ input: String) -> String {
		var markdown = input
		if markdown.hasPrefix("<Markdown>") {
			markdown = String(markdown.dropFirst("<Markdown>".count))
		}
		if markdown.hasSuffix("</Markdown>") {
			markdown = String(markdown.dropLast("</Markdown>".count))
		}
		return markdown
	}

	/// Renders Markdown to HTML.
	///
	/// The pinned swift-markdown (commit ea1d88be) `HTMLFormatter` escapes text, code-block, and
	/// inline-code content itself, so typed `<`/`>`/`&` are neutralized without double-escaping.
	/// It does, however, emit two things verbatim: a `HTMLBlock`/`InlineHTML` node (a raw `<script>`,
	/// `<svg>`, `<img ...>`, or `<a href="...">` typed by the author) as live markup, and a fenced
	/// block's `class="language-…"` attribute unescaped (a malicious info string can break out of it).
	/// We neutralize both in the AST *before* formatting: raw HTML nodes are rewritten to inert text
	/// (the formatter then escapes them to `&lt;…&gt;`), and code-block languages are restricted to a
	/// safe character set. Markdown link/image `href`/`src` are the one residual vector the caller's
	/// `neutralizeDangerousSchemes` pass still has to handle.
	static func formatEscapedMarkdown(_ markdown: String) -> String {
		let document = Markdown.Document(parsing: markdown)
		var rewriter = RawHTMLNeutralizer()
		let safeDocument = rewriter.visit(document) as? Document ?? document
		return HTMLFormatter.format(safeDocument)
	}

	/// Rewrites the AST so no raw markup can reach the formatter as a live tag: `HTMLBlock` and
	/// `InlineHTML` nodes become inert text (escaped by `HTMLFormatter.visitText`), and fenced
	/// code-block languages are restricted to `[A-Za-z0-9_+-]` so they cannot break out of the
	/// `class="language-…"` attribute. Everything else is left untouched.
	private struct RawHTMLNeutralizer: MarkupRewriter {
		func visitHTMLBlock(_ html: HTMLBlock) -> Markup? {
			return Text(html.rawHTML)
		}

		func visitInlineHTML(_ inlineHTML: InlineHTML) -> Markup? {
			return Text(inlineHTML.rawHTML)
		}

		func visitCodeBlock(_ codeBlock: CodeBlock) -> Markup? {
			guard let language = codeBlock.language else {
				return codeBlock
			}
			let safe = String(language.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" || $0 == "+" })
			guard safe != language else {
				return codeBlock
			}
			return CodeBlock(language: safe.isEmpty ? nil : safe, codeBlock.code)
		}
	}

	/// Neutralizes `javascript:` / `data:` / `vbscript:` URL schemes in `href`/`src` attributes so
	/// a Markdown link like `[click](javascript:alert(1))` cannot trigger click-based script
	/// execution. This is the one residual vector left after the up-front input escape: raw HTML
	/// is already inert, but Markdown link/image *syntax* can still emit a live dangerous `href`.
	/// The match is case-insensitive and tolerates the embedded whitespace/newlines obfuscators
	/// rely on; it replaces the whole scheme-prefixed URL with an inert `about:blank`.
	static func neutralizeDangerousSchemes(_ html: String) -> String {
		let pattern = "(?i)\\b(href|src)\\s*=\\s*[\"']\\s*(?:javascript|data|vbscript)\\s*:?[^\"']*"
		guard let re = try? NSRegularExpression(pattern: pattern) else {
			return html
		}
		let range = NSRange(html.startIndex..., in: html)
		return re.stringByReplacingMatches(in: html, range: range, withTemplate: "$1=\"about:blank\"")
	}

	/// Rewrites the forum's inline syntax (jocomoji, mentions, hashtags) into `<img>`/`<a>` HTML
	/// in cmark's output, leaving code blocks and preformatted blocks untouched. Mentions and
	/// hashtags are also left alone inside existing links (nested links are invalid HTML), but
	/// jocomoji still convert there because an inline image is valid link text.
	///
	/// Running this *after* cmark is what lets us skip code: at this point the text between tags
	/// is plain prose, and `<code>`, `<pre>`, and `<a>` delimit the regions we must not touch.
	/// The emitted tags are safe to insert because cmark has already run.
	static func applyInlineRewrites(_ html: String) -> String {
		let skipTags: Set<String> = ["code", "pre", "a"]
		let tagRegex = try! NSRegularExpression(pattern: "<[^>]*>")
		let matches = tagRegex.matches(in: html, options: [], range: NSRange(html.startIndex..<html.endIndex, in: html))

		var result = ""
		var skipStack: [String] = []
		var lastEnd = html.startIndex

		for match in matches {
			guard let tagRange = Range(match.range(at: 0), in: html) else { continue }

			// Text before this tag: never rewrite inside code/pre. Inside an <a> we still convert
			// jocomoji (an <img> is valid link text) but leave mentions/hashtags alone (nested
			// links are invalid HTML).
			let textChunk = String(html[lastEnd..<tagRange.lowerBound])
			result += Self.rewriteChunk(textChunk, skipStack: skipStack)

			// Track whether this tag opens or closes a region we skip.
			let tag = String(html[tagRange])
			var body = tag
			var closing = false
			if body.hasPrefix("</") {
				closing = true
				body.removeFirst(2)
			} else {
				body.removeFirst()
			}
			let name = String(body.prefix { !$0.isWhitespace && $0 != ">" }).lowercased()
			if skipTags.contains(name) {
				if closing {
					if let top = skipStack.last, top == name {
						skipStack.removeLast()
					}
				} else {
					skipStack.append(name)
				}
			}
			result += tag
			lastEnd = tagRange.upperBound
		}

		// Trailing text after the last tag.
		if lastEnd < html.endIndex {
			let textChunk = String(html[lastEnd...])
			result += Self.rewriteChunk(textChunk, skipStack: skipStack)
		}
		return result
	}

	/// Rewrites a prose chunk based on which skip region it's currently inside (from the
	/// tag stack). Code/pre suppress all rewrites; a link suppresses mentions/hashtags but
	/// still converts jocomoji. `skipStack` holds the open skip tags (code/pre/a).
	///
	static func rewriteChunk(_ textChunk: String, skipStack: [String]) -> String {
		if skipStack.contains("code") || skipStack.contains("pre") {
			return textChunk
		}
		return Self.rewriteInline(textChunk, insideLink: skipStack.contains("a"))
	}

	/// Applies the jocomoji/mention/hashtag rewrites to a single chunk of prose (text between tags).
	/// Collects every match first, then substitutes right-to-left so the ranges stay valid.
	///
	/// When `insideLink` is true (the chunk is the text of an existing `<a>`), mentions and
	/// hashtags are skipped because nesting links is invalid HTML; jocomoji still convert,
	/// since an inline image is valid link text.
	static func rewriteInline(_ text: String, insideLink: Bool = false) -> String {
		struct Rewrite {
			let range: NSRange
			let replacement: String
		}

		var rewrites: [Rewrite] = []
		let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)

		// Jocomoji: :tag: -> <img src="/img/emoji/small/tag.png" ...>
		for emojiTag in AddJocomojiTag.jocomoji {
			let literal = ":\(emojiTag):"
			var searchFrom = text.startIndex
			while let range = text.range(of: literal, range: searchFrom..<text.endIndex) {
				rewrites.append(Rewrite(
					range: NSRange(range, in: text),
					replacement: AddJocomojiTag.imgTag(for: emojiTag)
				))
				// Use upperBound (not index(after:)) so a match at the very end of the chunk
				// doesn't call index(after: endIndex), which traps; the next empty search returns nil.
				searchFrom = range.upperBound
			}
		}

		// Mentions and hashtags are skipped inside an existing link (nested links are invalid
		// HTML), so only run them when we're not inside an <a>.
		if !insideLink {
			// Mentions: @username -> <a class="..." href="/username/username">@username</a>
			let staffUsernames = Self.staffUsernames
			let mentionRegex = try! NSRegularExpression(pattern: "(?<!\\S)(@[A-Za-z0-9]+(?:[-.+_][A-Za-z0-9]+)*)")
			for match in mentionRegex.matches(in: text, options: [], range: fullRange) {
				guard let range = Range(match.range(at: 0), in: text) else { continue }
				let mention = String(text[range])
				let username = String(mention.dropFirst())
				let className = staffUsernames.contains(username.lowercased()) ? "link-danger" : "link-primary"
				rewrites.append(Rewrite(
					range: NSRange(range, in: text),
					replacement: "<a class=\"\(className)\" href=\"/username/\(username)\">\(mention)</a>"
				))
			}

			// Hashtags: #tag -> <a class="link-primary" href="/forumpost/search?hashtag=tag">#tag</a>
			let hashtagRegex = try! NSRegularExpression(pattern: "(?<!\\S)(#[A-Za-z0-9]+)(?!\\S)")
			for match in hashtagRegex.matches(in: text, options: [], range: fullRange) {
				guard let range = Range(match.range(at: 0), in: text) else { continue }
				let hashtag = String(text[range])
				let tag = String(hashtag.dropFirst())
				rewrites.append(Rewrite(
					range: NSRange(range, in: text),
					replacement: "<a class=\"link-primary\" href=\"/forumpost/search?hashtag=\(tag)\">\(hashtag)</a>"
				))
			}
		}

		rewrites.sort { $0.range.location < $1.range.location }

		// Drop any rewrite that overlaps an earlier (lower-location) one. Two jocomoji that
		// share a colon (e.g. ":die:ship:") otherwise both match, and applying both corrupts
		// the output into broken HTML. Keeping the earliest-starting match mirrors the
		// plain-text path, where sequential replacement makes the second one unfindable.
		var kept: [Rewrite] = []
		for rewrite in rewrites {
			if let last = kept.last, rewrite.range.location < last.range.location + last.range.length {
				continue
			}
			kept.append(rewrite)
		}

		var result = text
		for rewrite in kept.reversed() {
			if let range = Range(rewrite.range, in: result) {
				result.replaceSubrange(range, with: rewrite.replacement)
			}
		}
		return result
	}

	/// Post-process cmark HTML to add Bootstrap link color classes to mention and hashtag links.
	/// Staff mentions get `link-danger`; regular mentions and hashtags get `link-primary`.
	/// This makes the coloring independent of URL case (unlike CSS href attribute selectors).
	static func addMentionLinkClasses(_ html: String) -> String {
		let staffUsernames = Self.staffUsernames
		var result = html

		// Mention links: <a href="/username/...">
		let mentionPattern = "<a href=\"/username/([^\"]+)\">"
		let mentionRegex = try! NSRegularExpression(pattern: mentionPattern)
		let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
		let matches = mentionRegex.matches(in: result, options: [], range: fullRange)
		for match in matches.reversed() {
			guard let fullMatchRange = Range(match.range(at: 0), in: result),
			      let usernameRange = Range(match.range(at: 1), in: result) else { continue }
			let username = String(result[usernameRange])
			let isStaff = staffUsernames.contains(username.lowercased())
			let className = isStaff ? "link-danger" : "link-primary"
			result.replaceSubrange(fullMatchRange, with: "<a class=\"\(className)\" href=\"/username/\(username)\">")
		}

		// Hashtag links: <a href="/forumpost/search?hashtag=...">
		let hashtagPattern = "<a href=\"(/forumpost/search\\?hashtag=[^\"]+)\">"
		let hashtagRegex = try! NSRegularExpression(pattern: hashtagPattern)
		let hRange = NSRange(result.startIndex..<result.endIndex, in: result)
		let hMatches = hashtagRegex.matches(in: result, options: [], range: hRange)
		for match in hMatches.reversed() {
			guard let fullMatchRange = Range(match.range(at: 0), in: result),
			      let hrefRange = Range(match.range(at: 1), in: result) else { continue }
			let href = String(result[hrefRange])
			result.replaceSubrange(fullMatchRange, with: "<a class=\"link-primary\" href=\"\(href)\">")
		}

		return result
	}

	/// Finds bare URLs in the (already neutralized) string and turns them into clickable links.
	///
	/// The string at this point is the result of `htmlEscaped()`, so any HTML the user typed is
	/// present as escaped entities (`&lt;a href=&quot;…&quot;&gt;…&lt;/a&gt;`). Those escaped tag regions are
	/// masked with unique placeholders before matching so the URL regex cannot reach into a tag's
	/// `href="…"` (or an `img`'s `src="…"`) and swallow the trailing `&quot;&gt;…` into one mangled,
	/// double-nested link with a stray `;`. Only the bare, untagged URLs that remain are linked; the
	/// typed HTML is restored verbatim and therefore renders as inert literal text.
	///
	/// Pass by ref can kinda be voodoo.
	/// https://stackoverflow.com/questions/27364117/is-swift-pass-by-value-or-pass-by-reference
	///
	/// - Parameter string: Reference to the Leaf string that is the HTML content to return to the user.
	///
	static func processUrlMatches(string: inout String) {
		// Mask every neutralized `&lt;…&gt;` region with a unique placeholder so the URL matcher below
		// can't reach into a typed tag (e.g. its href="…") and swallow the trailing &quot;&gt;… into the
		// "URL". The URL body class [^\s()<>{}\[\]]+ happily consumes &, ; and letters, which is exactly
		// what produced the mangled link. Only the ESCAPED regions (&lt;/&gt;) are masked; the raw <img>/<a>
		// tags that rewriteInline added use a real '<' and are left alone. Placeholders are \u{0001}N\u{0001}
		// tokens: not whitespace and ending in a non-alphanumeric, so the URL regex (which must end in
		// [a-zA-Z0-9]) never matches one.
		let escapedTagRegex = try! NSRegularExpression(pattern: "&lt;.*?&gt;")
		let maskLimit = NSRange(string.startIndex..., in: string)
		let maskedRegions = escapedTagRegex.matches(in: string, range: maskLimit)
		var stringWithMask = string
		// Map each placeholder index -> the original escaped-tag text, for the restore pass below.
		//
		// The placeholder is "[MASK <n>]" (NOT a bare \u{0001}n\u{0001} token). The URL body class
		// [^\s()<>{}\[\]]+ happily consumes \u{0001}, so a bare-URL immediately adjacent to a typed tag
		// (e.g. "https://x.com/page<img …>") would swallow a \u{0001}-delimited token into the match and
		// mangle it. The '[' breaks the URL body cleanly, so the URL stops before the placeholder. The
		// placeholder is also inert to the matcher itself (no http(s):// or canonical host to start on).
		// Substitute RIGHT-TO-LEFT: all regions' ranges were computed against the untouched string, so
		// replacing the rightmost region first never shifts the ranges of the regions still to its left.
		// (Left-to-right replacement would invalidate every earlier range, which is why the second typed
		// tag in a post was historically left unmasked and its href got swallowed by the URL matcher.)
		var masked: [Int: String] = [:]
		for (originalIndex, tagMatch) in maskedRegions.enumerated().reversed() {
			guard let tagRange = Range(tagMatch.range, in: stringWithMask) else { continue }
			masked[originalIndex] = String(stringWithMask[tagRange])
			stringWithMask.replaceSubrange(tagRange, with: "[MASK \(originalIndex)]")
		}

		// Now link the bare URLs that remain (the escaped-tag regions are inert placeholders).
		let matches = genericUrlRegex.matches(in: stringWithMask, range: NSRange(stringWithMask.startIndex..., in: stringWithMask))
		var processed = stringWithMask
		// We reverse the matches since we're gonna manipulate the string and insert characters (ie, HTML)
		// so we want to preserve the range indices if there are multiple matches within the same string.
		for match in matches.reversed() {
			guard let stringRange = Range(match.range(at: 0), in: processed) else { continue }
			var urlStr = String(processed[stringRange])
			// iOS Safari doesn't put "http(s)://" at the start links copied from the linkbar.
			// If the scheme isn't specified it messes with the URLComponents constructor and it
			// interprets the entire string as a path component. Weird.
			if !urlStr.hasPrefix("http") {
				urlStr = "http://\(urlStr)"
			}
			// Sometimes people write urls at the end of sentence like https://twitarr.com. This is
			// not a valid URL and usually 404's, so we chomp off that last period from the match.
			// https://stackoverflow.com/questions/24122288/remove-last-character-from-string-swift-language
			//
			// A future consideration could be to insert a special unicode character or sequence that the
			// frontend JS can detect and give users a popup saying their URL has been messed with.
			var urlTextSuffix = ""
			if urlStr.hasSuffix(".") {
				urlStr = String(urlStr.dropLast())
				urlTextSuffix = "."
			}
			// Strip the scheme/host/port from the link so that the origin the user is already
			// at is preserved. The browser will automatically handle this for us.
			// Only do this for URLs that have a real path (ie, not top level).
			guard var components = URLComponents(string: urlStr) else { continue }
			if Settings.shared.canonicalHostnames.contains(components.host ?? "")
				&& !["", "/"].contains(components.path)
			{
				(components.scheme, components.host, components.port) = (nil, nil, nil)
				var linkText = components.string
				if let url = URL(string: urlStr) {
					linkText = Self.canonicalLinkText(pathComponents: url.pathComponents) ?? linkText
				}
				// Replace the link's text with a wiki-like linkbox describing where the link goes
				processed.replaceSubrange(
					stringRange,
					with: "<a href=\"\(components.string!)\">\(linkText!)</a>\(urlTextSuffix)"
				)
			}
			else {
				// This is where we replace the text in the Leaf string with the newly crafted <a> element.
				processed.replaceSubrange(
					stringRange,
					with: "<a href=\"\(components.string!)\">\(components.string!)</a>\(urlTextSuffix)"
				)
			}
		}

		// Restore the masked typed-HTML regions verbatim so they render as inert literal text.
		// "[MASK <n>]" placeholders are unique, so order is irrelevant; each maps back to its original text.
		for (originalIndex, original) in masked {
			let token = "[MASK \(originalIndex)]"
			if let tokenRange = processed.range(of: token) {
				processed.replaceSubrange(tokenRange, with: original)
			}
		}

		string = processed
	}

	/// Wiki-style label for a canonical Twitarr site path, or `nil` when the path shouldn't be rewritten.
	/// Site LFG routes live under `/lfg`; `/fez` is kept so older posted URLs still get LFG labels.
	static func canonicalLinkText(pathComponents: [String]) -> String? {
		guard pathComponents.count > 1, pathComponents[0] == "/" else { return nil }
		switch pathComponents[1] {
		case "tweets": return "[Twitarr Tweet Link]"
		case "forums":
			if pathComponents.count == 2 {
				return "[Forum Categories Link]"
			}
			else {
				return "[Forum Category Link]"
			}
		case "forum": return "[Forum Link]"
		case "seamail": return "[Seamail Link]"
		case "fez", "lfg":
			if pathComponents.count > 2 {
				switch pathComponents[2] {
				case "joined": return "[Joined LFGs Link]"
				case "owned": return "[Your LFGs Link]"
				case "faq": return "[LFG FAQ Link]"
				default: return "[LFG Link]"
				}
			}
			else {
				return "[LFGs Link]"
			}
		case "events": return "[Events Link]"
		case "user", "profile": return "[User Link]"
		case "boardgames":
			if pathComponents.count > 2 {
				return "[Boardgame Link]"
			}
			else {
				return "[Boardgames Link]"
			}
		case "karaoke": return "[Karaoke Link]"
		case "communitysupport":
			return pathComponents.count > 3 && pathComponents[2] == "report" ? "[Community Support Report Link]" : "[Community Support Link]"
		case "quartermaster":
			if pathComponents.count > 2 {
				switch pathComponents[2] {
				case "need": return "[Quartermastarr Need Link]"
				case "owned": return "[Your Quartermastarr Items Link]"
				case "about": return "[Quartermastarr Info Link]"
				default: return "[Quartermastarr Item Link]"
				}
			}
			else {
				return "[Quartermastarr Have Link]"
			}
		default: return "[Twitarr Link]"
		}
	}

	enum Usage {
		case twarrt
		case forumpost
		case fez
		case seamail
	}
	let usage: Usage

	/// The regex that finds bare URLs in post text, built once from the canonical hostnames. Static so
	/// `processUrlMatches` can be exercised directly from tests without instantiating the Leaf tag.
	static let genericUrlRegex: NSRegularExpression = {
		// Let https://regex101.com/ be your guide on this spiritual journey.
		// This regex matches any URL starting in http:// or https://.
		// Certain browsers (looking at you Safari on iOS) do not prefix the scheme in pasted links from the linkbar.
		// These will not be caught by this regex but instead by the canonical names one below.
		// To be at least a little bit safe we replace all hostname dots (twittar.com) with regex-escaped literal dots.
		// The canonicalNamesRegexStr has both http and https seperated because lookbacks must be of fixed length.
		// So https?:// is unavailable which makes me sad.
		let escapedCanonicalHostnames = Settings.shared.canonicalHostnames.joined(separator: "|")
			.replacingOccurrences(of: ".", with: "\\.")
		let genericUrlRegexStr =
			"(?i)\\b((?:https?:(?:/{1,3}|[a-z0-9%])|\(escapedCanonicalHostnames)/)(?:[^\\s()<>{}\\[\\]]+|\\([^\\s()]*?\\([^\\s()]+\\)[^\\s()]*?\\)|\\([^\\s]+?\\))+(?:\\([^\\s()]*?\\([^\\s()]+\\)[^\\s()]*?\\)|\\([^\\s]+?\\)|[^\\s`!()\\[\\]{};:'\".,<>?«»“”‘’])|(?:(?<!@)\(escapedCanonicalHostnames)\\b/?(?!@)))"
		return try! NSRegularExpression(pattern: genericUrlRegexStr, options: .caseInsensitive)
	}()

	init(_ forUsage: Usage) {
		usage = forUsage
	}
}

/// Wraps `MarkdownTag` (cmark) output in a `<div class="markdown-body">` so that
/// site CSS can scope mention-link colors and jocomoji sizing to Markdown content.
///
/// Usage: #markdownTextTag(String) -> String
struct MarkdownBodyTag: UnsafeUnescapedLeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard let markdown = ctx.parameters[0].string else {
			return LeafData.string("")
		}
		let html = FormatPostTextTag.formatEscapedMarkdown(markdown)
		let styled = FormatPostTextTag.neutralizeDangerousSchemes(FormatPostTextTag.addMentionLinkClasses(html))
		return LeafData.string("<div class=\"markdown-body\">\(styled)</div>")
	}
}

// MARK: - Tags for Displaying Dates

/// Turns a Date string into a relative date string. Argument is a ISO8601 formatted Date, or what JSON encoding
/// does to Date values. Output is a string giving a relative time in the past (from now) indicating the approximate time of the Date.
///
///	Output is constrained to a single element. e.g: "3 hours ago", "1 day ago", "5 minutes ago"
///
/// Usage in Leaf templates: #relativeTime(dateValue) -> String
struct RelativeTimeTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard let dateStr = ctx.parameters[0].string, let ti = TimeInterval(dateStr) else {
			return LeafData.string("")
		}
		let date = Date(timeIntervalSince1970: ti)
		if date.timeIntervalSinceNow > -1.0 {
			return "a second ago"
		}

		// If the date is Date.distantPast
		let daySecs = 60 * 60 * 24
		if date.timeIntervalSinceNow < Double(0 - daySecs * 365 * 100) {
			return ""
		}

		let hour = 60.0 * 60.0
		let day = hour * 24.0
		let month = day * 30.0
		let year = day * 365.0
		let interval = Date().timeIntervalSince(date)

		// Initially I'd just used DateComponentsFormatter to produce human-readable relative time strings.
		// However, swift-corelibs-foundation doesn't support DateComponentsFormatter as yet, which means Linux builds fail.
		switch interval {
		case 0..<1: return "just now"
		case 1..<60:
			let secs = Int(interval)
			return LeafData.string("\(secs) second\(secs == 1 ? "" : "s") ago")
		case 60..<hour:
			let mins = Int(interval / 60.0)
			return LeafData.string("\(mins) minute\(mins == 1 ? "" : "s") ago")
		case hour..<day:
			let hours = Int(interval / hour)
			return LeafData.string("\(hours) hour\(hours == 1 ? "" : "s") ago")
		case day..<month:
			let days = Int(interval / day)
			return LeafData.string("\(days) day\(days == 1 ? "" : "s") ago")
		case month..<year:
			let months = Int(interval / month)
			return LeafData.string("\(months) month\(months == 1 ? "" : "s") ago")
		case year..<year * 10:
			let years = Int(interval / year)
			return LeafData.string("\(years) year\(years == 1 ? "" : "s") ago")
		default: return "some time ago"
		}
	}
}

/// Returns a string descibing when an event is taking place. Shows both the start and end time.
///
/// Events come to us from the Sched dump which THO populates as "consistent-boat-EST-based-UTC".
/// Meaning that the raw values from Sched are in UTC and the events are scheduled for EST and not
/// adjusted for any time-zone changes. This means that on any day where the boat (display) time zone
/// changes the Sched is off by that offset. Since EST is given as the reference point for
/// timezoneless time on the ship we call that "Port Time" and always render events based on that
/// perspective so that it will be consistent.
///
/// For 2022 a munger was developed so that the days of odd time zones get their UTC times adjusted
/// by the difference between Port Timezone and AST (which was our only transition). As such there
/// is currently no functional difference between EvenTimeTag and FezTimeTag. It is being left in
/// the code so that some day we can define programatic timezone transitions and not have to do
/// munging of the input.
///
/// Usage in Leaf templates:: #eventTime(startTime, endTime) -> String
struct EventTimeTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(2)
		guard let startTimeDouble = ctx.parameters[0].double, let endTimeDouble = ctx.parameters[1].double else {
			throw "Leaf: Unable to convert parameter to double for date"
		}
		let startTime = Date(timeIntervalSince1970: startTimeDouble)
		let endTime = Date(timeIntervalSince1970: endTimeDouble)
		let timezone: TimeZone = Settings.shared.timeZoneChanges.tzAtTime(startTime)

		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		dateFormatter.locale = Locale(identifier: "en_US")
		dateFormatter.timeZone = timezone

		var timeString = dateFormatter.string(from: startTime)
		dateFormatter.dateStyle = .none
		timeString.append(" - \(dateFormatter.string(from: endTime))")
		timeString.append(" \(timezone.abbreviation(for: startTime) ?? "")")
		return LeafData.string(timeString)
	}
}

/// Returns a string descibing when an LFG is taking place. Shows both the start and end time.
///
/// Usage in Leaf templates:: #fezTime(startTime, endTime) -> String
struct FezTimeTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(2)
		guard let startTimeDouble = ctx.parameters[0].double, let endTimeDouble = ctx.parameters[1].double else {
			throw "Leaf: Unable to convert parameter to double for date"
		}
		let startTime = Date(timeIntervalSince1970: startTimeDouble)
		let endTime = Date(timeIntervalSince1970: endTimeDouble)
		let timezone: TimeZone = Settings.shared.timeZoneChanges.tzAtTime(startTime)

		let dateFormatter = DateFormatter()
		dateFormatter.locale = Locale(identifier: "en_US")
		dateFormatter.setLocalizedDateFormatFromTemplate("M/d, h:mm a")
		dateFormatter.timeZone = timezone

		var timeString = dateFormatter.string(from: startTime)
		dateFormatter.setLocalizedDateFormatFromTemplate("h:mm a z")
		timeString.append(" - \(dateFormatter.string(from: endTime))")
		return LeafData.string(timeString)
	}
}

/// Returns a string describing a time. Unlike EventTimeTag this is used for a single point in time rather
/// than a range or duration.
///
/// Usage in Leaf templates:: #staticTime(startTime) -> String
struct StaticTimeTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard let inputTimeDouble = ctx.parameters[0].double else {
			throw "Leaf: Unable to convert parameter to double for date"
		}
		let inputTime = Date(timeIntervalSince1970: inputTimeDouble)

		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .short
		dateFormatter.timeStyle = .short
		dateFormatter.locale = Locale(identifier: "en_US")
		dateFormatter.timeZone = Settings.shared.timeZoneChanges.tzAtTime(inputTime)
		let timeString = "\(dateFormatter.string(from: inputTime)) \(dateFormatter.timeZone.abbreviation() ?? "")"
		return LeafData.string(timeString)
	}
}

/// Returns a string describing a time, expressed as a ISO8601 time string in the GMT timezone.
/// That is: `20221103T002152Z`.
///
/// Usage in Leaf templates:: #UTCTime(time) -> String
struct UTCTimeTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard let inputTimeDouble = ctx.parameters[0].double else {
			throw "Leaf: Unable to convert parameter to double for date"
		}

		let dateFormatter = ISO8601DateFormatter()
		let timeString = "\(dateFormatter.string(from: Date(timeIntervalSince1970: inputTimeDouble)))"
		return LeafData.string(timeString)
	}
}

/// Return an ISO8601-ish time string for use with the HTML datetime-local form input type.
/// It cannot take an ISO8601 since that requires a timezone to be included (suffix
/// of [+-]H:MM) and the input chokes on that. So here we translate the following:
///
/// "2022-02-13 02:00:00 +0000" (Date) -> "2022-02-12T18:00:00" (String)
///
struct LocalTimeTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard let inputTimeDouble = ctx.parameters[0].double else {
			throw "Leaf: Unable to convert parameter to double for date"
		}
		let inputTime = Date(timeIntervalSince1970: inputTimeDouble)

		// https://www.objc.io/blog/2018/12/04/unexpected-results-from-a-date-formatter/
		let dateFormatter = DateFormatter()
		dateFormatter.timeZone = Settings.shared.timeZoneChanges.tzAtTime(inputTime)
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
		return LeafData.string(dateFormatter.string(from: inputTime))
	}
}

/// Turns a Date into a indexed day of the cruise, with embarkation day being day 0. Used to get the day on which an event happens.
/// This code counts ''days' as starting/ending at 3AM instead of midnight, as there are often after-midnight events but rarely 3AM events.
///
/// Usage: #cruiseDayIndex(date)  returns 0...8
struct CruiseDayIndexTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard let startTimeDouble = ctx.parameters[0].double else {
			throw "Leaf: Unable to convert parameter to double for date"
		}
		let difference =
			Date(timeIntervalSince1970: startTimeDouble).timeIntervalSince(Settings.shared.cruiseStartDate()) - 3600 * 3
		let dayIndex = String(Int(floor(difference / (3600.0 * 24.0))))
		return LeafData.string(dayIndex)
	}
}

// MARK: - Tags for Styling Users

/// Inserts an <img> tag for the given user's avatar image. Presents a default image if the user doesn't have an image.
/// Note: If we implement identicons at the API level, users will always have images, and the 'generic user' image here is just a fallback.
///
/// First parameter is the UserHeader, second optional parameter is the size of the <img> to produce. This tag will select the best size image to reference
/// based on the size of  the image tag it is being placed in. Only produces square image views.
///
/// Usage: #avatar(userHeader), #avatar(userHeader, 800)
struct AvatarTag: UnsafeUnescapedLeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		var imgSize = 40
		if ctx.parameters.count > 1, let tempSize = ctx.parameters[1].int {
			imgSize = tempSize
		}
		guard ctx.parameters.count >= 1, let userHeader = ctx.parameters[0].dictionary,
			let userID = userHeader["userID"]?.string
		else {
			throw "Leaf: avatarTag tag unable to get user header."
		}
		let imgLoadSize = imgSize > Settings.shared.imageThumbnailSize ? "full" : "thumb"
		var imagePath = "/api/v3/image/user/identicon/\(userID)"
		if let customImage = userHeader["userImage"]?.string {
			imagePath = "/api/v3/image/\(imgLoadSize)/\(customImage)"
		}
		return LeafData.string("<img src=\"\(imagePath)\" width=\(imgSize) height=\(imgSize) alt=\"Avatar\">")
	}
}

/// Inserts an <a> tag with the given user's display name and username, linking to the user's profile page. As an UnsafeUnescaped tag, needs to
/// sanitize user-provided text itself.
///
/// Usage: #userByline(userHeader)
/// Or: #userByline(userHeader, "css-class") to style the link
/// Or: #userByline(userHeader, "short") to display a shorter link (only the username, no displayname).
/// Or: #userByline(userHeader, "nolink") to display the username and displayname, without a link
/// Or: #userByline(userHeader, "short-nolink") to display only the username without a link
/// Or: #userByline(userHeader, "pronoun") to display the username and displayname with pronouns.
struct UserBylineTag: UnsafeUnescapedLeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		guard ctx.parameters.count >= 1, let userHeader = ctx.parameters[0].dictionary,
			let userID = userHeader["userID"]?.string,
			let username = userHeader["username"]?.string?.htmlEscaped()
		else {
			throw "Leaf: userByline tag unable to get user header."
		}
		var styling = ""
		if ctx.parameters.count >= 2, let newStyle = ctx.parameters[1].string {
			styling = newStyle
		}
		func stylingSearch(style: String, in styling: inout String) -> Bool {
			if styling.contains(style) {
				styling = styling.replacingOccurrences(of: style, with: "")
				return true
			}
			return false
		}
		let shortStyle = stylingSearch(style: "short", in: &styling)
		let nolinkStyle = stylingSearch(style: "nolink", in: &styling)
		let pronounStyle = stylingSearch(style: "pronoun", in: &styling)
		if ["admin", "THO", "TwitarrTeam", "moderator", "CommunitySupport"].contains(username) {
			styling.append(" text-danger")
		}
		if nolinkStyle {
			if shortStyle {
				// short-nolink: only username, no link
				return LeafData.string("<span class=\"\(styling)\">@\(username)</span>")
			}
			// nolink: display name and username, no link
			if let displayName = userHeader["displayName"]?.string?.htmlEscaped() {
				return LeafData.string("<span class=\"\(styling)\"><b>\(displayName)</b> @\(username)</span>")
			}
			return LeafData.string("<span class=\"\(styling)\">@\(username)</span>")
		}
		else if !shortStyle, let displayName = userHeader["displayName"]?.string?.htmlEscaped() {
			if pronounStyle, let preferredPronoun = userHeader["preferredPronoun"]?.string?.htmlEscaped() {
				return LeafData.string(
					"<a class=\"\(styling)\" href=\"/user/\(userID)\"><b>\(displayName)</b> @\(username) (\(preferredPronoun))</a>"
				)
			}
			return LeafData.string(
				"<a class=\"\(styling)\" href=\"/user/\(userID)\"><b>\(displayName)</b> @\(username)</a>"
			)
		}
		else {
			if pronounStyle, let preferredPronoun = userHeader["preferredPronoun"]?.string?.htmlEscaped() {
				return LeafData.string(
					"<a class=\"\(styling)\" href=\"/user/\(userID)\">@\(username) (\(preferredPronoun))</a>"
				)
			}
			return LeafData.string("<a class=\"\(styling)\" href=\"/user/\(userID)\">@\(username)</a>")
		}
	}
}

// MARK: - Other Tags

/// Gets the user-formatted label string for the given tyhpe of LFG.
///
/// Usage: #lfgLabel(String)
struct LFGLabelTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		guard ctx.parameters.count == 1, let value = ctx.parameters[0].string else {
			throw "Leaf: LFGLabelTag tag unable to get string value."
		}
		guard let type = FezType(rawValue: value) else {
			return ""
		}
		return LeafData.string(type.label)
	}
}

/// Prints a float with 2 decimal precision e.g. "5.76". Used by game ratings and game complexity.
///
/// Usage: #gameRating(float)
struct GameRatingTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		guard ctx.parameters.count == 1, let value = ctx.parameters[0].double else {
			throw "Leaf: gameRating tag unable to get float value."
		}
		let str = String(format: "%.2f", value)
		return LeafData.string(str)
	}
}

/// https://github.com/jocosocial/swiftarr/issues/188
/// Renders a pretty label for a dinner team enum. I have to believe there's a better way to
/// access fancy properties like dinnerTeam.label from within the template, but I didn't see
/// an obvious pattern that worked.
struct DinnerTeamTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		guard ctx.parameters.count == 1, let value = ctx.parameters[0].string else {
			throw "Leaf: DinnerTeamTag tag unable to get string value."
		}
		guard let dinnerTeam = DinnerTeam(rawValue: value) else {
			return ""
		}
		return LeafData.string(dinnerTeam.label)
	}
}

// Percent-encodes a string for safe use as a single value in a URL query string -- e.g. a piece of
// user-generated text being spliced into an href. Escapes "&", "=", and "+" in addition to the usual
// urlQueryAllowed set, since those are still meaningful as query-string structure even though they're
// technically legal characters within one.
//
// Usage: #urlEncode(string)
struct URLEncodeTag: LeafTag {
	static let queryValueAllowed: CharacterSet = {
		var allowed = CharacterSet.urlQueryAllowed
		allowed.remove(charactersIn: "&=+")
		return allowed
	}()

	func render(_ ctx: LeafContext) throws -> LeafData {
		guard ctx.parameters.count == 1, let value = ctx.parameters[0].string else {
			throw "Leaf: urlEncode tag unable to get string value."
		}
		return LeafData.string(value.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? value)
	}
}

// Similar to the built-in `isEmpty` Leaf tag, except it returns LeafData(false) if its argument is LeafData(nil).
// isEmpty() throws an error if presented with nil, and is not a great choice for optional strings.
// Note that we can't distinguish between a value that was nil in the context before it got serialized and a variable name
// that wasn't ever in the context (like a typo).
//
// Usage: #notEmpty(value)
struct NotEmptyTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard let leafData = ctx.parameters.first else {
			throw "Couldn't extract first parameter to NotEmpty tag"
		}
		if leafData.isNil {
			return .bool(false)
		}
		guard let str = leafData.string else {
			throw "unable to check for empty value unexpected data"
		}
		return .bool(!str.isEmpty)
	}
}

// Have I become that guy? Is inserting obvious references to forty year old Gibson books still cool?
// Anyway, unlike Leaf's #count(), this returns 0 if the parameter isn't an array or dict. Most useful
// when the parameter is an optional that may be nil.
//
// Usage: #countOrZero(value)
struct CountZeroTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		if let array = ctx.parameters[0].array {
			return LeafData.int(array.count)
		}
		else if let dictionary = ctx.parameters[0].dictionary {
			return LeafData.int(dictionary.count)
		}
		else {
			return .int(0)
		}
	}
}

/// Renders the human-readable name of a ModeratorActionType, e.g. "regCodeViewed" → "Viewed Registration Code".
/// Unknown values are rendered as-is so old log rows never disappear from the moderator log.
///
/// Usage: #moderatorActionName(String) -> String
struct ModeratorActionNameTag: LeafTag {
	func render(_ ctx: LeafContext) throws -> LeafData {
		guard ctx.parameters.count == 1, let value = ctx.parameters[0].string else {
			throw "Leaf: ModeratorActionNameTag tag unable to get string value."
		}
		guard let actionType = ModeratorActionType(rawValue: value) else {
			return LeafData.string(value)
		}
		return LeafData.string(actionType.visibleName())
	}
}

/// Renders a registration code as bold monospace text in THO-style groups, e.g. "abcabc" → "ABC ABC".
///
/// Usage: #regCode(String)
struct RegCodeTag: UnsafeUnescapedLeafTag {
	static func format(_ code: String) -> String {
		RegistrationCode.displayString(code)
	}

	func render(_ ctx: LeafContext) throws -> LeafData {
		try ctx.requireParameterCount(1)
		guard let string = ctx.parameters[0].string, !string.isEmpty else {
			return LeafData.string("")
		}
		let display = RegCodeTag.format(string).htmlEscaped()
		return LeafData.string("<span class=\"font-monospace\">\(display)</span>")
	}
}
