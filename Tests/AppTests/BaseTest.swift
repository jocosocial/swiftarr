import XCTVapor
@testable import swiftarr

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

    /// The number of attempts currently counted against an `AuthRateLimiter` bucket.
    func authRateLimitCount(_ app: Application, _ bucket: AuthRateLimiter.Bucket) async -> Int {
        await app.authRateLimitStore.count(bucket.key)
    }
}
