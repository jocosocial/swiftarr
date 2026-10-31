import XCTest
@testable import swiftarr

#if canImport(CoreImage)
	import CoreImage
#endif

// Pure tests (no DB) for the qr-code command's renderer.
class QRCodeRendererTests: XCTestCase {

	private let longURL = "https://twitarr.com/clients?platform=android"

	override func setUp() {
		SwiftarrImage.initializeVips()
	}

	private func pngSize(_ data: Data) throws -> (width: Int, height: Int) {
		XCTAssertEqual(Array(data.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], "not a PNG")
		let image = try SwiftarrImage(data: data)
		return (Int(image.size.width), Int(image.size.height))
	}

	func testDefaultOutputIsSquarePNGWithIcon() throws {
		let result = try QRCodeRenderer().render(longURL)
		XCTAssertTrue(result.iconApplied)
		let size = try pngSize(result.png)
		XCTAssertEqual(size.width, size.height)
		XCTAssertEqual(size.width % 32, 0, "size should be a whole number of modules")
	}

	func testNoIconSwitchSkipsIcon() throws {
		let withIcon = try QRCodeRenderer(moduleSize: 8).render(longURL)
		let without = try QRCodeRenderer(icon: false, moduleSize: 8).render(longURL)
		XCTAssertFalse(without.iconApplied)
		XCTAssertNotEqual(withIcon.png, without.png)
	}

	func testNoRoundedSwitchChangesOutput() throws {
		let rounded = try QRCodeRenderer(icon: false, moduleSize: 8).render(longURL)
		let square = try QRCodeRenderer(rounded: false, icon: false, moduleSize: 8).render(longURL)
		XCTAssertNotEqual(rounded.png, square.png)
	}

	func testTinyCodeSkipsIcon() throws {
		let result = try QRCodeRenderer(moduleSize: 8).render("https://a.co")
		XCTAssertFalse(result.iconApplied)
		_ = try pngSize(result.png)
	}

	func testVeryLargeCodeSkipsIcon() throws {
		let result = try QRCodeRenderer(moduleSize: 8).render("https://twitarr.com/" + String(repeating: "a", count: 120))
		XCTAssertFalse(result.iconApplied)
	}

	func testModuleSizeScalesOutput() throws {
		let small = try pngSize(try QRCodeRenderer(icon: false, moduleSize: 8).render(longURL).png)
		let large = try pngSize(try QRCodeRenderer(icon: false, moduleSize: 16).render(longURL).png)
		XCTAssertEqual(large.width, small.width * 2)
	}

	#if canImport(CoreImage)
		/// Every style combination must still scan back to the original text.
		func testAllStylesDecode() throws {
			let detector = try XCTUnwrap(
				CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
			)
			for (rounded, icon) in [(true, true), (true, false), (false, true), (false, false)] {
				let png = try QRCodeRenderer(rounded: rounded, icon: icon, moduleSize: 16).render(longURL).png
				let image = try XCTUnwrap(CIImage(data: png))
				let decoded = (detector.features(in: image).first as? CIQRCodeFeature)?.messageString
				XCTAssertEqual(decoded, longURL, "rounded=\(rounded) icon=\(icon)")
			}
		}
	#endif
}
