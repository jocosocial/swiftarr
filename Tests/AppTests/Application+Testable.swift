import Vapor
import XCTVapor
@testable import swiftarr

extension Application {
    static func testable() async throws -> Application {
        // var env = try Environment.detect()
        let app = try await Application.make(.testing)
        do {
			try await SwiftarrConfigurator(app).configure()
        } catch {
            app.logger.report(error: error)
            try? await app.asyncShutdown()
            throw error
        }
        return app
    }
}
