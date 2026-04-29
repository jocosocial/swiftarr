import XCTVapor
@testable import swiftarr

class GeometryTests: XCTestCase {

	// MARK: - 6-character hex (RRGGBB)

	func testColor_SixCharHex_NoPrefix() throws {
		let color = try Color(hex: "ff0000")
		XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.alphaComponent, 1.0, accuracy: 0.001)
	}

	func testColor_SixCharHex_WithHashPrefix() throws {
		let color = try Color(hex: "#00ff00")
		XCTAssertEqual(color.redComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.alphaComponent, 1.0, accuracy: 0.001)
	}

	// MARK: - 8-character hex with trailing alpha (RRGGBBAA)

	func testColor_EightCharHex_TrailingAlpha() throws {
		let color = try Color(hex: "ff000080")
		XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.alphaComponent, 128.0 / 255.0, accuracy: 0.001)
	}

	// MARK: - 8-character hex with leading alpha (AARRGGBB)

	func testColor_EightCharHex_LeadingAlpha() throws {
		let color = try Color(hex: "80ff0000", leadingAlpha: true)
		XCTAssertEqual(color.alphaComponent, 128.0 / 255.0, accuracy: 0.001)
		XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
	}

	// MARK: - 3-character short hex (RGB → RRGGBB)

	func testColor_ThreeCharShortHex() throws {
		let color = try Color(hex: "f00")
		XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.alphaComponent, 1.0, accuracy: 0.001)
	}

	// MARK: - 4-character short hex with trailing alpha (RGBA → RRGGBBAA)

	func testColor_FourCharShortHex_TrailingAlpha() throws {
		let color = try Color(hex: "f008")
		XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.alphaComponent, Double(0x88) / 255.0, accuracy: 0.001)
	}

	// MARK: - Invalid input

	func testColor_InvalidLengthThrows() {
		XCTAssertThrowsError(try Color(hex: "ff")) { error in
			guard case ImageError.invalidColor = error else {
				return XCTFail("Expected ImageError.invalidColor, got \(error)")
			}
		}
	}

	func testColor_InvalidCharactersThrow() {
		XCTAssertThrowsError(try Color(hex: "zzzzzz")) { error in
			guard case ImageError.invalidColor = error else {
				return XCTFail("Expected ImageError.invalidColor, got \(error)")
			}
		}
	}

	func testColor_EmptyStringThrows() {
		XCTAssertThrowsError(try Color(hex: "")) { error in
			guard case ImageError.invalidColor = error else {
				return XCTFail("Expected ImageError.invalidColor, got \(error)")
			}
		}
	}

	// MARK: - Boundary values

	func testColor_AllBlack() throws {
		let color = try Color(hex: "000000")
		XCTAssertEqual(color.redComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
	}

	func testColor_AllWhite() throws {
		let color = try Color(hex: "ffffff")
		XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 1.0, accuracy: 0.001)
	}
}
