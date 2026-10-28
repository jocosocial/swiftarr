import XCTVapor
@testable import swiftarr

/// These tests exercise resource resolution and streaming without configuring a database.
final class DevelopmentResourcesTests: XCTestCase {
	/// Backend song reads and HTTP media requests must select the same root in both environments.
	func testMicroKaraokeUsesTheHTTPResourceRoot() async throws {
		let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		let bundled = temporary.appendingPathComponent("bundle")
		let source = temporary.appendingPathComponent("source")
		let previousRoot = Settings.shared.staticFilesRootPath
		let previousOverride = Environment.get("SWIFTARR_DEV_RESOURCES")
		defer {
			Settings.shared.staticFilesRootPath = previousRoot
			if let previousOverride { setenv("SWIFTARR_DEV_RESOURCES", previousOverride, 1) }
			else { unsetenv("SWIFTARR_DEV_RESOURCES") }
			try? FileManager.default.removeItem(at: temporary)
		}
		Settings.shared.staticFilesRootPath = bundled
		setenv("SWIFTARR_DEV_RESOURCES", source.path, 1)
		for (root, content) in [(bundled.appendingPathComponent("Resources"), "bundled"), (source, "source")] {
			let directory = root.appendingPathComponent("Assets/microkaraoke/test-song/0")
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			try Data(content.utf8).write(to: directory.appendingPathComponent("sample.mp3"))
		}
		for (environment, expected) in [(Environment.development, "source"), (.production, "bundled")] {
			let app = try await Application.make(environment)
			do {
				try SiteFileController().registerRoutes(app)
				let directory = MicroKaraokeController().urlForSongDirectory(on: app, songName: "test-song", snippetIndex: 0)
				XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("sample.mp3"), encoding: .utf8), expected)
				try await app.test(.GET, "/microkaraoke/test-song/0/sample.mp3", afterResponse: { response async throws in
					XCTAssertEqual(response.status, .ok)
					XCTAssertEqual(response.body.string, expected)
				})
			}
			catch {
				try await app.asyncShutdown()
				throw error
			}
			try await app.asyncShutdown()
		}
	}
}
