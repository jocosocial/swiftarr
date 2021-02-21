import Vapor
import SwiftGD

/// The type of model for which an `ImageHandler` is processing. This defines the
/// size of the thumbnail produced.

enum ImageHandlerType: String {
    /// The image is for a `ForumPost`.
    case forumPost
    /// The image is for a `Twarrt`
    case twarrt
    /// The image is for a `User`'s profile.
    case userProfile
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

extension RouteCollection {

	/// Returns the file system path for the given image filename. Makes sure all image directories in the path exist.
	/// 
	/// Currently, this fn returns paths in the form:
	///		<WorkingDir>/images/<full/thumb>/<xx>/<filename>.jpg
	/// where "xx" is the first 2 characters of the filename.
	func getImagePath(for image: String, type: ImageHandlerType, size: ImageSize, on req: Request) throws -> URL {
		let baseImagesDirectory = req.application.baseImagesDirectory ?? 
				URL(fileURLWithPath: DirectoryConfiguration.detect().workingDirectory).appendingPathComponent("images")

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
			let fileURL = subDir.appendingPathComponent(filename + ".jpg")
			return fileURL
		}
		let staticBase =  baseImagesDirectory.appendingPathComponent("staticImages")
		if !FileManager().fileExists(atPath: staticBase.path) {
			try FileManager().createDirectory(atPath: staticBase.path, withIntermediateDirectories: true)
		}
		let fileURL = staticBase.appendingPathComponent(filename + ".jpg")
		return fileURL
	}

    /// Takes an optional image in Data form as input, produces full and thumbnail JPEG vrsions,
    /// places both the thumbnail and full image in their respective directories, and returns the
    /// generated name of the file on success, an empty string otherwise.
    ///
    /// - Parameters:
    ///   - data: The uploaded image in `Data` format.
    ///   - forType: The type of model using the image content.
    ///    - req: The incoming `Request`, on which this processing must run.
    /// - Returns: The generated name of the stored file, or nil.
    func processImage(data: Data?, forType: ImageHandlerType, on req: Request) -> EventLoopFuture<String?> {
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
				var image = try Image.init(data: data)
								
				// attempt to crop to square if profile image
				if forType == .userProfile && image.size.height != image.size.width {
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
				
				// Resize if the image is over our size limit. Iphone 11 Pro Max has a scren size of 1242x2688 pixels.
				// A 4:3 portrait photo at 1536x2048 would downscale slightly to 1242x1656. 2K should therefore
				// be a reasonable size limit.
				if image.size.height > 2048 || image.size.width > 2048 {
					let resizeAmt: Double = 2048.0 / Double(max(image.size.height, image.size.width))
					if let resizedImage = image.resizedTo(width: Int(Double(image.size.width) * resizeAmt), 
							height: Int(Double(image.size.height) * resizeAmt)) {
						image = resizedImage		
					}
				}

				// ensure directories exist
				let name = UUID().uuidString
				let fullPath = try self.getImagePath(for: name, type: forType, size: .full, on: req)
				let thumbPath = try self.getImagePath(for: name, type: forType, size: .thumbnail, on: req)
			
				// save full image as jpg
				image.write(to: fullPath, quality: 90)
				
				// save thumbnail
				if let thumbnail = image.resizedTo(height: 100) {
					thumbnail.write(to: thumbPath, quality: 90)
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
			let fullURL = try self.getImagePath(for: image, type: .twarrt , size: .full, on: req)
			try FileManager().removeItem(at: fullURL)

            // move thumbnail
			let thumbnailURL = try self.getImagePath(for: image, type: .twarrt , size: .thumbnail, on: req)
			let archiveURL = try self.getImagePath(for: image, type: .twarrt , size: .archive, on: req)
            try FileManager().moveItem(at: thumbnailURL, to: archiveURL)

        } catch let error {
            // FIXME: should do something useful here
            print("could not archive image: \(error)")
        }
    }
}
