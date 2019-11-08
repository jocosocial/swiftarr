import Vapor
import Crypto
import FluentSQL

/// The collection of `/api/v3/test/*` route endpoints and handler functions for unit
/// testing and benchmarking purposes.
///
/// - Note: These endpoints are **NOT** intended as API for client development.

struct TestController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/users endpoints
        let testRoutes = router.grouped("api", "v3", "test")
        
        // instantiate authentication middleware
//        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
//        let guardAuthMiddleware = User.guardAuthMiddleware()
//        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
//        let basicAuthGroup = testRoutes.grouped(basicAuthMiddleware)
//        let sharedAuthGroup = testRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware])
//        let tokenAuthGroup = testRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        testRoutes.get("getusers", use: getUsersHandler)
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out

        // endpoints available only when logged in
        
    }
    
    // MARK: - Open Access Handlers
    
    /// `GET /api/v3/test/getusers`
    ///
    /// Returns the first 10 users in the database.
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Returns: An array of at most the first 10 `User` models in the database.
    func getUsersHandler(_ req: Request) throws -> Future<[User]> {
        return User.query(on: req).range(..<10).all()
    }
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // *or* HTTP Bearer Authentication header in the request.

    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
}

// MARK: - Helper Functions

// MARK: - Helper Structs
