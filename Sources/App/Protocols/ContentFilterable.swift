import Vapor
import Redis

/// A `Protocol` used to provide convenience functions for RouteCollection controllers that
/// return content that is filterable on a per-user basis.

protocol ContentFilterable {
    /// Return the cached blocks, mutes and mutewords for the current user.
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

extension ContentFilterable {
    /// Checks if a `ForumPost` contains any of the provided array of muting strings, returning
    /// either the original post or `nil` if there is a match.
    ///
    /// - Parameters:
    ///   - post: The `ForumPost` to filter.
    ///   - mutewords: The list of strings on which to filter the post.
    ///   - req: The incoming `Request` on whose event loop this needs to run.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func filterMutewords(for post: ForumPost, using mutewords: [String], on req: Request) -> ForumPost? {
        for word in mutewords {
            if post.text.range(of: word, options: .caseInsensitive) != nil {
                return nil
            }
        }
        return post
    }
    
    /// Checks if a `Twarrt` contains any of the provided array of muting strings, returning
    /// either the original twarrt or `nil` if there is a match.
    ///
    /// - Parameters:
    ///   - post: The `ForumPost` to filter.
    ///   - mutewords: The list of strings on which to filter the post.
    ///   - req: The incoming `Request` on whose event loop this needs to run.
    /// - Returns: The provided post, or `nil` if the post contains a muting string.
    func filterMutewords(for twarrt: Twarrt, using mutewords: [String], on req: Request) -> Twarrt? {
        for word in mutewords {
            if twarrt.text.range(of: word, options: .caseInsensitive) != nil {
                return nil
            }
        }
        return twarrt
    }

}
