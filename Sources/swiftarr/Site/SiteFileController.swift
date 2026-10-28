import Fluent
import Vapor

/// Serves static files used bye the Web UI front end. Since these files are UI-level and not API-level entities, we serve
/// these files directly from here--there's no need to forward calls through the API. This means if you're an API client, you
/// shouldn't be using the files served from these endpoints.
///
/// Normal runs serve bundled files; the development runner can opt into source assets.
struct SiteFileController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {

		// Routes that the user does not need to be logged in to access.
		app.get("css", "**", use: streamCSSFile)
		app.get("fonts", "**", use: streamFontFile)
		app.get("img", "**", use: streamImgFile)
		app.get("js", "**", use: streamJSFile)
		app.get("microkaraoke", "**", use: streamMKFile)
		// This replaces FileMiddleware from Sources/swiftarr/configure.swift.
		app.get("public", "**", use: streamPublicFile)
		app.get("favicon.ico", use: streamFavicon)
		if DevelopmentResources.root(on: app) != nil,
			let revisionFile = Environment.get("SWIFTARR_DEV_RELOAD_FILE") {
			// The runner owns this file; browsers can read only its opaque revision, never choose a path.
			app.get("__dev", "revision") { req async throws -> Response in
				let buffer = try await req.fileio.collectFile(at: revisionFile)
				let response = Response(status: .ok, body: .init(buffer: buffer))
				response.headers.replaceOrAdd(name: .contentType, value: "text/plain; charset=utf-8")
				response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
				return response
			}
		}
	}

	// `GET /css/:catchall`
	//
	// :catchall is any path after "/css/", not just a single filename.
	func streamCSSFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "css")
	}

	// `GET /fonts/:catchall`
	func streamFontFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "fonts")
	}

	// `GET /img/:catchall`
	func streamImgFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "img")
	}

	// `GET /js/:catchall`
	func streamJSFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "js")
	}

	// `GET /microkaraoke/:catchall`
	func streamMKFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "microkaraoke")
	}

	// `GET /public/:catchall`
	func streamPublicFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "public")
	}
	
	// `GET /favicon.ico
	//
	// In accordance with the old ways, this associates '/favicon.ico' with our Microsoft ICO formatted icon file (which is 
	// actually in "Sources/swiftarr/Resources/Assets/img"). We also refer to this path using the more modern link header (see trunk.html).
	func streamFavicon(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "img/favicon.ico")
	}

	// Wraps fileio.streamFile. Sanity-checks the path, builds a file system path to the resource,
	// and streams the resource file. Normal runs cache assets; source development runs disable browser caching.
	func streamFile(_ req: Request, basePath: String) throws -> Response {
		// make a copy of the percent-decoded path
		guard var path = req.parameters.getCatchall().joined(separator: "/").removingPercentEncoding else {
			throw Abort(.badRequest)
		}

		// path must be relative.
		while path.hasPrefix("/") {
			path = String(path.dropFirst())
		}

		// protect against relative paths
		guard !path.contains("../") else {
			throw Abort(.forbidden)
		}

		// create absolute file path
		let resourceRoot = DevelopmentResources.root(on: req.application)
			?? Settings.shared.staticFilesRootPath.appendingPathComponent("Resources")
		let filePath = resourceRoot
			.appendingPathComponent("Assets/\(basePath)")
			.appendingPathComponent(path)

		// check if file exists and is not a directory
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: filePath.path, isDirectory: &isDir), !isDir.boolValue else {
			throw Abort(.notFound)
		}

		// Stream the file with a 24 hour cache lifetime, or no storage for live source edits.
		let response = req.fileio.streamFile(at: filePath.path)
		if response.status == .ok || response.status == .notModified {
			if DevelopmentResources.root(on: req.application) != nil {
				response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
			}
			else {
				response.headers.cacheControl = .init(isPublic: true, maxAge: 3600 * 24)
			}
		}
		return response
	}
}
