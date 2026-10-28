import Foundation
import Vapor

/// Resolves optional source resources only for an explicitly enabled development run.
enum DevelopmentResources {
	static func root(on app: Application) -> URL? {
		guard app.environment == .development,
			let path = Environment.get("SWIFTARR_DEV_RESOURCES"), !path.isEmpty
		else { return nil }
		return URL(fileURLWithPath: path, isDirectory: true)
	}
}
