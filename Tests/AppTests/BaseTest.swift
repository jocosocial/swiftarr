import XCTVapor

protocol SwiftarrBaseTest {}

extension SwiftarrBaseTest {
    func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.testable()
        do {
            try await app.autoMigrate()   
            try await test(app)
        }
        catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }
}