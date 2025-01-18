import Vapor
import XCTVapor
@testable import swiftarr

extension Application {
    static func testable() async throws -> Application {
        // var env = try Environment.detect()
        let app = try await Application.make(.testing)
        do {
			try await SwiftarrConfigurator(app).configure()
            // Some day this should do the entire post startup configuration.
            // Not just the TZChanges that I cherry-picked out to make them function.
            try await Settings.shared.readTimeZoneChanges(app)
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        return app
    }
}
