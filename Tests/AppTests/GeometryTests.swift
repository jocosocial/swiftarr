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

	// MARK: - Color int initializer (RGBA layout)

	func testColor_IntInit_RGBA() {
		// 0xFF000080: R=FF, G=00, B=00, A=80
		let color = Color(hex: 0xFF000080)
		XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.alphaComponent, 128.0 / 255.0, accuracy: 0.001)
	}

	func testColor_IntInit_RGBA_Opaque() {
		// 0x00FF00FF: R=00, G=FF, B=00, A=FF (fully opaque green)
		let color = Color(hex: 0x00FF00FF)
		XCTAssertEqual(color.redComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.alphaComponent, 1.0, accuracy: 0.001)
	}

	// MARK: - Color int initializer (ARGB layout)

	func testColor_IntInit_ARGB() {
		// 0x80FF0000 leadingAlpha=true: A=80, R=FF, G=00, B=00
		let color = Color(hex: 0x80FF0000, leadingAlpha: true)
		XCTAssertEqual(color.alphaComponent, 128.0 / 255.0, accuracy: 0.001)
		XCTAssertEqual(color.redComponent, 1.0, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 0.0, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.0, accuracy: 0.001)
	}

	// MARK: - Color basic initializer + constants

	func testColor_BasicInit() {
		let color = Color(red: 0.25, green: 0.5, blue: 0.75, alpha: 1.0)
		XCTAssertEqual(color.redComponent, 0.25, accuracy: 0.001)
		XCTAssertEqual(color.greenComponent, 0.5, accuracy: 0.001)
		XCTAssertEqual(color.blueComponent, 0.75, accuracy: 0.001)
		XCTAssertEqual(color.alphaComponent, 1.0, accuracy: 0.001)
	}

	func testColor_NamedConstants() {
		XCTAssertEqual(Color.red.redComponent, 1.0)
		XCTAssertEqual(Color.green.greenComponent, 1.0)
		XCTAssertEqual(Color.blue.blueComponent, 1.0)
		XCTAssertEqual(Color.black.redComponent, 0.0)
		XCTAssertEqual(Color.black.greenComponent, 0.0)
		XCTAssertEqual(Color.black.blueComponent, 0.0)
		XCTAssertEqual(Color.white.redComponent, 1.0)
		XCTAssertEqual(Color.white.greenComponent, 1.0)
		XCTAssertEqual(Color.white.blueComponent, 1.0)
	}

	// MARK: - Angle

	func testAngle_RadiansInit() {
		let angle = Angle(radians: .pi)
		XCTAssertEqual(angle.radians, .pi, accuracy: 0.0001)
		XCTAssertEqual(angle.degrees, 180.0, accuracy: 0.0001)
	}

	func testAngle_DegreesInit() {
		let angle = Angle(degrees: 90)
		XCTAssertEqual(angle.degrees, 90.0, accuracy: 0.0001)
		XCTAssertEqual(angle.radians, .pi / 2.0, accuracy: 0.0001)
	}

	func testAngle_DegreesSetter_UpdatesRadians() {
		var angle = Angle(degrees: 0)
		angle.degrees = 360
		XCTAssertEqual(angle.radians, 2 * .pi, accuracy: 0.0001)
	}

	func testAngle_Zero() {
		XCTAssertEqual(Angle.zero.radians, 0.0, accuracy: 0.0001)
		XCTAssertEqual(Angle.zero.degrees, 0.0, accuracy: 0.0001)
	}

	func testAngle_StaticFactories() {
		XCTAssertEqual(Angle.radians(.pi).degrees, 180.0, accuracy: 0.0001)
		XCTAssertEqual(Angle.degrees(180).radians, .pi, accuracy: 0.0001)
	}

	// MARK: - Point / Size / Rectangle

	func testPoint_Int32InitMatchesIntInit() {
		let pInt = Point(x: 5, y: 10)
		let p32 = Point(x: Int32(5), y: Int32(10))
		XCTAssertEqual(pInt.x, p32.x)
		XCTAssertEqual(pInt.y, p32.y)
	}

	func testRectangle_ConvenienceInitMatchesPointSizeInit() {
		let r1 = Rectangle(point: Point(x: 1, y: 2), size: Size(width: 3, height: 4))
		let r2 = Rectangle(x: 1, y: 2, width: 3, height: 4)
		XCTAssertEqual(r1.point.x, r2.point.x)
		XCTAssertEqual(r1.point.y, r2.point.y)
		XCTAssertEqual(r1.size.width, r2.size.width)
		XCTAssertEqual(r1.size.height, r2.size.height)
	}
}
