import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/client/*` route endpoints and handler functions that provide
/// bulk retrieval services for registered API clients.

struct ClientController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/client endpoints
        let clientRoutes = router.grouped("api", "v3", "client")
        
        // instantiate authentication middleware
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let tokenAuthGroup = clientRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        
        // endpoints available only when logged in
        tokenAuthGroup.get("user", "headers", "since", String.parameter, use: userHeadersHandler)
        tokenAuthGroup.get("user", "updates", "since", String.parameter, use: userUpdatesHandler)
        tokenAuthGroup.get("usersearch", use: userSearchHandler)
    }
    
    // MARK: - Open Access Handlers
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // *or* HTTP Bearer Authentication header in the request.
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `GET /api/v3/client/user/headers/since/DATE`
    ///
    /// Retrieves the `UserHeader` of all users with a `.profileUpdatedAt` timestamp
    /// later than the specified date. The `DATE` parameter is a string, and may be provided
    /// in either of two formats:
    ///
    /// * a string literal `Double` (e.g. "1574364935" or "1574364935.88991")
    /// * an ISO 8601 `yyyy-MM-dd'T'HH:mm:ssZ` string (e.g. "2019-11-21T05:31:28Z")
    ///
    /// The second format is precisely what is returned in `swiftarr` JSON responses, while
    /// the numeric form makes for a prettier URL.
    ///
    /// - Requires: `x-swiftarr-user` header in the request.
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if no valid date string provided. 401 error if the required header
    ///   is missing or invalid. 403 error if user is not a registered client.
    /// - Returns: `[UserHeader]` array of all updated users.
    func userHeadersHandler(_ req: Request) throws -> Future<[UserHeader]> {
        let client = try req.requireAuthenticated(User.self)
        // must be registered client
        guard client.accessLevel == .client else {
            throw Abort(.forbidden, reason: "registered clients only")
        }
        // must be on behalf of user
        guard let userHeader = req.http.headers["x-swiftarr-user"].first,
            let userID = UUID(uuidString: userHeader) else {
                throw Abort(.unauthorized, reason: "no valid 'x-swiftarr-user' header found")
        }
        // find user
        return User.find(userID, on: req)
            .unwrap(or: Abort(.unauthorized, reason: "'x-swiftarr-user' user not found"))
            .flatMap {
                (user) in
                guard user.accessLevel != .client else {
                    throw Abort(.unauthorized, reason: "'x-swiftarr-user' user cannot be client")
                }
                // parse date parameter
                let since = try req.parameters.next(String.self)
                guard let date = ClientController.dateFromParameter(string: since) else {
                    throw Abort(.badRequest, reason: "'\(since)' is not a recognized date format")
                }
                // remove blocked users
                let cache = try req.keyedCache(for: .redis)
                let key = try "blocks:\(user.requireID())"
                let cachedBlocks = cache.get(key, as: [UUID].self)
                return cachedBlocks.flatMap {
                    (blocks) in
                    let blocked = blocks ?? []
                    // return UserHeader array
                    return UserProfile.query(on: req)
                        .filter(\.updatedAt > date)
                        .filter(\.userID !~ blocked)
                        .all()
                        .map {
                            (profiles) in
                            let headers = try profiles.map { try $0.convertToHeader() }
                            return headers
                    }
                }
        }
    }
    
    /// `GET /api/v3/client/usersearch`
    ///
    /// Retrieves all `UserProfile.userSearch` values, returning an array of precomposed
    /// `.userSearch` strings in `UserSearch` format. The intended use for this data
    /// is to efficiently isolate a particular user in an auto-complete type scenario, using
    /// **all** of the `.displayName`, `.username` and `.realName` profile fields.
    ///
    /// - Requires: `x-swiftarr-user` header in the request.
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if no valid date string provided. 401 error if the required header
    ///   is missing or invalid. 403 error if user is not a registered client.
    /// - Returns: `[UserSearch]` containing the ID and `.userSearch` string values
    ///   of all users, sorted by username.
    func userSearchHandler(_ req: Request) throws -> Future<[UserSearch]> {
        let client = try req.requireAuthenticated(User.self)
        // must be registered client
        guard client.accessLevel == .client else {
            throw Abort(.forbidden, reason: "registered clients only")
        }
        // must be on behalf of user
        guard let userHeader = req.http.headers["x-swiftarr-user"].first,
            let userID = UUID(uuidString: userHeader) else {
                throw Abort(.unauthorized, reason: "no valid 'x-swiftarr-user' header found")
        }
        // find user
        return User.find(userID, on: req)
            .unwrap(or: Abort(.unauthorized, reason: "'x-swiftarr-user' user not found"))
            .flatMap {
                (user) in
                // must be actual user
                guard user.accessLevel != .client else {
                    throw Abort(.unauthorized, reason: "'x-swiftarr-user' user cannot be client")
                }
                // remove blocked users
                let cache = try req.keyedCache(for: .redis)
                let key = try "blocks:\(user.requireID())"
                let cachedBlocks = cache.get(key, as: [UUID].self)
                return cachedBlocks.flatMap {
                    (blocks) in
                    let blocked = blocks ?? []
                    return UserProfile.query(on: req)
                        .filter(\.userID !~ blocked)
                        .sort(\.username, .ascending)
                        .all()
                        .map {
                            (profiles) in
                            // return as [UserSearch]
                            return try profiles.map { try $0.convertToSearch() }
                    }
                }
        }
    }
    
    /// `GET /api/v3/client/user/updates/since/DATE`
    ///
    /// Retrieves the `UserInfo` of all users with a `.profileUpdatedAt` timestamp later
    /// than the specified date. The `DATE` parameter is a string, and may be provided in
    /// either of two formats:
    ///
    /// * a string literal `Double` (e.g. "1574364935" or "1574364935.88991")
    /// * an ISO 8601 `yyyy-MM-dd'T'HH:mm:ssZ` string (e.g. "2019-11-21T05:31:28Z")
    ///
    /// The second format is precisely what is returned in `swiftarr` JSON responses, while
    /// the numeric form makes for a prettier URL.
    ///
    /// - Requires: `x-swiftarr-user` header in the request.
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if no valid date string provided. 401 error if the required header
    ///   is missing or invalid. 403 error if user is not a registered client.
    /// - Returns: `[UserInfo]` containing all updated users.
    func userUpdatesHandler(_ req: Request) throws -> Future<[UserInfo]> {
         let client = try req.requireAuthenticated(User.self)
        // must be registered client
        guard client.accessLevel == .client else {
            throw Abort(.forbidden, reason: "registered clients only")
        }
        // must be on behalf of user
        guard let userHeader = req.http.headers["x-swiftarr-user"].first,
            let userID = UUID(uuidString: userHeader) else {
                throw Abort(.unauthorized, reason: "no valid 'x-swiftarr-user' header found")
        }
        // find user
        return User.find(userID, on: req)
            .unwrap(or: Abort(.unauthorized, reason: "'x-swiftarr-user' user not found"))
            .flatMap {
                (user) in
                guard user.accessLevel != .client else {
                    throw Abort(.unauthorized, reason: "'x-swiftarr-user' user cannot be client")
                }
                // parse date parameter
                let since = try req.parameters.next(String.self)
                guard let date = ClientController.dateFromParameter(string: since) else {
                    throw Abort(.badRequest, reason: "'\(since)' is not a recognized date format")
                }
                // remove blocked users
                let cache = try req.keyedCache(for: .redis)
                let key = try "blocks:\(user.requireID())"
                let cachedBlocks = cache.get(key, as: [UUID].self)
                return cachedBlocks.flatMap {
                    (blocks) in
                    let blocked = blocks ?? []
                    return User.query(on: req)
                        .filter(\.profileUpdatedAt > date)
                        .filter(\.id !~ blocked)
                        .all()
                        .map {
                            (users) in
                            // return as [UserInfo]
                            return try users.map { try $0.convertToInfo() }
                    }
                }
        }
    }
    
    // MARK: - Helper Functions
}
