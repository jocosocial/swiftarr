import Vapor
import Redis

/// A `Protocol` used to provide convenience functions for Models that
/// return content that is filterable on a per-user basis.
protocol ContentFilterable {    
    func containsMutewords(using mutewords: [String]) -> Bool
	func filterMutewords(using mutewords: [String]?) -> Self?
}

extension ContentFilterable {

    /// Default impementation that takes a `User` as input and returns the redis-cached values
    /// of the user's blocks, mutes and muting keywords.
    ///
    /// - Parameters:
    ///   - user: The user whose values are being retrieved.
    ///   - req: The incoming `Request`, on whose event loop this must run.
    /// - Returns: A tuple of `([UUID], [UUID], [String]` (blocks, mutes, mutewords).
    static func getCachedFilters(for user: User, on req: Request) -> EventLoopFuture<(CachedFilters)> {
    	do {
			let blocksKey: RedisKey = try "blocks:\(user.requireID())"
			let mutesKey: RedisKey = try "mutes:\(user.requireID())"
			let mutewordsKey: RedisKey = try "mutewords:\(user.requireID())"
			let cachedBlocks = req.redis.get(blocksKey, as: [UUID].self).unwrap(orReplace: [])
			let cachedMutes = req.redis.get(mutesKey, as: [UUID].self).unwrap(orReplace: [])
			let cachedMutewords = req.redis.get(mutewordsKey, as: [String].self).unwrap(orReplace: [])
			return cachedBlocks.and(cachedMutes).and(cachedMutewords).map {
				(tuple: ((blocked: [UUID], muted: [UUID]), mutedwords: [String])) in
				return CachedFilters(blocked: tuple.0.blocked, muted: tuple.0.muted, mutewords: tuple.mutedwords)
			}
		}
		catch {
			return req.eventLoop.makeFailedFuture(error)
		}
    }
}

struct CachedFilters {
	let blocked: [UUID]
	let muted: [UUID]
	let mutewords: [String]
}

