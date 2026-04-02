import Testing
import XCTVapor

@testable import swiftarr

class ImageFormatDetectorTests: XCTestCase {

	// MARK: - GD-Supported Formats

	func testDetectJPEG() {
		let data = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
		XCTAssertEqual(ImageFormatDetector.detect(data), .jpeg)
	}

	func testDetectPNG() {
		let data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
		XCTAssertEqual(ImageFormatDetector.detect(data), .png)
	}

	func testDetectGIF87a() {
		let data = Data([0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
		XCTAssertEqual(ImageFormatDetector.detect(data), .gif)
	}

	func testDetectGIF89a() {
		let data = Data([0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
		XCTAssertEqual(ImageFormatDetector.detect(data), .gif)
	}

	func testDetectWebP() {
		var data = Data([0x52, 0x49, 0x46, 0x46])
		data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
		data.append(contentsOf: [0x57, 0x45, 0x42, 0x50])
		XCTAssertEqual(ImageFormatDetector.detect(data), .webp)
	}

	func testDetectTIFF_LittleEndian() {
		let data = Data([0x49, 0x49, 0x2A, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .tiff)
	}

	func testDetectTIFF_BigEndian() {
		let data = Data([0x4D, 0x4D, 0x00, 0x2A])
		XCTAssertEqual(ImageFormatDetector.detect(data), .tiff)
	}

	func testDetectBMP() {
		let data = Data([0x42, 0x4D, 0x00, 0x00, 0x00, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .bmp)
	}

	// MARK: - Convertible Formats

	func testDetectHEIC() {
		var data = Data([0x00, 0x00, 0x00, 0x18])
		data.append("ftypheic".data(using: .ascii)!)
		data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .heic)
	}

	func testDetectHEIF_mif1() {
		var data = Data([0x00, 0x00, 0x00, 0x18])
		data.append("ftypmif1".data(using: .ascii)!)
		data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .heic)
	}

	func testDetectAVIF() {
		var data = Data([0x00, 0x00, 0x00, 0x18])
		data.append("ftypavif".data(using: .ascii)!)
		data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .avif)
	}

	func testDetectAVIF_avis() {
		var data = Data([0x00, 0x00, 0x00, 0x18])
		data.append("ftypavis".data(using: .ascii)!)
		data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .avif)
	}

	func testDetectJXL_Codestream() {
		let data = Data([0xFF, 0x0A, 0x00, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .jxl)
	}

	func testDetectJXL_Container() {
		let data = Data([0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A])
		XCTAssertEqual(ImageFormatDetector.detect(data), .jxl)
	}

	// MARK: - Edge Cases

	func testDetectUnknown_RandomBytes() {
		let data = Data([0xDE, 0xAD, 0xBE, 0xEF, 0xCA, 0xFE])
		XCTAssertEqual(ImageFormatDetector.detect(data), .unknown)
	}

	func testDetectUnknown_EmptyData() {
		let data = Data()
		XCTAssertEqual(ImageFormatDetector.detect(data), .unknown)
	}

	func testDetectUnknown_SingleByte() {
		let data = Data([0xFF])
		XCTAssertEqual(ImageFormatDetector.detect(data), .unknown)
	}

	func testDetectUnknown_TwoBytes_NotJXL() {
		let data = Data([0xFF, 0x0B])
		XCTAssertEqual(ImageFormatDetector.detect(data), .unknown)
	}

	func testDetectWebP_IncompleteRIFF() {
		let data = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .unknown)
	}
}
