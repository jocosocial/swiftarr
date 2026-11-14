import XCTest
@testable import swiftarr

/// Presentation variants must share storage identity without merging distinct skin tones or sequences.
final class ReactionIdentityTests: XCTestCase {
	/// Exercises picker forms, legacy tokens, custom tokens, and meaningful modifiers.
	func testReactionCanonicalization() throws {
		for value in ["👍", "👍\u{FE0F}", "👍\u{FE0E}"] {
			XCTAssertEqual(try PostReactionData(reaction: value).validatedReaction(), "👍")
		}
		XCTAssertEqual(try PostReactionData(reaction: "❤").validatedReaction(), "❤️")
		XCTAssertEqual(try PostReactionData(reaction: "❤️").validatedReaction(), "❤️")
		XCTAssertEqual(try PostReactionData(reaction: ":arr:").validatedReaction(), ":arr:")
		XCTAssertNotEqual(try PostReactionData(reaction: "👍🏽").validatedReaction(), "👍")
		XCTAssertEqual(try PostReactionData(reaction: "👨‍👩‍👧‍👦").validatedReaction(), "👨‍👩‍👧‍👦")
		XCTAssertThrowsError(try PostReactionData(reaction: "\u{FE0F}").validatedReaction())
	}
}
