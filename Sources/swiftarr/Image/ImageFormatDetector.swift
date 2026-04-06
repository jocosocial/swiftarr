// Identifies image formats by reading magic bytes from file headers.
// Returns a detected format enum — no dependencies, no side effects.

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
