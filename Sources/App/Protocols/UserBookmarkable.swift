import Vapor
import FluentPostgreSQL

/// A `Protocol` used to provide convenience functions for RouteCollection controllers that
/// return content that can be bookmarked by the user on a per-model basis.

protocol UserBookmarkable {
    /// The barrel type to be used for bookmarked model ID storage.
    var bookmarkBarrelType: BarrelType { get }
}

extension UserBookmarkable {
    /// Returns the `Barrel` of type `.bookmarkedBarrelType` for the request's `User`, or nil
    /// if none exists.
    ///
    /// - Parameters:
    ///   - user: The user who owns the barrel.
    ///   - req: The incoming `Request`, on whose event loop this must run.
    /// - Returns: `Barrel` of the required type, or `nil`.
    func getBookmarkBarrel(for user: User, on req: Request) throws -> Future<Barrel?> {
        return try Barrel.query(on: req)
            .filter(\.ownerID == user.requireID())
            .filter(\.barrelType == bookmarkBarrelType)
            .first()
            .map {
                (barrel) in
                guard let barrel = barrel else {
                    return nil
                }
                return barrel
        }
    }
    
    /// Returns whether a bookmarks barrel contains the provided integer ID value.
    ///
    /// - Parameters:
    ///   - user: The user who owns the barrel.
    ///   - value: The Int ID value being queried.
    ///   - req: The incoming `Request`, on whose event loop this must run.
    /// - Returns: `Bool` true if the barrel contains the value, else false.
    func isBookmarked(idValue: Int, byUser: User, on req: Request) throws -> Future<Bool> {
        return try Barrel.query(on: req)
            .filter(\.ownerID == byUser.requireID())
            .filter(\.barrelType == bookmarkBarrelType)
            .first()
            .map {
                (barrel) in
                guard let barrel = barrel else {
                    return false
                }
                return barrel.userInfo["bookmarks"]?.contains(String(idValue)) ?? false
        }
    }
}

