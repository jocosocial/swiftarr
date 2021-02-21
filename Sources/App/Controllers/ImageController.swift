import Vapor
import Crypto
import FluentSQL
import SwiftGD
import Foundation

// rcf Contents of this file are still being baked.
struct ImageController: RouteCollection {
	// Important that this stays a constant; changing after creation is not thread-safe.
	// Also, since this is based on DirectdoryConfiguration, the value is process-wide, not Application-wide.
	let imagesDirectory: URL
	
	init() {
		let dir = DirectoryConfiguration.detect().workingDirectory
		imagesDirectory = URL(fileURLWithPath: dir).appendingPathComponent("images")
	}
 
    /// Required. Registers routes to the incoming router.
    func boot(routes: RoutesBuilder) throws {
        
		// convenience route group for all /api/v3/auth endpoints
		let imageRoutes = routes.grouped("api", "v3", "image")

		// instantiate authentication middleware
//		let basicAuthMiddleware = User.authenticator()
//		let guardAuthMiddleware = User.guardMiddleware()
//		let tokenAuthMiddleware = Token.authenticator()

		// set protected route groups
//		let basicAuthGroup = imageRoutes.grouped([basicAuthMiddleware, guardAuthMiddleware])
//		let tokenAuthGroup = imageRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])

		// open access endpoints
		imageRoutes.get("full", ":image_uuid", use: getImage_FullHandler)
		imageRoutes.get("thumb", ":image_uuid", use: getImage_ThumbnailHandler)
	}
	
	func getImage_FullHandler(_ req: Request) throws -> Response {
		return try getImageHandler(req, typeStr: "full")
	}
	
	func getImage_ThumbnailHandler(_ req: Request) throws -> Response {
		return try getImageHandler(req, typeStr: "thumbnail")
	}
	
	func getImageHandler(_ req: Request, typeStr: String) throws -> Response {
		guard let fileParam = req.parameters.get("image_uuid") else {
			throw Abort(.badRequest, reason: "No image file specified.")
		}
		// Strip extension and any other gunk off the filename. Eject if two extensions detected (.php.jpg, for example).
		let noFiletype = URL(fileURLWithPath: fileParam).deletingPathExtension()
		if noFiletype.pathExtension.count > 0 {
			throw Abort(.badRequest, reason: "Malformed image filename.")
		}
		let filename = noFiletype.lastPathComponent
		// This check is important for security. Not only does it do the obvious, it protects
		// against "../../../../file_important_to_Swiftarr_operation" attacks.
		guard let fileUUID = UUID(filename) else {
			throw Abort(.badRequest, reason: "Image filename is not a valid UUID.")
		}
				
		// I don't think ~10K files in each directory is going to cause slowdowns, but if it does,
		// this will give us 128 subdirs.
		let subDirName = String(fileParam.prefix(2))
			
        let fileURL = imagesDirectory.appendingPathComponent(typeStr)
        		.appendingPathComponent(subDirName)
        		.appendingPathComponent(fileUUID.uuidString + ".jpg")
		return req.fileio.streamFile(at: fileURL.path)
	}
}
