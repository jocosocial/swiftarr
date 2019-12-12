import Vapor
import Redis

/// A `Protocol` used to provide convenience functions for RouteCollection controllers that
/// return content that is filterable on a per-user basis.

protocol ContentFilterable {
    /// Return the cached blocked UUIDs, muted UUIDs and muting keyword String values for content
    /// filtering.
    func getCachedFilters(for user: User, on req: Request) throws -> Future<([UUID], [UUID], [String])>
}

extension ContentFilterable {
    /// Default impementation that takes a `User` as input and returns the redis-cached values
    /// of the user's blocks, mutes and muting keywords.
    ///
    /// - Parameters:
    ///   - user: The user whose values are being retrieved.
    ///   - req: The incoming `Request`, on whose event loop this must run.
    /// - Returns: A tuple of `([UUID], [UUID], [String]` (blocks, mutes, mutewords).
    func getCachedFilters(for user: User, on req: Request) throws -> Future<([UUID], [UUID], [String])> {
        let cache = try req.keyedCache(for: .redis)
        let blocksKey = try "blocks:\(user.requireID())"
        let mutesKey = try "mutes:\(user.requireID())"
        let mutewordsKey = try "mutewords:\(user.requireID())"
        let cachedBlocks = cache.get(blocksKey, as: [UUID].self)
        let cachedMutes = cache.get(mutesKey, as: [UUID].self)
        let cachedMutewords = cache.get(mutewordsKey, as: [String].self)
        return map(cachedBlocks, cachedMutes, cachedMutewords) {
            (blocks, mutes, mutewords) in
            let blocked = blocks ?? []
            let muted = mutes ?? []
            let mutedwords = mutewords ?? []
            return (blocked, muted, mutedwords)
        }
    }
}
