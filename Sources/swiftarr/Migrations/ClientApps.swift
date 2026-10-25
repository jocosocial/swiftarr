import Fluent
import Vapor

/// A `Migration` that seeds the `client_app` table from a JSON file in the `seeds/` subdirectory of the project: `client-apps.json`
/// for release builds and `test-client-apps.json` otherwise, the same convention as the games catalog and registered-clients files.
/// The two files ship with identical contents; edit either to change what a new server starts with, or make a file `[]` to start empty.
///
/// The file is an array of objects:
///
///     {
///         "name": "Tricordarr",
///         "description": "A native Twitarr client for Android and iOS.",
///         "developer": "Grant Cohoe",
///         "sortName": "Tricordarr",                          // optional; defaults to name
///         "icon": "ClientApps/tricordarr.jpg",               // optional; path relative to the seeds directory
///         "links": [ { "platform": "android", "url": "..." }, { "platform": "ios", "url": "..." } ],
///         "swiftarrClient": "tricordarr"                     // optional
///     }
///
/// A missing or unreadable icon file just results in a client app with no image. A missing or malformed seed file fails the migration.
struct CreateClientApps: AsyncMigration {
	struct SeedApp: Decodable {
		var name: String
		var description: String
		var developer: String
		var sortName: String?
		var icon: String?
		var links: [ClientAppLink]
		var swiftarrClient: SwiftarrClientApp?
	}

	/// The seed file for this build: the real one for release builds, the test one otherwise.
	static var seedFileName: String {
		(try? Environment.detect().isRelease) == true ? "client-apps.json" : "test-client-apps.json"
	}

	static func loadSeedApps(from seedsDirectory: URL) throws -> [SeedApp] {
		let path = seedsDirectory.appendingPathComponent(seedFileName)
		guard let data = FileManager.default.contents(atPath: path.path) else {
			throw Abort(.internalServerError, reason: "Could not read client apps seed file \(path.path).")
		}
		do {
			return try JSONDecoder().decode([SeedApp].self, from: data)
		}
		catch {
			throw Abort(.internalServerError, reason: "Could not parse client apps seed file \(seedFileName): \(error)")
		}
	}

	/// Resolves an `icon` value, a path relative to the seeds directory, to a file URL. Returns nil if the path would
	/// escape the seeds directory (absolute paths, `..`), so a seed file can't be used to read arbitrary files.
	static func iconURL(for icon: String, seedsDirectory: URL) -> URL? {
		let root = seedsDirectory.standardizedFileURL
		let url = root.appendingPathComponent(icon).standardizedFileURL
		guard !icon.hasPrefix("/"), url.path.hasPrefix(root.path + "/") else {
			return nil
		}
		return url
	}

	func prepare(on database: Database) async throws {
		let seedsDirectory = Settings.shared.seedsDirectoryPath
		for seed in try Self.loadSeedApps(from: seedsDirectory) {
			var imageName: String?
			if let icon = seed.icon {
				do {
					guard let iconURL = Self.iconURL(for: icon, seedsDirectory: seedsDirectory) else {
						throw Abort(.badRequest, reason: "icon path must be inside the seeds directory")
					}
					imageName = try processImageData(try Data(contentsOf: iconURL), usage: .clientApp, logger: database.logger)
				}
				catch {
					database.logger.warning("Couldn't load client app seed icon \(icon) for \(seed.name): \(error.localizedDescription)")
				}
			}
			let app = ClientApp(
				name: seed.name,
				description: seed.description,
				image: imageName,
				developer: seed.developer,
				sortName: seed.sortName,
				links: seed.links,
				swiftarrClient: seed.swiftarrClient
			)
			try await app.save(on: database)
		}
	}

	func revert(on database: Database) async throws {
		let names = (try? Self.loadSeedApps(from: Settings.shared.seedsDirectoryPath))?.map { $0.name } ?? []
		try await ClientApp.query(on: database).filter(\.$name ~~ names).delete()
	}
}
