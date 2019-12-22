import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of /api/v3/fez/* route endpoints and handler functions related
/// to FriendlyFez/LFG barrels.

struct FezController: RouteCollection {
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/fez endpoints
        let fezRoutes = router.grouped("api", "v3", "fez")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let sharedAuthGroup = fezRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = fezRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // endpoints available whether logged in or not
        
        // endpoints available only when logged in
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
}


