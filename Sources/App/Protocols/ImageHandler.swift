import Vapor
import SwiftGD

/// The type of model for which an `ImageHandler` is processing. This defines the
/// size of the thumbnail produced.

enum ImageHandlerType: String {
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
}

enum ImageSize: String {
	case thumbnail = "thumb"
//	case medium
	case full = "full"
	
	case archive = "archive"
}

/// A `Protocol` used to provide image processing within RouteCollection controllers.

extension Application {
	var baseImagesDirectory: URL? {
        get {
            self.storage[ImageHandlerStorageKey.self]?.baseImagesDirectory
        }
        set {
            self.storage[ImageHandlerStorageKey.self] = ImageHandlerStorage(baseImagesDirectory: newValue)
        }
    }
    
	/// This is the datatype that gets stored in UserCacheStorage. Vapor's Services API uses this.
	struct ImageHandlerStorage {
		var baseImagesDirectory: URL?
	}
	
	/// Storage key used by Vapor's Services API. Used by UserCache to access its cache data.
	struct ImageHandlerStorageKey: StorageKey {
		typealias Value = ImageHandlerStorage
	}
}

extension APIRouteCollection {

	/// Returns the file system path for the given image filename. Makes sure all image directories in the path exist.
	/// 
	/// Currently, this fn returns paths in the form:
	///		<WorkingDir>/images/<full/thumb>/<xx>/<filename>.jpg
	/// where "xx" is the first 2 characters of the filename.
	func getImagePath(for image: String, format: String? = nil, usage: ImageHandlerType, size: ImageSize, on req: Request) throws -> URL {
		let baseImagesDirectory = req.application.baseImagesDirectory ?? 
				URL(fileURLWithPath: DirectoryConfiguration.detect().workingDirectory).appendingPathComponent("images")
		
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
		let staticBase =  baseImagesDirectory.appendingPathComponent("staticImages")
		if !FileManager().fileExists(atPath: staticBase.path) {
			try FileManager().createDirectory(atPath: staticBase.path, withIntermediateDirectories: true)
		}
		let fileURL = staticBase.appendingPathComponent(filename + "." + imageFormat)
		return fileURL
	}
	
    /// Takes an an array of `ImageUploadData` as input. Some of the input elements may be new image Data that needs procssing;
	/// some of the input elements may refer to already-processed images in our image store. Once all the ImageUploadData elements are processed,
	/// returns a `[String]` containing the filenames where al the images are stored. The use case here is for editing existing content with
	/// image attachments in a way that prevents re-uploading of photos that are already on the server.
    ///
    /// - Parameters:
    ///   - images: The  images in `ImageUploadData` format. 
    ///   - usage: The type of model using the image content.
    ///    - req: The incoming `Request`, on which this processing must run.
    /// - Returns: The generated names of the stored files.
	func processImages(_ images: [ImageUploadData], usage: ImageHandlerType, on req: Request) -> EventLoopFuture<[String]> {
		guard images.count <= 4 else {
			return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "Too many image attachments"))
		}
		var processingFutures = [EventLoopFuture<String?>]()
		for image in images {
			if let imageData = image.image {
				processingFutures.append(processImage(data: imageData, usage: usage, on: req))
			}
			else if let filename = image.filename {
				processingFutures.append(req.eventLoop.makeSucceededFuture(filename))
			}
		}
		return processingFutures.flatten(on: req.eventLoop).map { filenames in
			return filenames.compactMap { $0 }
		}
	}

    /// Takes an optional image in Data form as input, produces full and thumbnail JPEG vrsions,
    /// places both the thumbnail and full image in their respective directories, and returns the
    /// generated name of the file on success, an empty string otherwise.
    ///
    /// - Parameters:
    ///   - data: The uploaded image in `Data` format.
    ///   - usage: The type of model using the image content.
    ///    - req: The incoming `Request`, on which this processing must run.
    /// - Returns: The generated name of the stored file, or nil.
    func processImage(data: Data?, usage: ImageHandlerType, on req: Request) -> EventLoopFuture<String?> {
		do {
			guard let data = data else {
				// Not an error, just nothing to do.
				return req.eventLoop.future(nil)
			}
			guard data.count < Settings.shared.maxImageSize else {
				let maxMegabytes = Settings.shared.maxImageSize / 1024 * 1024
				throw Abort(.badRequest, reason: "Image too large. Size limit is \(maxMegabytes)MB.")
			}
			return req.application.threadPool.runIfActive(eventLoop: req.eventLoop) {
				let imageTypes: [ImportableFormat] = [.jpg, .png, .gif, .webp, .tiff, .bmp, .wbmp]
				var foundType: ImportableFormat? = nil
				var foundImage: Image?
				for type in imageTypes {
					foundImage = try? Image(data: data, as: type) 
					if foundImage != nil{
						foundType = type
						break
					}
				}
				guard var image = foundImage, let imageType = foundType else {
					throw Error.invalidImage(reason: "No matching raster formatter for given image found")
				}
				var outputType = imageType
				
				// Disallow images with an aspect ratio > 10:1, as they're too often malicious (even if by 'malicious' it means
				// "ha ha you have to scroll past this"). Also disallow extremely large widths and heights.
				let sourceSize = image.size
				if sourceSize.width > 10000 || sourceSize.height > 10000 {
					throw Error.invalidImage(reason: "Image dimensions too large")
				}
				let aspectRatio = Double(sourceSize.width) / Double(sourceSize.height)
				if aspectRatio < 0.1 || aspectRatio > 10.0 {
					throw Error.invalidImage(reason: "Invalid image aspect ratio. ")
				}
												
				// attempt to crop to square if profile image
				if usage == .userProfile {
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

				// ensure directories exist
				let name = UUID().uuidString
				let outputExtension = ExportableFormat(outputType).fileExtension()
				let fullPath = try self.getImagePath(for: name, format: outputExtension, usage: usage, size: .full, on: req)
				let thumbPath = try self.getImagePath(for: name, format: outputExtension, usage: usage, size: .thumbnail, on: req)
			
				// save full image. If we didn't have to modify the input image, save the original in its original format.
				// Jpeg images always get exported, to ensure the Q value isn't needlessly high.
				let imageData = try outputType == .jpg ? image.export(as: .jpg(quality: 90)) : data
				try imageData.write(to: fullPath)
				
				// save thumbnail
				if let thumbnail = image.resizedTo(height: 100) {
					let thumbnailData = try thumbnail.export(as: ExportableFormat(outputType))
					try thumbnailData.write(to: thumbPath)
				}
				return fullPath.lastPathComponent
			}
		}
		catch {
			return req.eventLoop.makeFailedFuture(error)
		}
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
    func archiveImage(_ image: String, on req: Request) -> Void {
        do {
			// remove existing full image
			let fullURL = try self.getImagePath(for: image, usage: .twarrt , size: .full, on: req)
			try FileManager().removeItem(at: fullURL)

            // move thumbnail
			let thumbnailURL = try self.getImagePath(for: image, usage: .twarrt , size: .thumbnail, on: req)
			let archiveURL = try self.getImagePath(for: image, usage: .twarrt , size: .archive, on: req)
            try FileManager().moveItem(at: thumbnailURL, to: archiveURL)

        } catch let error {
            // FIXME: should do something useful here
            print("could not archive image: \(error)")
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
