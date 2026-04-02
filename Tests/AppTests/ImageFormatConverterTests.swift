import Testing
import XCTVapor

@testable import swiftarr

class ImageFormatConverterTests: XCTestCase {

	// MARK: - Helpers

	/// Check if a CLI tool is available on this system.
	private func toolAvailable(_ name: String) -> Bool {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["which", name]
		process.standardOutput = FileHandle.nullDevice
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
			process.waitUntilExit()
			return process.terminationStatus == 0
		} catch {
			return false
		}
	}

	/// Create a minimal valid JPEG (smallest possible: 2x1 pixel).
	private func minimalJPEG() -> Data {
		let image = GDImage(width: 2, height: 1)!
		return try! image.export(as: .jpg(quality: 90))
	}

	// MARK: - Converter Validation

	func testConvertUnsupportedFormatThrows() {
		let jpegData = minimalJPEG()
		XCTAssertThrowsError(try ImageFormatConverter.convertToJPEG(jpegData, from: .jpeg)) { error in
			XCTAssertTrue("\(error)".contains("not a convertible format"))
		}
	}

	func testConvertUnknownFormatThrows() {
		let data = Data([0xDE, 0xAD, 0xBE, 0xEF])
		XCTAssertThrowsError(try ImageFormatConverter.convertToJPEG(data, from: .unknown)) { error in
			XCTAssertTrue("\(error)".contains("not a convertible format"))
		}
	}

	// MARK: - HEIC Conversion

	func testConvertHEIC() throws {
		try XCTSkipUnless(toolAvailable("heif-convert"), "heif-convert not installed")

		let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.appendingPathComponent("Resources")
		let fixturePath = fixturesDir.appendingPathComponent("test.heic")
		try XCTSkipUnless(FileManager.default.fileExists(atPath: fixturePath.path), "test.heic fixture not found")

		let heicData = try Data(contentsOf: fixturePath)
		let jpegData = try ImageFormatConverter.convertToJPEG(heicData, from: .heic)

		XCTAssertGreaterThan(jpegData.count, 0)
		XCTAssertEqual(jpegData[jpegData.startIndex], 0xFF)
		XCTAssertEqual(jpegData[jpegData.startIndex + 1], 0xD8)
		XCTAssertEqual(jpegData[jpegData.startIndex + 2], 0xFF)
	}

	// MARK: - Temp File Cleanup

	func testTempFilesCleanedUp() throws {
		let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("swiftarr-convert")

		_ = try? ImageFormatConverter.convertToJPEG(Data([0x00, 0x01, 0x02]), from: .heic)

		if FileManager.default.fileExists(atPath: tempDir.path) {
			let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
			XCTAssertEqual(remaining.count, 0, "Temp files not cleaned up: \(remaining)")
		}
	}
}
