import Vapor
import Fluent

/// A `Protocol` for model objects that can be bookmarked.
/// Return content that can be bookmarked by the user on a per-model basis.

protocol UserBookmarkable {
    /// The barrel type to be used for bookmarked model ID storage.
    var bookmarkBarrelType: BarrelType { get }
    
    func bookmarkIDString() throws -> String
}

