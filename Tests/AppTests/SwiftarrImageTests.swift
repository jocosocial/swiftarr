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
            pixels[i] = 255     // R
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
}
