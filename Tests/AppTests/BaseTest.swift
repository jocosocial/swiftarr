import Redis
import XCTVapor
@testable import swiftarr

protocol SwiftarrBaseTest {}

extension SwiftarrBaseTest {
    func withApp(_ test: (Application) async throws -> ()) async throws {
        let app = try await Application.testable()
        do {
            try await app.autoMigrate()   
            // Auth rate limit counts live in Redis and would otherwise carry over from earlier tests. Redis needs the app booted;
            // XCTVapor boots it on the first request anyway.
            try await app.asyncBoot()
            try await clearAuthRateLimits(app)
            try await test(app)
        }
        catch {
            try? await app.autoRevert()
            try await app.asyncShutdown()
            throw error
        }
        try await app.asyncShutdown()
    }

    func clearAuthRateLimits(_ app: Application) async throws {
        let keys = try await app.redis.send(command: "KEYS", with: [.init(from: "authlimit*")]).get()
        let redisKeys = (keys.array ?? []).compactMap { $0.string }.map { RedisKey($0) }
        if !redisKeys.isEmpty {
            _ = try await app.redis.delete(redisKeys).get()
        }
    }

    /// The number of attempts currently counted against an `AuthRateLimiter` bucket.
    func authRateLimitCount(_ app: Application, _ bucket: AuthRateLimiter.Bucket) async throws -> Int {
        return try await app.redis.get(RedisKey("authlimit:\(bucket.key)"), as: Int.self).get() ?? 0
    }
}
