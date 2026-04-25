import XCTVapor
@testable import swiftarr

class ThemeCookieTests: XCTestCase {

	func testResolveTheme_NilDefaultsToAuto() {
		XCTAssertEqual(TrunkContext.resolveTheme(from: nil), "auto")
	}

	func testResolveTheme_EmptyDefaultsToAuto() {
		XCTAssertEqual(TrunkContext.resolveTheme(from: ""), "auto")
	}

	func testResolveTheme_AutoIsValid() {
		XCTAssertEqual(TrunkContext.resolveTheme(from: "auto"), "auto")
	}

	func testResolveTheme_LightIsValid() {
		XCTAssertEqual(TrunkContext.resolveTheme(from: "light"), "light")
	}

	func testResolveTheme_DarkIsValid() {
		XCTAssertEqual(TrunkContext.resolveTheme(from: "dark"), "dark")
	}

	func testResolveTheme_GarbageDefaultsToAuto() {
		XCTAssertEqual(TrunkContext.resolveTheme(from: "javascript:alert(1)"), "auto")
	}

	func testResolveTheme_CaseSensitive() {
		// We accept only lowercase canonical values; "DARK" should fall back to auto.
		XCTAssertEqual(TrunkContext.resolveTheme(from: "DARK"), "auto")
	}
}
