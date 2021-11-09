import Vapor
import Fluent

struct SiteFileController: SiteControllerUtils {
	private static var filesRoot: URL = URL(fileURLWithPath: "/")

	func registerRoutes(_ app: Application) throws {
		let dir = DirectoryConfiguration.detect().workingDirectory
		SiteFileController.filesRoot = URL(fileURLWithPath: dir).appendingPathComponent("Resources/Assets")
	
		// Routes that the user does not need to be logged in to access.
		app.get("css", "**", use: streamCSSFile)
		app.get("img", "**", use: streamImgFile)
		app.get("js", "**", use: streamJSFile)

	}

	// `GET /css/:catchall`
	//
	// :catchall is any path after "/css/", not just a single filename.
	func streamCSSFile(_ req: Request) throws -> EventLoopFuture<Response> {
		return try streamFile(req, basePath: "css")
	}

	// `GET /img/:catchall`
	func streamImgFile(_ req: Request) throws -> EventLoopFuture<Response> {
		return try streamFile(req, basePath: "img")
	}

	// `GET /js/:catchall`
	func streamJSFile(_ req: Request) throws -> EventLoopFuture<Response> {
		return try streamFile(req, basePath: "js")
	}
	
	// Wraps fileio.streamFile. Sanity-checks the path, builds a file system path to the resource,
	// and streams the resource file. Adds a cache-control header as all these files are long-lived and shouldn't change.
	func streamFile(_ req: Request, basePath: String) throws -> EventLoopFuture<Response> {
        // make a copy of the percent-decoded path
        guard var path = req.parameters.getCatchall().joined(separator: "/").removingPercentEncoding else {
            return req.eventLoop.makeFailedFuture(Abort(.badRequest))
        }

        // path must be relative.
        while path.hasPrefix("/") {
            path = String(path.dropFirst())
        }

        // protect against relative paths
        guard !path.contains("../") else {
            return req.eventLoop.makeFailedFuture(Abort(.forbidden))
        }

        // create absolute file path
        let filePath = SiteFileController.filesRoot.appendingPathComponent(basePath).appendingPathComponent(path).path

        // check if file exists and is not a directory
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir), !isDir.boolValue else {
			throw Abort(.notFound)
        }

        // stream the file, then add a "Cache-Control" header with a 24 hour freshness time.
        let response = req.fileio.streamFile(at: filePath)
		if response.status == .ok || response.status == .notModified {
			response.headers.cacheControl = .init(isPublic: true, maxAge: 3600 * 24)
		}        
        return req.eventLoop.makeSucceededFuture(response)
	}
}
