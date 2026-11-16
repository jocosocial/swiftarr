import XCTest
@testable import swiftarr

/// Reactions preserve the exact Unicode sequence supplied by clients.
final class ReactionIdentityTests: XCTestCase {
	/// Exercises picker forms, legacy tokens, custom tokens, and meaningful modifiers.
	func testReactionIdentity() throws {
		for value in ["☺", "☺️", "👍", "👍\u{FE0F}", "👍\u{FE0E}"] {
			XCTAssertEqual(try PostReactionData(reaction: value).validatedReaction(), value)
		}
		XCTAssertEqual(try PostReactionData(reaction: "❤").validatedReaction(), "❤")
		XCTAssertEqual(try PostReactionData(reaction: "❤️").validatedReaction(), "❤️")
		XCTAssertEqual(try PostReactionData(reaction: ":arr:").validatedReaction(), ":arr:")
		XCTAssertNotEqual(try PostReactionData(reaction: "👍🏽").validatedReaction(), "👍")
		XCTAssertEqual(try PostReactionData(reaction: "👨‍👩‍👧‍👦").validatedReaction(), "👨‍👩‍👧‍👦")
		XCTAssertThrowsError(try PostReactionData(reaction: "\u{FE0F}").validatedReaction())
	}
}
