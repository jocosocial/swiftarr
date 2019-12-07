import Vapor

protocol ImageHandler {
    var imageDir: String { get }
    func processImage(data: Data?, forType: ImageHandlerType, on req: Request) throws -> Future<String>
}

extension ImageHandler {
    /// Takes an optional image in Data form as input, produces a thumbnail version, places
    /// both the thumbnail and original image in their respective directories, and returns the
    /// generated name of the file on success, an empty string otherwise.
    ///
    /// - Parameters:
    ///   - data: The uploaded image in `Data` format.
    ///   - forType: The type of model using the image content.
    ///   - req: The incoming `Request`, on which this processing must run.
    /// - Returns: The generated name of the stored file, or an empty string.
    func processImage(data: Data?, forType: ImageHandlerType, on req: Request) throws -> Future<String> {
        return req.future("Hello")
    }
}
