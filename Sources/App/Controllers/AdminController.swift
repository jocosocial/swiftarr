import Vapor
import Crypto
import FluentSQL
import Redis

/// The collection of `/api/v3/admin/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct AdminController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/admin endpoints
        let adminRoutes = router.grouped("api", "v3", "admin")
        
        // instantiate authentication middleware
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let tokenAuthGroup = adminRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        
        // endpoints available only when not logged in
        
        // endpoints available only when logged in
        tokenAuthGroup.get("users", User.parameter, use: userHandler)
    }
    
    // MARK: - Open Access Handlers
    
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    

    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `GET /api/v3/admin/user/ID`
    ///
    /// Retrieves the full `User` model of the specified user.
    ///
    /// - Requires: `UserAccessLevel` of `.admin`.
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 403 error if the user is not an admin.
    /// - Returns: The specified user's `User` model.
    func userHandler(_ req: Request) throws -> Future<User> {
        let user = try req.requireAuthenticated(User.self)
        guard user.accessLevel == .admin else {
            throw Abort(.forbidden, reason: "admins only")
        }
        return try req.parameters.next(User.self)
    }
    
    // MARK: - Helper Functions

}

// MARK: - Helper Structs
