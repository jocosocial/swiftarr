import Vapor
import Crypto
import FluentSQL
import Redis

/// The collection of `/api/v3/user/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct UsersController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/users endpoints
        let usersRoutes = router.grouped("api", "v3", "users")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let basicAuthGroup = usersRoutes.grouped([basicAuthMiddleware, guardAuthMiddleware])
        let sharedAuthGroup = usersRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = usersRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        sharedAuthGroup.get(User.parameter, "profile", use: profileHandler)
        
        // endpoints available only when logged in

    }
    
    // MARK: - Open Access Handlers
    
    
    // MARK: - sharedAuthGroup Handlers (logged in OR out)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/user/ID/profile`
    ///
    /// Retrieves the user's own profile data for editing, as a `UserProfile.Edit` object.
    ///
    /// This endpoint can be reached with either Basic or Bearer authenticaton, so that a user
    /// can customize their profile even if they do not yet have their registration code.
    ///
    /// - Note: The `.username` and `.displayedName` properties of the returned object
    ///   are for display convenience only. A username must be changed using the
    ///   `POST /api/v3/user/username` endpoint. The displayedName property is generated from
    ///   the username and displayName values.
    ///
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: A `UserProfile.Edit` object containing the editable properties of the
    ///   profile.
    func profileHandler(_ req: Request) throws -> Future<UserProfile.Public> {
        let requester = try req.requireAuthenticated(User.self)
        // get requested user
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // a .banned profile is only available to .moderator or above
            if user.accessLevel == .banned
                && requester.accessLevel.rawValue < UserAccessLevel.moderator.rawValue {
                throw Abort(.notFound, reason: "profile is not available")
            }
            // get profile and convert to .Public
            return try user.profile.query(on: req).first().flatMap {
                (profile) in
                guard let profile = profile, let profileID = profile.id else {
                    throw Abort(.internalServerError, reason: "profile not found")
                }
                let publicProfile = try profile.convertToPublic()
                // if auth type is Basic, requestor is not logged in, so hide info if
                // `.limitAccess` is true or requestor is .banned
                if (req.http.headers.basicAuthorization != nil && profile.limitAccess)
                    || requester.accessLevel == .banned {
                    publicProfile.about = ""
                    publicProfile.email = ""
                    publicProfile.homeLocation = ""
                    publicProfile.message = "You must be logged in to view this user's Profile details."
                    publicProfile.preferredPronoun = ""
                    publicProfile.realName = ""
                    publicProfile.roomNumber = ""
                }
                // include UserNote if any, then return
                return try requester.notes.query(on: req)
                    .filter(\.profileID == profileID)
                    .first()
                    .map {
                        (note) in
                        if let note = note {
                            publicProfile.note = note.note
                        }
                        return publicProfile
                }
            }
        }
    }
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    
    // MARK: - Helper Functions
}

// MARK: - Helper Structs
