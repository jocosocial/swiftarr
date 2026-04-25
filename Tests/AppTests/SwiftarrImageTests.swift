// ABOUTME: Unit tests for SwiftarrImage, the libvips-backed image wrapper.
// ABOUTME: Tests cover loading, resizing, cropping, alpha handling, and export.

import XCTVapor
@testable import swiftarr

class SwiftarrImageTests: XCTestCase {

	override class func setUp() {
		super.setUp()
		SwiftarrImage.initializeVips()
	}

	// MARK: - Test Fixtures

	private func makeTestJPEG(width: Int = 10, height: Int = 10) throws -> Data {
		let pixels = [UInt8](repeating: 0, count: width * height * 3)
		let image = try SwiftarrImage(width: width, height: height, pixels: pixels)
		return try image.exportAsJPEG(quality: 90)
	}

	private func makeTestPNGWithAlpha(width: Int = 10, height: Int = 10) throws -> Data {
		var pixels = [UInt8](repeating: 0, count: width * height * 4)
		for i in stride(from: 0, to: pixels.count, by: 4) {
			pixels[i] = 255	 // R
			pixels[i + 1] = 0   // G
			pixels[i + 2] = 0   // B
			pixels[i + 3] = 128 // A (50% transparent)
		}
		let image = try SwiftarrImage(width: width, height: height, pixels: pixels, bands: 4)
		return try image.exportAsPNG()
	}

	// MARK: - Loading

	func testLoadJPEG() throws {
		let jpegData = try makeTestJPEG()
		let image = try SwiftarrImage(data: jpegData)
		XCTAssertEqual(image.size.width, 10)
		XCTAssertEqual(image.size.height, 10)
	}

	func testLoadPNG() throws {
		let pngData = try makeTestPNGWithAlpha()
		let image = try SwiftarrImage(data: pngData)
		XCTAssertEqual(image.size.width, 10)
		XCTAssertEqual(image.size.height, 10)
	}

	func testLoadInvalidDataThrows() {
		let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
		XCTAssertThrowsError(try SwiftarrImage(data: garbage)) { error in
			XCTAssertTrue(error is ImageError)
		}
	}

	func testLoadEmptyDataThrows() {
		XCTAssertThrowsError(try SwiftarrImage(data: Data())) { error in
			XCTAssertTrue(error is ImageError)
		}
	}

	// MARK: - Alpha Detection

	func testHasAlpha_JPEG() throws {
		let jpegData = try makeTestJPEG()
		let image = try SwiftarrImage(data: jpegData)
		XCTAssertFalse(image.hasAlpha)
	}

	func testHasAlpha_PNGWithAlpha() throws {
		let pngData = try makeTestPNGWithAlpha()
		let image = try SwiftarrImage(data: pngData)
		XCTAssertTrue(image.hasAlpha)
	}

	// MARK: - Resize

	func testResizeToWidthAndHeight() throws {
		let jpegData = try makeTestJPEG(width: 100, height: 100)
		let image = try SwiftarrImage(data: jpegData)
		let resized = image.resizedTo(width: 50, height: 50)
		XCTAssertNotNil(resized)
		XCTAssertEqual(resized!.size.width, 50)
		XCTAssertEqual(resized!.size.height, 50)
	}

	func testResizeToWidth() throws {
		let jpegData = try makeTestJPEG(width: 100, height: 200)
		let image = try SwiftarrImage(data: jpegData)
		let resized = image.resizedTo(width: 50)
		XCTAssertNotNil(resized)
		XCTAssertEqual(resized!.size.width, 50)
		XCTAssertEqual(resized!.size.height, 100)
	}

	func testResizeToHeight() throws {
		let jpegData = try makeTestJPEG(width: 200, height: 100)
		let image = try SwiftarrImage(data: jpegData)
		let resized = image.resizedTo(height: 50)
		XCTAssertNotNil(resized)
		XCTAssertEqual(resized!.size.height, 50)
		XCTAssertEqual(resized!.size.width, 100)
	}

	// MARK: - Crop

	func testCrop() throws {
		let jpegData = try makeTestJPEG(width: 100, height: 100)
		let image = try SwiftarrImage(data: jpegData)
		let rect = Rectangle(x: 10, y: 10, width: 50, height: 50)
		let cropped = image.cropped(to: rect)
		XCTAssertNotNil(cropped)
		XCTAssertEqual(cropped!.size.width, 50)
		XCTAssertEqual(cropped!.size.height, 50)
	}

	// MARK: - Flatten

	func testFlattenRemovesAlpha() throws {
		let pngData = try makeTestPNGWithAlpha()
		let image = try SwiftarrImage(data: pngData)
		XCTAssertTrue(image.hasAlpha)
		let flattened = image.flattened()
		XCTAssertNotNil(flattened)
		XCTAssertFalse(flattened!.hasAlpha)
	}

	func testFlattenOnOpaqueImageReturnsNil() throws {
		let jpegData = try makeTestJPEG()
		let image = try SwiftarrImage(data: jpegData)
		XCTAssertFalse(image.hasAlpha)
		let flattened = image.flattened()
		XCTAssertNil(flattened)
	}

	// MARK: - Export

	func testExportAsJPEG() throws {
		let jpegData = try makeTestJPEG()
		let image = try SwiftarrImage(data: jpegData)
		let exported = try image.exportAsJPEG(quality: 85)
		XCTAssertGreaterThan(exported.count, 0)
		XCTAssertEqual(exported[0], 0xFF)
		XCTAssertEqual(exported[1], 0xD8)
	}

	func testExportAsPNG() throws {
		let jpegData = try makeTestJPEG()
		let image = try SwiftarrImage(data: jpegData)
		let exported = try image.exportAsPNG()
		XCTAssertGreaterThan(exported.count, 0)
		XCTAssertEqual(exported[0], 0x89)
		XCTAssertEqual(exported[1], 0x50)
		XCTAssertEqual(exported[2], 0x4E)
		XCTAssertEqual(exported[3], 0x47)
	}

	// MARK: - Round Trip

	func testRoundTripPreservesDimensions() throws {
		let jpegData = try makeTestJPEG(width: 77, height: 33)
		let image = try SwiftarrImage(data: jpegData)
		let exported = try image.exportAsJPEG()
		let reloaded = try SwiftarrImage(data: exported)
		XCTAssertEqual(reloaded.size.width, 77)
		XCTAssertEqual(reloaded.size.height, 33)
	}

	// MARK: - Raw Pixel Init

	func testInitFromPixels() throws {
		let pixels = [UInt8](repeating: 128, count: 5 * 5 * 3)
		let image = try SwiftarrImage(width: 5, height: 5, pixels: pixels)
		XCTAssertEqual(image.size.width, 5)
		XCTAssertEqual(image.size.height, 5)
		XCTAssertFalse(image.hasAlpha)
	}

	func testInitFromPixelsAndResize() throws {
		let pixels = [UInt8](repeating: 128, count: 5 * 5 * 3)
		let image = try SwiftarrImage(width: 5, height: 5, pixels: pixels)
		let resized = image.resizedTo(width: 40, height: 40)
		XCTAssertNotNil(resized)
		XCTAssertEqual(resized!.size.width, 40)
		XCTAssertEqual(resized!.size.height, 40)
		let pngData = try resized!.exportAsPNG()
		XCTAssertGreaterThan(pngData.count, 0)
	}

	// MARK: - HEIC/AVIF/JXL Format Loading

	/// Path to test fixture files relative to the test source file.
	private func fixtureData(_ filename: String) throws -> Data {
		let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.appendingPathComponent("Fixtures")
		let path = fixturesDir.appendingPathComponent(filename)
		return try Data(contentsOf: path)
	}

	func testLoadHEIC() throws {
		let data = try fixtureData("test.heic")
		let image = try SwiftarrImage(data: data)
		XCTAssertEqual(image.size.width, 10)
		XCTAssertEqual(image.size.height, 10)
	}

	func testLoadAVIF() throws {
		let data = try fixtureData("test.avif")
		let image = try SwiftarrImage(data: data)
		XCTAssertEqual(image.size.width, 10)
		XCTAssertEqual(image.size.height, 10)
	}

	func testLoadJXL() throws {
		let data = try fixtureData("test.jxl")
		let image = try SwiftarrImage(data: data)
		XCTAssertEqual(image.size.width, 10)
		XCTAssertEqual(image.size.height, 10)
	}

	func testLoadHEICAndExportAsJPEG() throws {
		let data = try fixtureData("test.heic")
		let image = try SwiftarrImage(data: data)
		let jpegData = try image.exportAsJPEG(quality: 90)
		XCTAssertGreaterThan(jpegData.count, 0)
		XCTAssertEqual(jpegData[0], 0xFF)
		XCTAssertEqual(jpegData[1], 0xD8)
	}

	// MARK: - Pipeline: loadImageFromData

	func testLoadImageFromData_FlattensAlpha() throws {
		let pngData = try makeTestPNGWithAlpha()
		// Verify the raw PNG has alpha
		let rawImage = try SwiftarrImage(data: pngData)
		XCTAssertTrue(rawImage.hasAlpha)

		// loadImageFromData should flatten it
		let processed = try loadImageFromData(pngData)
		XCTAssertFalse(processed.hasAlpha)
	}

	func testLoadImageFromData_OpaqueImageUnchanged() throws {
		let jpegData = try makeTestJPEG()
		let processed = try loadImageFromData(jpegData)
		XCTAssertFalse(processed.hasAlpha)
		XCTAssertEqual(processed.size.width, 10)
		XCTAssertEqual(processed.size.height, 10)
	}

	func testLoadImageFromData_HEICWorks() throws {
		let data = try fixtureData("test.heic")
		let processed = try loadImageFromData(data)
		XCTAssertEqual(processed.size.width, 10)
		XCTAssertEqual(processed.size.height, 10)
	}

	func testLoadImageFromData_InvalidDataThrows() {
		let garbage = Data([0xDE, 0xAD, 0xBE, 0xEF])
		XCTAssertThrowsError(try loadImageFromData(garbage))
	}

	// MARK: - Identicon

	func testIdenticonDeterministic() throws {
		let controller = ImageController()
		let uuid = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
		let data1 = try controller.generateIdenticon(for: uuid)
		let data2 = try controller.generateIdenticon(for: uuid)
		XCTAssertEqual(data1, data2, "Same UUID should produce identical identicon data")
	}

	func testIdenticonDifferentForDifferentUUIDs() throws {
		let controller = ImageController()
		let uuid1 = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
		let uuid2 = UUID(uuidString: "ABCDEF01-2345-6789-ABCD-EF0123456789")!
		let data1 = try controller.generateIdenticon(for: uuid1)
		let data2 = try controller.generateIdenticon(for: uuid2)
		XCTAssertNotEqual(data1, data2, "Different UUIDs should produce different identicons")
	}

	func testIdenticonIsPNG() throws {
		let controller = ImageController()
		let uuid = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
		let data = try controller.generateIdenticon(for: uuid)
		XCTAssertGreaterThan(data.count, 0)
		// PNG magic bytes
		XCTAssertEqual(data[0], 0x89)
		XCTAssertEqual(data[1], 0x50)
		XCTAssertEqual(data[2], 0x4E)
		XCTAssertEqual(data[3], 0x47)
	}

	func testIdenticonIs40x40() throws {
		let controller = ImageController()
		let uuid = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
		let data = try controller.generateIdenticon(for: uuid)
		let image = try SwiftarrImage(data: data)
		XCTAssertEqual(image.size.width, 40)
		XCTAssertEqual(image.size.height, 40)
	}

	// MARK: - Resize Aspect Ratio Preservation

	func testResizePreservesAspectRatio_Landscape() throws {
		let jpegData = try makeTestJPEG(width: 200, height: 100)
		let image = try SwiftarrImage(data: jpegData)
		// Resize by width — height should be proportional
		let resized = image.resizedTo(width: 100)
		XCTAssertNotNil(resized)
		XCTAssertEqual(resized!.size.width, 100)
		XCTAssertEqual(resized!.size.height, 50)
	}

	func testResizePreservesAspectRatio_Portrait() throws {
		let jpegData = try makeTestJPEG(width: 100, height: 300)
		let image = try SwiftarrImage(data: jpegData)
		// Resize by height — width should be proportional
		let resized = image.resizedTo(height: 100)
		XCTAssertNotNil(resized)
		// 100:300 ratio → width dominates at 33px, height scales to 99
		// (vips fits within the bounding box, so rounding may lose 1px)
		XCTAssertEqual(resized!.size.width, 33)
		XCTAssertTrue(resized!.size.height >= 99 && resized!.size.height <= 100)
	}

	// MARK: - Larger Image Simulation

	func testProcessLargerImage() throws {
		// Simulate a 500x500 "photo" — bigger than identicon, exercises the resize path
		let jpegData = try makeTestJPEG(width: 500, height: 500)
		let image = try SwiftarrImage(data: jpegData)
		XCTAssertEqual(image.size.width, 500)

		// Simulate the thumbnail creation path (resize to height 100)
		let thumb = image.resizedTo(height: 100)
		XCTAssertNotNil(thumb)
		XCTAssertEqual(thumb!.size.height, 100)
		XCTAssertEqual(thumb!.size.width, 100)

		// Export and verify it round-trips
		let thumbData = try thumb!.exportAsJPEG(quality: 90)
		let reloaded = try SwiftarrImage(data: thumbData)
		XCTAssertEqual(reloaded.size.width, 100)
		XCTAssertEqual(reloaded.size.height, 100)
	}

	func testCropThenResize() throws {
		// Simulate the user profile pipeline: crop to square, then resize
		let jpegData = try makeTestJPEG(width: 300, height: 200)
		let image = try SwiftarrImage(data: jpegData)

		// Crop to center square (200x200)
		let size = min(image.size.width, image.size.height)
		let cropX = (image.size.width - size) / 2
		let rect = Rectangle(x: cropX, y: 0, width: size, height: size)
		let cropped = image.cropped(to: rect)
		XCTAssertNotNil(cropped)
		XCTAssertEqual(cropped!.size.width, 200)
		XCTAssertEqual(cropped!.size.height, 200)

		// Resize down
		let resized = cropped!.resizedTo(width: 100, height: 100)
		XCTAssertNotNil(resized)
		XCTAssertEqual(resized!.size.width, 100)

		// Export as JPEG
		let data = try resized!.exportAsJPEG(quality: 90)
		XCTAssertEqual(data[0], 0xFF)
		XCTAssertEqual(data[1], 0xD8)
	}

	// MARK: - Realistic Image Sizes

	func testLargeJPEG_LoadResizeExport() throws {
		// Simulate a 3000x2000 photo (typical phone camera output)
		let jpegData = try makeTestJPEG(width: 3000, height: 2000)
		let image = try SwiftarrImage(data: jpegData)
		XCTAssertEqual(image.size.width, 3000)
		XCTAssertEqual(image.size.height, 2000)

		// Simulate the upload pipeline downscale (>2048 → fit within 2048)
		let resizeAmt = 2048.0 / Double(max(image.size.width, image.size.height))
		let resized = image.resizedTo(
			width: Int(Double(image.size.width) * resizeAmt),
			height: Int(Double(image.size.height) * resizeAmt)
		)
		XCTAssertNotNil(resized)
		XCTAssertLessThanOrEqual(resized!.size.width, 2048)
		XCTAssertLessThanOrEqual(resized!.size.height, 2048)

		// Export and verify round-trip
		let exported = try resized!.exportAsJPEG(quality: 90)
		XCTAssertGreaterThan(exported.count, 0)
		let reloaded = try SwiftarrImage(data: exported)
		XCTAssertEqual(reloaded.size.width, resized!.size.width)
		XCTAssertEqual(reloaded.size.height, resized!.size.height)
	}

	func testLargeHEIC_FullPipeline() throws {
		// Generate a large HEIC-like image via JPEG (we can't generate HEIC programmatically,
		// but we can test the full pipeline with a large JPEG to verify resize + export works)
		let jpegData = try makeTestJPEG(width: 4032, height: 3024)
		let image = try SwiftarrImage(data: jpegData)
		XCTAssertEqual(image.size.width, 4032)
		XCTAssertEqual(image.size.height, 3024)

		// Flatten (no alpha on JPEG, should return nil)
		XCTAssertNil(image.flattened())

		// Resize
		let resizeAmt = 2048.0 / 4032.0
		let resized = image.resizedTo(
			width: Int(4032.0 * resizeAmt),
			height: Int(3024.0 * resizeAmt)
		)
		XCTAssertNotNil(resized)

		// Thumbnail
		let thumb = resized!.resizedTo(height: 100)
		XCTAssertNotNil(thumb)
		XCTAssertEqual(thumb!.size.height, 100)

		// Both export cleanly
		let fullData = try resized!.exportAsJPEG(quality: 90)
		let thumbData = try thumb!.exportAsJPEG(quality: 90)
		XCTAssertGreaterThan(fullData.count, 0)
		XCTAssertGreaterThan(thumbData.count, 0)
	}

	func testProfileAvatar_CropAndResize() throws {
		// Simulate a portrait photo cropped to square for profile avatar
		let jpegData = try makeTestJPEG(width: 1200, height: 1600)
		let image = try SwiftarrImage(data: jpegData)

		// Crop to center square (same logic as processImage)
		let size = min(image.size.width, image.size.height)  // 1200
		let cropY = (image.size.height - size) / 2  // 200
		let rect = Rectangle(x: 0, y: cropY, width: size, height: size)
		let cropped = image.cropped(to: rect)
		XCTAssertNotNil(cropped)
		XCTAssertEqual(cropped!.size.width, 1200)
		XCTAssertEqual(cropped!.size.height, 1200)

		// Export as JPEG
		let exported = try cropped!.exportAsJPEG(quality: 90)
		XCTAssertGreaterThan(exported.count, 0)
	}
}
