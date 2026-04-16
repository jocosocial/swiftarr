// ABOUTME: Swift wrapper around libvips image operations for the upload pipeline.
// ABOUTME: Manages a VipsImage pointer with load, resize, crop, flatten, and export operations.

import Foundation
import CvipsShim

/// Image wrapper backed by libvips. Manages a VipsImage pointer with automatic cleanup.
/// Operations return new instances — vips images are immutable.
public class SwiftarrImage {
	/// The underlying libvips image pointer.
	private var vipsImage: UnsafeMutablePointer<VipsImage>

	/// Image dimensions.
	public var size: Size {
		let w = vips_image_get_width(vipsImage)
		let h = vips_image_get_height(vipsImage)
		return Size(width: Int(w), height: Int(h))
	}

	/// Whether the image has an alpha channel.
	public var hasAlpha: Bool {
		return vips_image_hasalpha(vipsImage) != 0
	}

	/// One-time libvips initialization. Call once at app startup (e.g. in configure.swift).
	public static func initializeVips() {
		let result = swiftarr_vips_init()
		precondition(result == 0, "Failed to initialize libvips: \(String(cString: vips_error_buffer()))")
	}

	/// Load an image from a data buffer. Auto-detects format and auto-rotates per EXIF.
	/// - Parameter data: Raw image bytes (JPEG, PNG, GIF, WebP, TIFF, BMP, HEIC, AVIF, JXL)
	/// - Throws: `ImageError.invalidImage` if the data can't be parsed
	public init(data: Data) throws {
		guard !data.isEmpty else {
			throw ImageError.invalidImage(reason: "Image data is empty")
		}

		let loaded: UnsafeMutablePointer<VipsImage>? = data.withUnsafeBytes { rawBuffer in
			guard let baseAddress = rawBuffer.baseAddress else { return nil }
			return swiftarr_vips_load_buffer(baseAddress, rawBuffer.count)
		}
		guard let image = loaded else {
			let errorMsg = String(cString: vips_error_buffer())
			vips_error_clear()
			throw ImageError.invalidImage(
				reason: "Failed to load image: \(errorMsg)"
			)
		}

		// Auto-rotate based on EXIF orientation
		if let rotated = swiftarr_vips_autorot(image) {
			g_object_unref(image)
			self.vipsImage = rotated
		} else {
			self.vipsImage = image
		}
	}

	/// Create an image from raw pixel data (e.g. for identicon/QR code generation).
	/// - Parameters:
	///   - width: Image width in pixels
	///   - height: Image height in pixels
	///   - pixels: Raw pixel data, must be exactly width * height * bands bytes
	///   - bands: Number of color bands (3 for RGB, 4 for RGBA). Defaults to 3.
	public init(width: Int, height: Int, pixels: [UInt8], bands: Int = 3) throws {
		guard pixels.count == width * height * bands else {
			throw ImageError.invalidImage(
				reason: "Pixel buffer size \(pixels.count) doesn't match \(width)x\(height)x\(bands) = \(width * height * bands)"
			)
		}

		// vips_image_new_from_memory does NOT copy the data — it just references it.
		// We need to copy into the image to avoid dangling pointer issues.
		guard let memImage = pixels.withUnsafeBufferPointer({ buf in
			swiftarr_vips_image_new_from_memory(buf.baseAddress, buf.count, Int32(width), Int32(height), Int32(bands))
		}) else {
			throw ImageError.invalidImage(reason: "Failed to create image from pixel data")
		}

		// Force a copy so the image owns its pixel data (the array will go out of scope)
		var copyOut: UnsafeMutablePointer<VipsImage>?
		if swiftarr_vips_copy(memImage, &copyOut) != 0 || copyOut == nil {
			g_object_unref(memImage)
			throw ImageError.invalidImage(reason: "Failed to copy pixel data into image")
		}
		g_object_unref(memImage)
		self.vipsImage = copyOut!
	}

	/// Internal init from an already-owned VipsImage pointer.
	private init(vipsImage: UnsafeMutablePointer<VipsImage>) {
		self.vipsImage = vipsImage
	}

	// MARK: - Operations

	/// Resize to exact width and height.
	public func resizedTo(width: Int, height: Int) -> SwiftarrImage? {
		guard let result = swiftarr_vips_thumbnail(vipsImage, Int32(width), Int32(height)) else {
			return nil
		}
		return SwiftarrImage(vipsImage: result)
	}

	/// Resize to exact width and height using nearest-neighbor interpolation.
	/// Produces crisp pixel-art scaling — use for QR codes and identicons.
	public func resizedToNearest(width: Int, height: Int) -> SwiftarrImage? {
		guard let result = swiftarr_vips_resize_nearest(vipsImage, Int32(width), Int32(height)) else {
			return nil
		}
		return SwiftarrImage(vipsImage: result)
	}

	/// Resize to a target width, preserving aspect ratio.
	public func resizedTo(width: Int) -> SwiftarrImage? {
		let currentSize = size
		let scale = Double(width) / Double(currentSize.width)
		let newHeight = Int(Double(currentSize.height) * scale)
		return resizedTo(width: width, height: newHeight)
	}

	/// Resize to a target height, preserving aspect ratio.
	public func resizedTo(height: Int) -> SwiftarrImage? {
		let currentSize = size
		let scale = Double(height) / Double(currentSize.height)
		let newWidth = Int(Double(currentSize.width) * scale)
		return resizedTo(width: newWidth, height: height)
	}

	/// Crop a rectangular region from the image.
	public func cropped(to rect: Rectangle) -> SwiftarrImage? {
		guard let result = swiftarr_vips_crop(vipsImage,
			Int32(rect.point.x), Int32(rect.point.y),
			Int32(rect.size.width), Int32(rect.size.height)) else {
			return nil
		}
		return SwiftarrImage(vipsImage: result)
	}

	/// Flatten alpha channel onto a solid background color.
	/// Returns nil if the image has no alpha channel.
	public func flattened(background: Color = .white) -> SwiftarrImage? {
		guard hasAlpha else { return nil }
		let r = background.redComponent * 255.0
		let g = background.greenComponent * 255.0
		let b = background.blueComponent * 255.0
		guard let result = swiftarr_vips_flatten(vipsImage, r, g, b) else {
			return nil
		}
		return SwiftarrImage(vipsImage: result)
	}

	// MARK: - Export

	/// Export as JPEG data with the given quality (0-100).
	public func exportAsJPEG(quality: Int = 90) throws -> Data {
		var outLen: Int = 0
		guard let buf = swiftarr_vips_jpegsave_buffer(vipsImage, Int32(quality), &outLen) else {
			defer { vips_error_clear() }
			let errorMsg = String(cString: vips_error_buffer())
			throw ImageError.invalidImage(reason: "JPEG export failed: \(errorMsg)")
		}
		return Data(bytesNoCopy: buf, count: outLen, deallocator: .custom({ ptr, _ in g_free(ptr) }))
	}

	/// Export as PNG data.
	public func exportAsPNG() throws -> Data {
		var outLen: Int = 0
		guard let buf = swiftarr_vips_pngsave_buffer(vipsImage, &outLen) else {
			defer { vips_error_clear() }
			let errorMsg = String(cString: vips_error_buffer())
			throw ImageError.invalidImage(reason: "PNG export failed: \(errorMsg)")
		}
		return Data(bytesNoCopy: buf, count: outLen, deallocator: .custom({ ptr, _ in g_free(ptr) }))
	}

	deinit {
		g_object_unref(vipsImage)
	}
}
