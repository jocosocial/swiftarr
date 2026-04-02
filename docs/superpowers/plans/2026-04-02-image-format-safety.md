# Image Format Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent server segfaults from unsupported image uploads and add HEIC/AVIF/JXL support via magic byte detection + CLI-based conversion.

**Architecture:** New `ImageFormatDetector` identifies the format from file header bytes. New `ImageFormatConverter` shells out to `heif-convert`/`djxl` for non-GD formats. Both are wired into the existing `loadImageFromData()` in `ImageHandler.swift`, so all upload endpoints benefit automatically.

**Tech Stack:** Swift 6.2, Vapor 4, libgd, Foundation.Process, heif-convert (libheif), djxl (libjxl)

**Spec:** `docs/superpowers/specs/2026-04-02-image-format-safety-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `Sources/swiftarr/Image/ImageFormatDetector.swift` | Magic byte detection — bytes in, format enum out |
| Create | `Sources/swiftarr/Image/ImageFormatConverter.swift` | CLI-based format conversion to JPEG |
| Modify | `Sources/swiftarr/Protocols/ImageHandler.swift` | Wire detection + conversion into `loadImageFromData()` |
| Modify | `scripts/init-prereqs.sh` | Add `libheif-examples libjxl-tools` to apt install |
| Create | `Tests/AppTests/ImageFormatDetectorTests.swift` | Unit tests for format detection |
| Create | `Tests/AppTests/ImageFormatConverterTests.swift` | Unit tests for format conversion |

---

### Task 1: ImageFormatDetector — Tests

**Files:**
- Create: `Tests/AppTests/ImageFormatDetectorTests.swift`

- [ ] **Step 1: Write failing tests for all supported format detections**

```swift
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
		// RIFF....WEBP
		var data = Data([0x52, 0x49, 0x46, 0x46])
		data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // file size (don't care)
		data.append(contentsOf: [0x57, 0x45, 0x42, 0x50])  // WEBP
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
		// ftyp box: 4-byte size + "ftyp" + brand "heic"
		var data = Data([0x00, 0x00, 0x00, 0x18])  // box size
		data.append("ftypheic".data(using: .ascii)!)
		data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // minor version
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
		// 0xFF 0x0B is close to JXL (0xFF 0x0A) but not it
		let data = Data([0xFF, 0x0B])
		XCTAssertEqual(ImageFormatDetector.detect(data), .unknown)
	}

	func testDetectWebP_IncompleteRIFF() {
		// RIFF header but not enough bytes for WEBP check
		let data = Data([0x52, 0x49, 0x46, 0x46, 0x00, 0x00])
		XCTAssertEqual(ImageFormatDetector.detect(data), .unknown)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ImageFormatDetectorTests 2>&1 | tail -5`
Expected: Build error — `ImageFormatDetector` not defined.

- [ ] **Step 3: Commit test file**

```bash
git add Tests/AppTests/ImageFormatDetectorTests.swift
git commit -m "test: add ImageFormatDetector unit tests (red)"
```

---

### Task 2: ImageFormatDetector — Implementation

**Files:**
- Create: `Sources/swiftarr/Image/ImageFormatDetector.swift`

- [ ] **Step 1: Implement the detector**

```swift
// ABOUTME: Identifies image formats by reading magic bytes from file headers.
// ABOUTME: Returns a detected format enum — no dependencies, no side effects.

import Foundation

/// Image formats identified by their magic byte signatures.
enum DetectedImageFormat: Equatable {
	// GD-supported formats (pass directly to GD)
	case jpeg, png, gif, webp, tiff, bmp
	// Convertible via CLI tools (heif-convert, djxl)
	case heic, avif, jxl
	// Not recognized
	case unknown

	/// Maps detected GD-supported formats to the corresponding GD ImportableFormat.
	var gdFormat: ImportableFormat? {
		switch self {
		case .jpeg: return .jpg
		case .png: return .png
		case .gif: return .gif
		case .webp: return .webp
		case .tiff: return .tiff
		case .bmp: return .bmp
		default: return nil
		}
	}

	/// Whether this format needs CLI conversion before GD can process it.
	var needsConversion: Bool {
		switch self {
		case .heic, .avif, .jxl: return true
		default: return false
		}
	}
}

/// Detects image format from file header bytes.
struct ImageFormatDetector {

	/// Detect the image format by examining the first ~12 bytes of the data.
	static func detect(_ data: Data) -> DetectedImageFormat {
		let count = data.count
		guard count >= 2 else { return .unknown }

		let byte0 = data[data.startIndex]
		let byte1 = data[data.startIndex + 1]

		// JPEG: FF D8 FF
		if byte0 == 0xFF && byte1 == 0xD8 {
			if count >= 3 && data[data.startIndex + 2] == 0xFF {
				return .jpeg
			}
		}

		// JXL codestream: FF 0A
		if byte0 == 0xFF && byte1 == 0x0A {
			return .jxl
		}

		// PNG: 89 50 4E 47
		if count >= 4 && byte0 == 0x89 && byte1 == 0x50 {
			if data[data.startIndex + 2] == 0x4E && data[data.startIndex + 3] == 0x47 {
				return .png
			}
		}

		// GIF: 47 49 46 38
		if count >= 4 && byte0 == 0x47 && byte1 == 0x49 {
			if data[data.startIndex + 2] == 0x46 && data[data.startIndex + 3] == 0x38 {
				return .gif
			}
		}

		// RIFF container: could be WebP
		if count >= 12 && byte0 == 0x52 && byte1 == 0x49
			&& data[data.startIndex + 2] == 0x46 && data[data.startIndex + 3] == 0x46
		{
			// Check for WEBP at offset 8
			if data[data.startIndex + 8] == 0x57 && data[data.startIndex + 9] == 0x45
				&& data[data.startIndex + 10] == 0x42 && data[data.startIndex + 11] == 0x50
			{
				return .webp
			}
		}

		// TIFF: II*\0 (little-endian) or MM\0* (big-endian)
		if count >= 4 {
			if byte0 == 0x49 && byte1 == 0x49
				&& data[data.startIndex + 2] == 0x2A && data[data.startIndex + 3] == 0x00
			{
				return .tiff
			}
			if byte0 == 0x4D && byte1 == 0x4D
				&& data[data.startIndex + 2] == 0x00 && data[data.startIndex + 3] == 0x2A
			{
				return .tiff
			}
		}

		// BMP: BM
		if byte0 == 0x42 && byte1 == 0x4D {
			return .bmp
		}

		// ISOBMFF container (HEIC, AVIF): check for "ftyp" at offset 4
		if count >= 12 {
			let ftyp = data[data.startIndex + 4 ..< data.startIndex + 8]
			if ftyp.elementsEqual("ftyp".utf8) {
				let brand = data[data.startIndex + 8 ..< data.startIndex + 12]
				let brandString = String(bytes: brand, encoding: .ascii) ?? ""
				switch brandString {
				case "heic", "heix", "mif1", "msf1":
					return .heic
				case "avif", "avis":
					return .avif
				default:
					break
				}
			}
		}

		// JXL container: 00 00 00 0C 4A 58 4C 20 0D 0A 87 0A
		if count >= 12 {
			let jxlContainer: [UInt8] = [0x00, 0x00, 0x00, 0x0C, 0x4A, 0x58, 0x4C, 0x20, 0x0D, 0x0A, 0x87, 0x0A]
			if data.prefix(12).elementsEqual(jxlContainer) {
				return .jxl
			}
		}

		return .unknown
	}
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter ImageFormatDetectorTests 2>&1 | tail -10`
Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/swiftarr/Image/ImageFormatDetector.swift
git commit -m "feat: add ImageFormatDetector — magic byte format identification"
```

---

### Task 3: ImageFormatConverter — Tests

**Files:**
- Create: `Tests/AppTests/ImageFormatConverterTests.swift`

- [ ] **Step 1: Write failing tests for conversion**

```swift
// ABOUTME: Tests for CLI-based image format conversion.
// ABOUTME: Tests that need converter tools skip gracefully if tools are not installed.

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
		// A real JPEG is complex to construct from bytes. Instead, generate one via GD
		// which we know is available in the test environment.
		let image = GDImage(width: 2, height: 1)!
		return try! image.export(as: .jpg(quality: 90))
	}

	// MARK: - Converter Validation

	func testConvertUnsupportedFormatThrows() {
		// .jpeg is GD-supported, not convertible — should throw
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

		// Generate a minimal HEIC test file using heif-enc if available,
		// otherwise use a fixture file. For now, create a JPEG and test the
		// error path for a valid-looking but non-HEIC file.
		// Real HEIC test fixtures should be added to Tests/AppTests/Resources/
		// This test validates the plumbing works end-to-end.
		// Fixture path relative to the test source file location
		let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.appendingPathComponent("Resources")
		let fixturePath = fixturesDir.appendingPathComponent("test.heic")
		try XCTSkipUnless(FileManager.default.fileExists(atPath: fixturePath.path), "test.heic fixture not found")

		let heicData = try Data(contentsOf: fixturePath)
		let jpegData = try ImageFormatConverter.convertToJPEG(heicData, from: .heic)

		// Verify output is valid JPEG
		XCTAssertGreaterThan(jpegData.count, 0)
		XCTAssertEqual(jpegData[jpegData.startIndex], 0xFF)
		XCTAssertEqual(jpegData[jpegData.startIndex + 1], 0xD8)
		XCTAssertEqual(jpegData[jpegData.startIndex + 2], 0xFF)
	}

	// MARK: - Temp File Cleanup

	func testTempFilesCleanedUp() throws {
		let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("swiftarr-convert")

		// Run a conversion that will fail (garbage data labeled as HEIC)
		_ = try? ImageFormatConverter.convertToJPEG(Data([0x00, 0x01, 0x02]), from: .heic)

		// Check that no files are left behind in the temp directory
		if FileManager.default.fileExists(atPath: tempDir.path) {
			let remaining = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
			XCTAssertEqual(remaining.count, 0, "Temp files not cleaned up: \(remaining)")
		}
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter ImageFormatConverterTests 2>&1 | tail -5`
Expected: Build error — `ImageFormatConverter` not defined.

- [ ] **Step 3: Commit test file**

```bash
git add Tests/AppTests/ImageFormatConverterTests.swift
git commit -m "test: add ImageFormatConverter unit tests (red)"
```

---

### Task 4: ImageFormatConverter — Implementation

**Files:**
- Create: `Sources/swiftarr/Image/ImageFormatConverter.swift`

- [ ] **Step 1: Implement the converter**

```swift
// ABOUTME: Converts image formats that GD cannot handle (HEIC, AVIF, JXL) to JPEG.
// ABOUTME: Shells out to CLI tools (heif-convert, djxl) with temp files and timeout.

import Foundation

/// Errors from image format conversion.
enum ImageConversionError: Error, LocalizedError {
	case notConvertible(DetectedImageFormat)
	case converterNotFound(String)
	case conversionFailed(String)
	case timeout

	var errorDescription: String? {
		switch self {
		case .notConvertible(let format):
			return "\(format) is not a convertible format"
		case .converterNotFound(let tool):
			return "Server does not support this image format — \(tool) is not installed. Please upload JPEG, PNG, GIF, or WebP."
		case .conversionFailed(let reason):
			return "Image conversion failed: \(reason)"
		case .timeout:
			return "Image conversion timed out"
		}
	}
}

/// Converts non-GD image formats to JPEG via CLI tools.
struct ImageFormatConverter {

	private static let timeoutSeconds: TimeInterval = 30
	private static let jpegQuality = 95

	/// Convert image data from a non-GD format to JPEG using a CLI tool.
	/// - Parameters:
	///   - data: The raw image data
	///   - format: The detected format (must be .heic, .avif, or .jxl)
	/// - Returns: JPEG image data
	static func convertToJPEG(_ data: Data, from format: DetectedImageFormat) throws -> Data {
		guard format.needsConversion else {
			throw ImageConversionError.notConvertible(format)
		}

		let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
			.appendingPathComponent("swiftarr-convert")
		try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

		let uuid = UUID().uuidString
		let inputExtension: String
		let toolName: String
		var toolArgs: [String]

		switch format {
		case .heic:
			inputExtension = "heic"
			toolName = "heif-convert"
			toolArgs = []  // filled below
		case .avif:
			inputExtension = "avif"
			toolName = "heif-convert"
			toolArgs = []
		case .jxl:
			inputExtension = "jxl"
			toolName = "djxl"
			toolArgs = []
		default:
			throw ImageConversionError.notConvertible(format)
		}

		let inputPath = tempDir.appendingPathComponent("\(uuid).\(inputExtension)")
		let outputPath = tempDir.appendingPathComponent("\(uuid).jpg")

		// Build the command arguments
		switch format {
		case .heic, .avif:
			// heif-convert input.heic output.jpg -q 95
			toolArgs = [inputPath.path, outputPath.path, "-q", "\(jpegQuality)"]
		case .jxl:
			// djxl input.jxl output.jpg
			toolArgs = [inputPath.path, outputPath.path]
		default:
			break
		}

		defer {
			try? FileManager.default.removeItem(at: inputPath)
			try? FileManager.default.removeItem(at: outputPath)
		}

		// Write input data to temp file
		try data.write(to: inputPath)

		// Find the tool
		let toolURL = findExecutable(toolName)
		guard let executableURL = toolURL else {
			throw ImageConversionError.converterNotFound(toolName)
		}

		// Run the converter
		let process = Process()
		process.executableURL = executableURL
		process.arguments = toolArgs
		process.standardOutput = FileHandle.nullDevice
		let errorPipe = Pipe()
		process.standardError = errorPipe

		try process.run()

		// Timeout handling
		let deadline = DispatchTime.now() + timeoutSeconds
		let group = DispatchGroup()
		group.enter()
		DispatchQueue.global().async {
			process.waitUntilExit()
			group.leave()
		}
		if group.wait(timeout: deadline) == .timedOut {
			process.terminate()
			throw ImageConversionError.timeout
		}

		guard process.terminationStatus == 0 else {
			let stderrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
			let stderr = String(data: stderrData, encoding: .utf8) ?? "unknown error"
			throw ImageConversionError.conversionFailed(stderr.trimmingCharacters(in: .whitespacesAndNewlines))
		}

		// Read the output JPEG
		guard FileManager.default.fileExists(atPath: outputPath.path) else {
			throw ImageConversionError.conversionFailed("Converter produced no output file")
		}

		return try Data(contentsOf: outputPath)
	}

	/// Search PATH for an executable by name.
	private static func findExecutable(_ name: String) -> URL? {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		process.arguments = ["which", name]
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
			process.waitUntilExit()
			guard process.terminationStatus == 0 else { return nil }
			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
			return path.isEmpty ? nil : URL(fileURLWithPath: path)
		} catch {
			return nil
		}
	}
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter ImageFormatConverterTests 2>&1 | tail -10`
Expected: `testConvertUnsupportedFormatThrows` and `testConvertUnknownFormatThrows` PASS. `testConvertHEIC` SKIPPED (unless fixture exists). `testTempFilesCleanedUp` PASS.

- [ ] **Step 3: Commit**

```bash
git add Sources/swiftarr/Image/ImageFormatConverter.swift
git commit -m "feat: add ImageFormatConverter — CLI-based HEIC/AVIF/JXL to JPEG conversion"
```

---

### Task 5: Wire Detection + Conversion into loadImageFromData()

**Files:**
- Modify: `Sources/swiftarr/Protocols/ImageHandler.swift:71-89`

- [ ] **Step 1: Replace the body of `loadImageFromData()`**

Replace the existing `loadImageFromData()` method (lines 71-89) with:

```swift
	/// Loads an image from data and returns the image, its type, and original orientation.
	/// Detects the format via magic bytes before parsing. Converts HEIC/AVIF/JXL to JPEG
	/// via CLI tools if needed. Rejects unknown formats with a descriptive error.
	/// - Parameter data: The image data to load
	/// - Returns: A tuple containing the loaded image, its format type, and original orientation value
	static func loadImageFromData(_ data: Data) throws -> (image: GDImage, type: ImportableFormat, orientation: Int32) {
		let detected = ImageFormatDetector.detect(data)
		let imageData: Data
		let imageType: ImportableFormat

		if let gdFormat = detected.gdFormat {
			// GD can handle this format directly
			imageData = data
			imageType = gdFormat
		} else if detected.needsConversion {
			// Convert non-GD format to JPEG via CLI tool
			imageData = try ImageFormatConverter.convertToJPEG(data, from: detected)
			imageType = .jpg
		} else {
			// Unknown format — try TGA and WBMP as fallback (no reliable magic bytes for these)
			let fallbackTypes: [ImportableFormat] = [.tga, .wbmp]
			var fallbackImage: GDImage?
			var fallbackType: ImportableFormat?
			for type in fallbackTypes {
				fallbackImage = try? GDImage(data: data, as: type)
				if fallbackImage != nil {
					fallbackType = type
					break
				}
			}
			guard let image = fallbackImage, let foundType = fallbackType else {
				throw GDError.invalidImage(
					reason: "Unsupported image format. Supported: JPEG, PNG, GIF, WebP, TIFF, BMP, HEIC, AVIF, JXL"
				)
			}
			let origOrientation = image.internalImage.pointee.polyAllocated
			return (image, foundType, origOrientation)
		}

		// Parse with the identified GD format
		guard let image = try? GDImage(data: imageData, as: imageType) else {
			throw GDError.invalidImage(
				reason: "Failed to parse image data as \(imageType). The file may be corrupted."
			)
		}
		let origOrientation = image.internalImage.pointee.polyAllocated
		return (image, imageType, origOrientation)
	}
```

- [ ] **Step 2: Run the full test suite to verify nothing is broken**

Run: `REDIS_PASSWORD=password SWIFTARR_START_DATE=2024-03-09 DATABASE_PORT=5433 DATABASE_DB=swiftarr-test swift test 2>&1 | tail -20`
Expected: All existing tests PASS plus the new detector and converter tests.

- [ ] **Step 3: Commit**

```bash
git add Sources/swiftarr/Protocols/ImageHandler.swift
git commit -m "feat: wire magic byte detection + format conversion into image upload pipeline

Fixes #52 — unsupported formats now rejected with a clear error instead
of crashing the server. Addresses #535 — HEIC, AVIF, and JXL uploads
are converted to JPEG via CLI tools before GD processing."
```

---

### Task 6: Dockerfile — Add Converter Packages

**Files:**
- Modify: `scripts/init-prereqs.sh:17-19`

- [ ] **Step 1: Add converter packages to apt install**

In `scripts/init-prereqs.sh`, modify the `apt-get install` block to add `libheif-examples` and `libjxl-tools`:

```bash
apt-get install -y \
  curl libatomic1 libicu74 libxml2 gnupg2 \
  libcurl4 libz-dev libbsd0 tzdata libgd3 \
  libheif-examples libjxl-tools
```

- [ ] **Step 2: Verify the Dockerfile builds** (if Docker is available)

Run: `docker build -t swiftarr-test . 2>&1 | tail -10`
Expected: Build completes. If Docker is not available locally, verify the apt package names are correct:

Run: `apt-cache show libheif-examples 2>/dev/null && echo "OK" || echo "Package check requires Ubuntu"`
Run: `apt-cache show libjxl-tools 2>/dev/null && echo "OK" || echo "Package check requires Ubuntu"`

These packages are available on Ubuntu 24.04 (Noble).

- [ ] **Step 3: Commit**

```bash
git add scripts/init-prereqs.sh
git commit -m "infra: add heif-convert and djxl to Docker runtime image

Required for server-side HEIC/AVIF/JXL to JPEG conversion (#535)."
```

---

### Task 7: Test Fixtures + Integration Smoke Test

**Files:**
- Create: test fixture images (generated, not committed as binaries)
- Modify: `Tests/AppTests/ImageFormatConverterTests.swift` — add fixture generation

- [ ] **Step 1: Add a helper to generate test fixtures from available tools**

Add to `ImageFormatConverterTests.swift`:

```swift
	// MARK: - AVIF Conversion

	func testConvertAVIF() throws {
		try XCTSkipUnless(toolAvailable("heif-convert"), "heif-convert not installed")

		let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.appendingPathComponent("Resources")
		let fixturePath = fixturesDir.appendingPathComponent("test.avif")
		try XCTSkipUnless(FileManager.default.fileExists(atPath: fixturePath.path), "test.avif fixture not found")

		let avifData = try Data(contentsOf: fixturePath)
		let jpegData = try ImageFormatConverter.convertToJPEG(avifData, from: .avif)

		XCTAssertGreaterThan(jpegData.count, 0)
		XCTAssertEqual(jpegData[jpegData.startIndex], 0xFF)
		XCTAssertEqual(jpegData[jpegData.startIndex + 1], 0xD8)
	}

	// MARK: - JXL Conversion

	func testConvertJXL() throws {
		try XCTSkipUnless(toolAvailable("djxl"), "djxl not installed")

		let fixturesDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
			.appendingPathComponent("Resources")
		let fixturePath = fixturesDir.appendingPathComponent("test.jxl")
		try XCTSkipUnless(FileManager.default.fileExists(atPath: fixturePath.path), "test.jxl fixture not found")

		let jxlData = try Data(contentsOf: fixturePath)
		let jpegData = try ImageFormatConverter.convertToJPEG(jxlData, from: .jxl)

		XCTAssertGreaterThan(jpegData.count, 0)
		XCTAssertEqual(jpegData[jpegData.startIndex], 0xFF)
		XCTAssertEqual(jpegData[jpegData.startIndex + 1], 0xD8)
	}
```

- [ ] **Step 2: Generate test fixture files using CLI tools** (if available)

Run these on macOS with the tools installed to create minimal test images:

```bash
# Create a 2x2 red JPEG as source
convert -size 2x2 xc:red /tmp/test-source.jpg 2>/dev/null || \
  python3 -c "
from PIL import Image
img = Image.new('RGB', (2, 2), color='red')
img.save('/tmp/test-source.jpg')
"

# Convert to HEIC (if heif-enc available)
heif-enc /tmp/test-source.jpg -o Tests/AppTests/Resources/test.heic -q 90 2>/dev/null || echo "heif-enc not available, skip HEIC fixture"

# Convert to AVIF (if heif-enc available with AVIF)
heif-enc /tmp/test-source.jpg -o Tests/AppTests/Resources/test.avif -A -q 90 2>/dev/null || echo "heif-enc AVIF not available, skip AVIF fixture"

# Convert to JXL (if cjxl available)
cjxl /tmp/test-source.jpg Tests/AppTests/Resources/test.jxl -q 90 2>/dev/null || echo "cjxl not available, skip JXL fixture"
```

If the encoder tools aren't available, the tests will skip gracefully via `XCTSkipUnless`. Fixture files can be generated in CI or manually added later.

- [ ] **Step 3: Run the full test suite**

Run: `REDIS_PASSWORD=password SWIFTARR_START_DATE=2024-03-09 DATABASE_PORT=5433 DATABASE_DB=swiftarr-test swift test 2>&1 | tail -20`
Expected: All tests PASS (conversion tests may SKIP if tools/fixtures not available).

- [ ] **Step 4: Commit**

```bash
git add Tests/AppTests/ImageFormatConverterTests.swift
git add Tests/AppTests/Resources/test.heic Tests/AppTests/Resources/test.avif Tests/AppTests/Resources/test.jxl 2>/dev/null
git commit -m "test: add AVIF/JXL conversion tests and fixture generation"
```

---

### Task 8: Final Verification + PR Prep

**Files:**
- No new files. Verification only.

- [ ] **Step 1: Run the complete test suite one final time**

Run: `REDIS_PASSWORD=password SWIFTARR_START_DATE=2024-03-09 DATABASE_PORT=5433 DATABASE_DB=swiftarr-test swift test 2>&1 | tail -30`
Expected: All tests PASS.

- [ ] **Step 2: Run swift-format**

Run: `swift-format format --recursive Sources/swiftarr/Image/ImageFormatDetector.swift Sources/swiftarr/Image/ImageFormatConverter.swift Sources/swiftarr/Protocols/ImageHandler.swift Tests/AppTests/ImageFormatDetectorTests.swift Tests/AppTests/ImageFormatConverterTests.swift --in-place`
Then: `git diff` — if any formatting changes, commit them:

```bash
git add -u
git commit -m "style: apply swift-format to new image format files"
```

- [ ] **Step 3: Review the full diff for the PR**

Run: `git log --oneline master..HEAD` to see all commits.
Run: `git diff master --stat` to see all changed files.

Verify:
- Only expected files are changed
- No debug code left in
- No hardcoded paths or credentials
- ABOUTME comments on new files

- [ ] **Step 4: Push to fork and create PR**

```bash
git push fork HEAD:feat/image-format-safety
```

Create PR targeting `jocosocial/swiftarr:master` with title:
`feat: Image format safety — magic byte validation + HEIC/AVIF/JXL support`

PR body should reference both issues: `Fixes #52, addresses #535`.
