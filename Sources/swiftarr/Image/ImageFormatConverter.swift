// Converts image formats that GD cannot handle (HEIC, AVIF, JXL) to JPEG.
// Shells out to CLI tools (heif-convert, djxl) with temp files and timeout.

import Foundation

/// Errors from image format conversion.
enum ImageConversionError: Error, LocalizedError, CustomStringConvertible {
	case notConvertible(DetectedImageFormat)
	case converterNotFound(String)
	case conversionFailed(String)
	case timeout

	var description: String { errorDescription ?? "unknown error" }

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
			toolArgs = []
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

		switch format {
		case .heic, .avif:
			toolArgs = [inputPath.path, outputPath.path, "-q", "\(jpegQuality)"]
		case .jxl:
			toolArgs = [inputPath.path, outputPath.path]
		default:
			break
		}

		defer {
			try? FileManager.default.removeItem(at: inputPath)
			try? FileManager.default.removeItem(at: outputPath)
		}

		try data.write(to: inputPath)

		let toolURL = findExecutable(toolName)
		guard let executableURL = toolURL else {
			throw ImageConversionError.converterNotFound(toolName)
		}

		let process = Process()
		process.executableURL = executableURL
		process.arguments = toolArgs
		process.standardOutput = FileHandle.nullDevice
		let errorPipe = Pipe()
		process.standardError = errorPipe

		try process.run()

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
