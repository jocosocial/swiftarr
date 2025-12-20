import Vapor

/// The type of model for which an `ImageHandler` is processing. This defines the size of the thumbnail produced.
enum ImageUsage: String {
	/// The image is for a `ForumPost`.
	case forumPost
	/// The image is for a `Twarrt`
	case twarrt
	/// The image is for a `FezPost`
	case fezPost
	/// The image is for a `User`'s profile.
	case userProfile
	/// The image is for a `DailyTheme`.
	case dailyTheme
	/// The image is for a `StreamPhoto`.
	case photostream
}

/// Internally, the Image Handler stores images at multiple sizes upon image upload. The exact sizes stored for each sizeGroup
/// may vary based on `ImageUsage`. Request images at roughly the size you need.
enum ImageSizeGroup: String {
	case thumbnail = "thumb"
//	case medium
	case full = "full"
	
	case archive = "archive"
}

/// Returns the file system path for the given image filename. Makes sure all image directories in the path exist.
/// 
/// Currently, this fn returns paths in the form:
///		<WorkingDir>/images/<full/thumb>/<xx>/<filename>.jpg
/// where "xx" is the first 2 characters of the filename.
func getImagePath(for image: String, format: String? = nil, usage: ImageUsage, size: ImageSizeGroup, on req: Request) throws -> URL {
	let baseImagesDirectory = Settings.shared.userImagesRootPath
	// Determine format extension to use. Caller can force a format with the 'format' parameter.
	var imageFormat: String = format ?? URL(fileURLWithPath: image).pathExtension
	if !(["bmp", "gif", "png", "tiff", "webp"].contains(imageFormat)) {
		imageFormat = "jpg"
	}

	// Strip extension and any other gunk off the filename. Eject if two extensions detected (.php.jpg, for example).
	let noFiletype = URL(fileURLWithPath: image).deletingPathExtension()
	if noFiletype.pathExtension.count > 0 {
		throw Abort(.badRequest, reason: "Malformed image filename.")
	}
	let filename = noFiletype.lastPathComponent
	
	if let _ = UUID(filename) {
		let subDirName = String(image.prefix(2))
		let subDir = baseImagesDirectory.appendingPathComponent(size.rawValue)
				.appendingPathComponent(subDirName)
		if !FileManager().fileExists(atPath: subDir.path) {
			try FileManager().createDirectory(atPath: subDir.path, withIntermediateDirectories: true)
		}
		let fileURL = subDir.appendingPathComponent(filename + "." + imageFormat)
		return fileURL
	}
	let staticBase = baseImagesDirectory.appendingPathComponent("staticImages")
	if !FileManager().fileExists(atPath: staticBase.path) {
		try FileManager().createDirectory(atPath: staticBase.path, withIntermediateDirectories: true)
	}
	let fileURL = staticBase.appendingPathComponent(filename + "." + imageFormat)
	return fileURL
}
	
extension APIRouteCollection {
	/// Loads an image from data and returns the image, its type, and original orientation.
	/// - Parameter data: The image data to load
	/// - Returns: A tuple containing the loaded image, its format type, and original orientation value
	static func loadImageFromData(_ data: Data) throws -> (image: GDImage, type: ImportableFormat, orientation: Int32) {
		let imageTypes: [ImportableFormat] = [.jpg, .png, .gif, .webp, .tiff, .bmp, .wbmp]
		var foundType: ImportableFormat? = nil
		var foundImage: GDImage?
		for type in imageTypes {
			foundImage = try? GDImage(data: data, as: type) 
			if foundImage != nil{
				foundType = type
				break
			}
		}
		guard let image = foundImage, let imageType = foundType else {
			throw GDError.invalidImage(reason: "No matching raster formatter for given image found")
		}
		// We've modified SwiftGD to call methods in gd_jpeg_custom.c instead of the gd_jpeg.c in the GD library.
		// The customized .c file has extra code to save the image orientation in the gdImage struct.
		// It's definitely a hack, as polyAllocated is not for this purpose.
		let origOrientation = image.internalImage.pointee.polyAllocated
		return (image, imageType, origOrientation)
	}
	
	/// Creates a thumbnail from an image with proper orientation handling and exports it.
	/// - Parameters:
	///   - image: The source image to create a thumbnail from
	///   - orientation: The original orientation value to preserve
	///   - outputType: The format to export the thumbnail as
	///   - thumbPath: The file path where the thumbnail should be saved
	static func createThumbnail(from image: GDImage, preserving orientation: Int32, as outputType: ImportableFormat, to thumbPath: URL) throws {
		guard let thumbnail = image.resizedTo(height: Settings.shared.imageThumbnailSize) else {
			throw Abort(.internalServerError, reason: "Error generating thumbnail image")
		}
		// Put the orientation value into the polyAllocated field, so that our code in the customized gd_jpeg.c file
		// can store the original image orientation back in the jpeg as exif data.
		thumbnail.internalImage.pointee.polyAllocated = orientation
		let thumbnailData = try thumbnail.export(as: ExportableFormat(outputType))
		try thumbnailData.write(to: thumbPath)
	}

	/// Takes an an array of `ImageUploadData` as input. Some of the input elements may be new image Data that needs procssing;
	/// some of the input elements may refer to already-processed images in our image store. Once all the ImageUploadData elements are processed,
	/// returns a `[String]` containing the filenames where al the images are stored. The use case here is for editing existing content with
	/// image attachments in a way that prevents re-uploading of photos that are already on the server.
	///
	/// - Parameters:
	///   - images: The  images in `ImageUploadData` format. 
	///   - usage: The type of model using the image content.
	///	- req: The incoming `Request`, on which this processing must run.
	/// - Returns: The generated names of the stored files.
	func processImages(_ images: [ImageUploadData], usage: ImageUsage, on req: Request) async throws -> [String] {
		guard images.count <= 4 else {
			throw Abort(.badRequest, reason: "Too many image attachments")
		}
		var savedImageNames = [String?]()
		for image in images {
			if let imageData = image.image {
				savedImageNames.append( try await processImage(data: imageData, usage: usage, on: req))
			}
			else if let filename = image.filename {
				savedImageNames.append(filename)
			}
		}
		return savedImageNames.compactMap { $0 }
	}

	/// Takes an optional image in Data form as input, produces full and thumbnail JPEG vrsions,
	/// places both the thumbnail and full image in their respective directories, and returns the
	/// generated name of the file on success, an empty string otherwise.
	///
	/// - Parameters:
	///   - data: The uploaded image in `Data` format.
	///   - usage: The type of model using the image content.
	///	- req: The incoming `Request`, on which this processing must run.
	/// - Returns: The generated name of the stored file, or nil.
	func processImage(data: Data?, usage: ImageUsage, on req: Request) async throws -> String? {
		guard let data = data, !data.isEmpty else {
			// Not an error, just nothing to do.
			return nil
		}
		
		// For debugging. Saves the uploaded image to the /images directory. Useful when you need to 
		// see the image as it gets uploaded, which may not be the same as the image on the client device,
		// nor is it the same as the image we save. Replace the test with whatever criteria needed to catch
		// the file you're looking for.
//			if false {
//				let p = URL(fileURLWithPath: DirectoryConfiguration.detect().workingDirectory)
//						.appendingPathComponent("images").appendingPathComponent("testfile.jpg")
//				try? data.write(to: p)
//			}
		
		guard data.count < Settings.shared.maxImageSize else {
			let maxMegabytes = Settings.shared.maxImageSize / 1024 * 1024
			throw Abort(.badRequest, reason: "Image too large. Size limit is \(maxMegabytes)MB.")
		}
		return try await req.application.threadPool.runIfActive(eventLoop: req.eventLoop) {
			let (loadedImage, imageType, origOrientation) = try Self.loadImageFromData(data)
			var image = loadedImage
			var outputType = imageType
			
			// Disallow images with an aspect ratio > 10:1, as they're too often malicious (even if by 'malicious' it means
			// "ha ha you have to scroll past this"). Also disallow extremely large widths and heights.
			let sourceSize = image.size
			if sourceSize.width > 10000 || sourceSize.height > 10000 {
				throw GDError.invalidImage(reason: "Image dimensions too large")
			}
			let aspectRatio = Double(sourceSize.width) / Double(sourceSize.height)
			if aspectRatio < 0.1 || aspectRatio > 10.0 {
				throw GDError.invalidImage(reason: "Invalid image aspect ratio. ")
			}
											
			// attempt to crop to square if profile image
			if usage == .userProfile {
				// Disallow animated avatars; make them always be jpegs
				outputType = .jpg
				if image.size.height != image.size.width {
					let size = min(image.size.height, image.size.width)
					var cropOrigin: Point
					if image.size.height > image.size.width {
						cropOrigin = Point(x: 0, y: (image.size.height - size) / 2)
					} else {
						cropOrigin = Point(x: (image.size.width - size) / 2, y: 0)
					}
					let square = Rectangle(point: cropOrigin, size: Size(width: size, height: size))
					if let croppedImage = image.cropped(to: square) {
						image = croppedImage
					}
				}
			}
			
			// Resize if the image is over our size limit. Iphone 11 Pro Max has a scren size of 1242x2688 pixels.
			// A 4:3 portrait photo at 1536x2048 would downscale slightly to 1242x1656. 2K should therefore
			// be a reasonable size limit.
			if image.size.height > 2048 || image.size.width > 2048 {
				outputType = .jpg
				let resizeAmt: Double = 2048.0 / Double(max(image.size.height, image.size.width))
				if let resizedImage = image.resizedTo(width: Int(Double(image.size.width) * resizeAmt), 
						height: Int(Double(image.size.height) * resizeAmt)) {
					image = resizedImage		
				}
			}
			
			// If allowAnimatedImages == false, force jpeg output if the input file could be an animation. 
			// This transocdes the first image of the input file (whether it's an animation or not) into a static jpeg.
			if outputType == .gif || outputType == .webp, !Settings.shared.allowAnimatedImages {
				outputType = .jpg
			}

			// ensure directories exist
			let name = UUID().uuidString
			let outputExtension = ExportableFormat(outputType).fileExtension()
			let fullPath = try getImagePath(for: name, format: outputExtension, usage: usage, size: .full, on: req)
			let thumbPath = try getImagePath(for: name, format: outputExtension, usage: usage, size: .thumbnail, on: req)
			
			// Put the orientation value into the polyAllocated field, so that our code in the customized gd_jpeg.c file
			// can store the original image orientation back in the jpeg as exif data.
			image.internalImage.pointee.polyAllocated = origOrientation
		
			// save full image. If we didn't have to modify the input image, save the original in its original format.
			// Jpeg images always get exported, to ensure the Q value isn't needlessly high.
			let imageData = try outputType == .jpg ? image.export(as: .jpg(quality: 90)) : data
			try imageData.write(to: fullPath)
			
			// save thumbnail
			try Self.createThumbnail(from: image, preserving: origOrientation, as: outputType, to: thumbPath)
			return fullPath.lastPathComponent
		}.get()
	}

	// Generate a thumbnail for the given image (by full path). Currently used in `copyImage`
	// as part of the bulk user import process. Now uses shared helper functions with `processImage`.
	func regenerateThumbnail(for imageSource: URL, on req: Request) async throws {
		let imageName = imageSource.lastPathComponent
		return try await req.application.threadPool.runIfActive(eventLoop: req.eventLoop) {
			let data = try Data(contentsOf: imageSource)
			let (image, imageType, origOrientation) = try Self.loadImageFromData(data)

			let destinationDir = Settings.shared.userImagesRootPath
					.appendingPathComponent(ImageSizeGroup.thumbnail.rawValue)
					.appendingPathComponent(String(imageName.prefix(2)))
			// Testing this requires wiping out the thumbnail directory.
			if (!FileManager.default.fileExists(atPath: destinationDir.path)) {
				try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
			}
			let thumbPath = destinationDir.appendingPathComponent(imageName)

			try Self.createThumbnail(from: image, preserving: origOrientation, as: imageType, to: thumbPath)
		}.get()
	}

	/// Archives an image that is no longer needed other than for accountability tracking, by
	/// removing the full-sized image and moving the thumbnail into the `archive/` subdirectory
	/// of the provided base image directory.
	///
	/// This is a synchronous operation, until such time as we can use SwiftNIO 2's asynchronous
	/// file I/O.
	///
	/// - Parameters:
	///   - image: The filename of the image.
	///   - imageDir: The base image directory path for the image's context.
	func archiveImage(_ image: String, on req: Request) {
		do {
			// remove existing full image
			let fullURL = try getImagePath(for: image, usage: .twarrt , size: .full, on: req)
			try FileManager().removeItem(at: fullURL)

			// move thumbnail
			let thumbnailURL = try getImagePath(for: image, usage: .twarrt , size: .thumbnail, on: req)
			let archiveURL = try getImagePath(for: image, usage: .twarrt , size: .archive, on: req)
			try FileManager().moveItem(at: thumbnailURL, to: archiveURL)

		} catch let error {
			req.logger.debug("could not archive image: \(error)")
		}
	}
}

extension ExportableFormat {
	init(_ imp: ImportableFormat) {
		switch imp {
//		case .bmp: self = .bmp(compression: true)
		case .gif: self = .gif
		case .jpg: self = .jpg(quality: 90)
		case .png: self = .png
		case .tiff: self = .tiff
		case .webp: self = .webp
		default: self = .jpg(quality: 90)
		}
	}

	func fileExtension() -> String {
		switch self {
		case .bmp: return "bmp"
		case .gif: return "gif"
		case .jpg: return "jpg"
		case .png: return "png"
		case .tiff: return "tiff"
		case .wbmp: return "wbmp"
		case .webp: return "webp"
		}
	}
}
