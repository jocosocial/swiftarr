import Vapor
import SwiftGD

/// A `Protocol` used to provide image processing within RouteCollection controllers.

protocol ImageHandler {
    /// The base directory for image storage for this type.
    var imageDir: String { get }
    /// The height of a thumbnail.
    var thumbnailHeight: Int { get }
    /// The image processing function.
    func processImage(data: Data?, forType: ImageHandlerType, on req: Request) throws -> Future<String>
}

extension ImageHandler {
    /// Takes an optional image in Data form as input, produces full and thumbnail JPEG vrsions,
    /// places both the thumbnail and full image in their respective directories, and returns the
    /// generated name of the file on success, an empty string otherwise.
    ///
    /// - Parameters:
    ///   - data: The uploaded image in `Data` format.
    ///   - forType: The type of model using the image content.
    ///   - req: The incoming `Request`, on which this processing must run.
    /// - Returns: The generated name of the stored file, or an empty string.
    func processImage(data: Data?, forType: ImageHandlerType, on req: Request) throws -> Future<String> {
        guard let data = data else {
            return req.future("")
        }
        var image = try Image.init(data: data)
        
        // FIXME: this will all need async dispatch if kept
        
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
        
        // ensure directories exist
        let baseDir = DirectoryConfig.detect().workDir.appending(imageDir)
        let fullPath = baseDir.appending("full/")
        let thumbPath = baseDir.appending("thumbnail/")
        if !FileManager().fileExists(atPath: fullPath) {
            try FileManager().createDirectory(atPath: fullPath, withIntermediateDirectories: true)
        }
        if !FileManager().fileExists(atPath: thumbPath) {
            try FileManager().createDirectory(atPath: thumbPath, withIntermediateDirectories: true)
        }
        
        // save as jpg
        let name = UUID().uuidString
        let fullURL = URL(fileURLWithPath: fullPath.appending(name).appending(".jpg"))
        image.write(to: fullURL)
        
        // save thumbnail
        let thumbnailURL = URL(fileURLWithPath: thumbPath.appending(name).appending(".jpg"))
        if let thumbnail = image.resizedTo(height: thumbnailHeight) {
            thumbnail.write(to: thumbnailURL)
        }
        return req.future(name)
    }
}

extension ImageHandler {
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
    func archiveImage(_ image: String, from imageDir: String) -> Void {
        // remove existing full image
        let basePath = DirectoryConfig.detect().workDir.appending(imageDir)
        let fullPath = basePath.appending("full/")
        let fullURL = URL(
            fileURLWithPath: fullPath.appending(image).appending(".jpg")
        )
        do {
            try FileManager().removeItem(at: fullURL)
            // move thumbnail
            let thumbPath = basePath.appending("thumbnail/")
            let archivePath = basePath.appending("archive/")
            // ensure archive directory exists
            if !FileManager().fileExists(atPath: archivePath) {
                try FileManager().createDirectory(
                    atPath: archivePath,
                    withIntermediateDirectories: true
                )
            }
            let thumbURL = URL(
                fileURLWithPath: thumbPath.appending(image).appending(".jpg")
            )
            let archiveURL = URL(
                fileURLWithPath: archivePath.appending(image).appending(".jpg")
            )
            try FileManager().moveItem(at: thumbURL, to: archiveURL)

        } catch let error {
            // FIXME: should do something useful here
            print("could not archive image: \(error)")
        }
    }
}
