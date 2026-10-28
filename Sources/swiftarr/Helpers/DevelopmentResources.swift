import Foundation
import Vapor

/// Resolves optional source resources only for an explicitly enabled development run.
enum DevelopmentResources {
	/// Uses the same site resource directory for backend readers, templates, and HTTP assets.
	static func siteRoot(on app: Application) -> URL {
		root(on: app) ?? Settings.shared.staticFilesRootPath.appendingPathComponent("Resources")
	}

	static func root(on app: Application) -> URL? {
		guard app.environment == .development,
			let path = Environment.get("SWIFTARR_DEV_RESOURCES"), !path.isEmpty
		else { return nil }
		return URL(fileURLWithPath: path, isDirectory: true)
	}
}
