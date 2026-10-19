import Fluent
import Vapor

/// A `Migration` that seeds the `client_app` table with the well-known Twitarr clients, including the web UI served by this
/// server. Icons are read from the `seeds/ClientApps/` subdirectory of the project; a missing or unreadable icon just
/// results in a client app with no image.
struct CreateClientApps: AsyncMigration {
	struct SeedApp {
		var name: String
		var description: String
		var developer: String
		var iconFile: String
		var links: [ClientAppLink]
		var swiftarrClient: SwiftarrClientApp
	}

	static let seedApps: [SeedApp] = [
		SeedApp(
			name: "Twitarr Web UI",
			description: "The website you're looking at right now. Works in any modern browser, no install needed.",
			developer: "Twitarr Team",
			iconFile: "website.png",
			links: [ClientAppLink(platform: .web, url: "/")],
			swiftarrClient: .swiftarr
		),
		SeedApp(
			name: "Tricordarr",
			description: "A native Twitarr client for Android and iOS.",
			developer: "Grant Cohoe",
			iconFile: "tricordarr.jpg",
			links: [
				ClientAppLink(platform: .android, url: "https://play.google.com/store/apps/details?id=com.tricordarr"),
				ClientAppLink(platform: .ios, url: "https://apps.apple.com/us/app/tricordarr/id6754777522"),
			],
			swiftarrClient: .tricordarr
		),
		SeedApp(
			name: "The Kraken",
			description: "A native Twitarr client for iOS.",
			developer: "Chall Fry",
			iconFile: "kraken.png",
			links: [
				ClientAppLink(
					platform: .ios, url: "https://apps.apple.com/us/app/the-kraken-a-twitarr-client/id1496322373")
			],
			swiftarrClient: .kraken
		),
	]

	func prepare(on database: Database) async throws {
		for seed in Self.seedApps {
			var imageName: String?
			let iconPath = Settings.shared.seedsDirectoryPath.appendingPathComponent("ClientApps")
				.appendingPathComponent(seed.iconFile)
			do {
				imageName = try processImageData(try Data(contentsOf: iconPath), usage: .clientApp, logger: database.logger)
			}
			catch {
				database.logger.warning("Couldn't load client app seed icon \(seed.iconFile): \(error.localizedDescription)")
			}
			let app = ClientApp(
				name: seed.name,
				description: seed.description,
				image: imageName,
				developer: seed.developer,
				links: seed.links,
				swiftarrClient: seed.swiftarrClient
			)
			try await app.save(on: database)
		}
	}

	func revert(on database: Database) async throws {
		let names = Self.seedApps.map { $0.name }
		try await ClientApp.query(on: database).filter(\.$name ~~ names).delete()
	}
}
