import Vapor
import Crypto
import FluentSQL
import Fluent
import Redis

/// The collection of `/api/v3/forum/*` route endpoints and handler functions related
/// to forums.

struct ForumController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/forum endpoints
        let forumRoutes = router.grouped("api", "v3", "forum")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let basicAuthGroup = forumRoutes.grouped([basicAuthMiddleware, guardAuthMiddleware])
        let sharedAuthGroup = forumRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = forumRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        
        // endpoints available only when logged in
    }
    
    // MARK: - Open Access Handlers
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
}
