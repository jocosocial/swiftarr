import Vapor
import FluentPostgreSQL

/// A `Protocol` used to provide convenience functions for RouteCollection controllers that
/// return content that can be tagged by the user on a per-model basis.

protocol UserTaggable {
    /// The barrel type to be used for tagged model ID storage.
    var favoriteBarrelType: BarrelType { get }
}

extension UserTaggable {
    /// Returns the `Barrel` of type `.taggedBarrelType` for the request's `User`, or nil
    /// if none exists.
    ///
    /// - Parameters:
    ///   - user: The user who owns the barrel.
    ///   - req: The incoming `Request`, on whose event loop this must run.
    /// - Returns: `Barrel` of the required type, or `nil`.
    func getTaggedBarrel(for user: User, on req: Request) throws -> Future<Barrel?> {
        return try Barrel.query(on: req)
            .filter(\.ownerID == user.requireID())
            .filter(\.barrelType == favoriteBarrelType)
            .first()
            .map {
                (barrel) in
                guard let barrel = barrel else {
                    return nil
                }
                return barrel
        }
    }
}
