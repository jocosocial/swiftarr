import XCTest
@testable import swiftarr

// Pure tests (no DB) for the client apps seed files and icon path handling.
class ClientAppSeedFileTests: XCTestCase {

	/// The `seeds/` directory in the source tree, located relative to this file.
	private var seedsDirectory: URL {
		URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
			.appendingPathComponent("Sources/swiftarr/seeds", isDirectory: true)
	}

	private func load(_ fileName: String) throws -> [CreateClientApps.SeedApp] {
		let data = try Data(contentsOf: seedsDirectory.appendingPathComponent(fileName))
		return try JSONDecoder().decode([CreateClientApps.SeedApp].self, from: data)
	}

	/// Whichever file a build picks, it must parse, be sane, and point at icon files that exist.
	func testShippedSeedFilesAreValid() throws {
		for fileName in ["client-apps.json", "test-client-apps.json"] {
			let apps = try load(fileName)
			XCTAssertFalse(apps.isEmpty, fileName)
			XCTAssertEqual(Set(apps.map { $0.name }).count, apps.count, "\(fileName): names should be unique")
			for app in apps {
				XCTAssertFalse(app.name.isEmpty, fileName)
				XCTAssertFalse(app.links.isEmpty, "\(fileName): \(app.name) needs a link")
				XCTAssertEqual(Set(app.links.map { $0.platform }).count, app.links.count,
						"\(fileName): \(app.name) has two links for one platform")
				if let icon = app.icon {
					let url = try XCTUnwrap(CreateClientApps.iconURL(for: icon, seedsDirectory: seedsDirectory),
							"\(fileName): \(app.name) icon escapes the seeds directory")
					XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(fileName): missing icon \(icon)")
				}
			}
		}
	}

	func testSeedFileContainsKnownClients() throws {
		let apps = try load("client-apps.json")
		let tricordarr = try XCTUnwrap(apps.first { $0.name == "Tricordarr" })
		XCTAssertEqual(Set(tricordarr.links.map { $0.platform }), [.ios, .android])
		XCTAssertEqual(tricordarr.swiftarrClient, .tricordarr)
		XCTAssertEqual(try XCTUnwrap(apps.first { $0.name == "The Kraken" }).swiftarrClient, .kraken)
		XCTAssertEqual(try XCTUnwrap(apps.first { $0.name == "Twitarr Web UI" }).links.first?.platform, .web)
	}

	func testIconPathsMustStayInsideSeedsDirectory() {
		let seeds = URL(fileURLWithPath: "/srv/swiftarr/seeds", isDirectory: true)
		XCTAssertNotNil(CreateClientApps.iconURL(for: "ClientApps/kraken.png", seedsDirectory: seeds))
		XCTAssertNotNil(CreateClientApps.iconURL(for: "ClientApps/../ClientApps/kraken.png", seedsDirectory: seeds))
		XCTAssertNil(CreateClientApps.iconURL(for: "../secrets.png", seedsDirectory: seeds))
		XCTAssertNil(CreateClientApps.iconURL(for: "ClientApps/../../secrets.png", seedsDirectory: seeds))
		XCTAssertNil(CreateClientApps.iconURL(for: "/etc/passwd", seedsDirectory: seeds))
		XCTAssertNil(CreateClientApps.iconURL(for: "..", seedsDirectory: seeds))
	}
}
