import Vapor
import Fluent

/// Serves static files used bye the Web UI front end. Since these files are UI-level and not API-level entities, we serve
/// these files directly from here--there's no need to forward calls through the API. This means if you're an API client, you
/// shouldn't be using the files served from these endpoints.
///
/// Files dynamically created currently require a restart to pick up.
struct SiteFileController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {

		// Routes that the user does not need to be logged in to access.
		app.get("css", "**", use: streamCSSFile)
		app.get("img", "**", use: streamImgFile)
		app.get("js", "**", use: streamJSFile)
		// This replaces FileMiddleware from Sources/App/configure.swift.
		app.get("public", "**", use: streamPublicFile)
		app.get("faq", use: streamFaqFile)

	}

	// `GET /css/:catchall`
	//
	// :catchall is any path after "/css/", not just a single filename.
	func streamCSSFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "css")
	}

	// `GET /img/:catchall`
	func streamImgFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "img")
	}

	// `GET /js/:catchall`
	func streamJSFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "js")
	}

	// `GET /public/:catchall`
	func streamPublicFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "public")
	}

	// `GET /faq`
	//
	// Serve the JoCo Cruise FAQ document. This is an HTML file that comes from the moderators
	// usually generated from a Google Doc. The export is achieved in Google Docs by going to
	// File -> Download -> Web Page (.html, zipped). The zip archive should include only a single
	// HTML file which we then shove in the Sources/App/Resources/Assets/public directory or
	// equivalent mountpoint. Technically this is also available at ${server}/public/faq.html
	// but we have this convenience URL for future purposes. Maybe some day we can find a sane
	// way to implement it as a View here while still allowing moderators to easily make changes.
	func streamFaqFile(_ req: Request) throws -> Response {
		return try streamFile(req, basePath: "public/faq.html")
	}

	// Wraps fileio.streamFile. Sanity-checks the path, builds a file system path to the resource,
	// and streams the resource file. Adds a cache-control header as all these files are long-lived and shouldn't change.
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
		let filePath = Settings.shared.staticFilesRootPath
				.appendingPathComponent("Resources/Assets/\(basePath)")
				.appendingPathComponent(path)

		// check if file exists and is not a directory
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: filePath.path, isDirectory: &isDir), !isDir.boolValue else {
			throw Abort(.notFound)
		}

		// stream the file, then add a "Cache-Control" header with a 24 hour freshness time.
		let response = req.fileio.streamFile(at: filePath.path)
		if response.status == .ok || response.status == .notModified {
			response.headers.cacheControl = .init(isPublic: true, maxAge: 3600 * 24)
		}
		return response
	}
}
