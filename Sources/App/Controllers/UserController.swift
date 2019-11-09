import Vapor
import Crypto
import FluentSQL

/// The collection of `/api/v3/user/*` route endpoints and handler functions related
/// to a user's own data.
///
/// Separating these from the endpoints related to users in general helps make for a
/// cleaner collection, since use of `User.parameter` in the paths here can be avoided
/// entirely.

struct UserController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/user endpoints
        let userRoutes = router.grouped("api", "v3", "user")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let basicAuthGroup = userRoutes.grouped(basicAuthMiddleware)
        let tokenAuthGroup = userRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        userRoutes.post(UserCreateData.self, at: "create", use: createHandler)
        
        // endpoints available only when logged in
        
    }
    
    // MARK: - Open Access Handlers
    
    /// `POST /api/v3/user/create`
    ///
    /// Creates a new `User` account and its associated `UserProfile`. If either fail, neither
    /// is created, since we want to ensure that all accounts have profiles.
    ///
    /// A `CreatedUserData` structure is returned on success, containing the new user's ID,
    /// username and a generated recovery key.
    ///
    /// - Note: The `CreatedUserData.recoveryKey` is a random phrase used to recover an account
    ///   in the case of a forgotten password. While it can be stored by a client, that
    ///   essentially defeats its purpose (presumably the password would also already be
    ///   stored). The *intended client use* is that it is displayed to the user upon successful
    ///   creation, and the user is *encouraged to take a screenshot or write it down before
    ///   proceeding*.
    ///
    /// - Requires: `UserCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `UserCreateData` struct containing the desired username, password and
    ///   (optionally) the registration code.
    /// - Throws: 409 if the username is not available. A 5xx response should be reported as a
    ///   likely bug, please and thank you.
    /// - Returns: The newly created user's ID, username, and a recovery key string
    func createHandler(_ req: Request, data: UserCreateData) throws -> Future<CreatedUserData> {
        // see `UserCreateData.validations()`
        try data.validate()
        // check for existing username so we can return 409 Conflict status instead
        // of the default super-unfriendly 500 for unique constraint violation
        return User.query(on: req)
            .filter(\.username == data.username)
            .first()
            .flatMap {
                (existingUser) in
                // abort if name is already taken
                if existingUser != nil {
                    let responseStatus = HTTPResponseStatus(
                        statusCode: 409,
                        reasonPhrase: "username '\(data.username)' is not available"
                    )
                    throw Abort(responseStatus)
                }
                
                // create recovery key
                let recoveryKey = generateRecoveryKey()
                let normalizedKey = recoveryKey.lowercased().replacingOccurrences(of: " ", with: "")
                
                // create user
                let passwordHash = try BCrypt.hash(data.password)
                let recoveryHash = try BCrypt.hash(normalizedKey)
                let user = User(
                    username: data.username,
                    password: passwordHash,
                    recoveryKey: recoveryHash,
                    // store normalized registration code if supplied, else `nil`
                    verification: data.verification?.lowercased().replacingOccurrences(of: " ", with: ""),
                    parentID: nil,
                    accessLevel: .unverified
                )
                // wrap in a transaction to ensure each user has an associated profile
                // (creates both, or neither)
                return req.transaction(on: .psql) {
                    (connection) in
                    return user.save(on: connection).flatMap {
                        (savedUser) in
                        // create profile
                        guard let id = savedUser.id else {
                            throw Abort(.internalServerError)
                        }
                        let profile = UserProfile(userID: id, username: savedUser.username)
                        return profile.save(on: connection).map {
                            (savedProfile) in
                            let createdUserData = CreatedUserData(
                                userID: id,
                                username: savedUser.username,
                                recoveryKey: recoveryKey
                            )
                            return createdUserData
                        }
                    }
                }
        }
    }
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    func verificationHandler(_ req: Request, data: UserVerificationData) throws -> Future<HTTPResponseStatus> {
        let user = try req.requireAuthenticated(User.self)
        // see `userVerificationData.validations()`
        try data.validate()
        return req.future(.ok)
    }

    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
}

// MARK: - Helper Functions

private func generateRecoveryKey() -> String {
    // FIXME: implement actual recovery key generation
    return "recovery key"
}

// MARK: - Helper Structs

/// Returned by `UserController.createHandler(_:data:).`
struct CreatedUserData: Content {
    /// The newly created user's ID.
    let userID: UUID
    /// The newly created user's username
    let username: String
    /// If an optional `UserCreateData.verification` registration code was supplied in the
    /// request and this is a primary account, the generated recovery key, otherwise `nil`.
    /// A recoveryKey is generated only upon receipt of a successful registration.
    let recoveryKey: String?
}

/// Used by `UserController.createHandler(_:data:) for initial creation of an account.
struct UserCreateData: Content {
    /// The user's username.
    let username: String
    /// The user's password.
    let password: String
    /// The registration code provided to the user. Optional during creation.
    let verification: String?
}

/// Used by `UserController.verificationHandler(_:)` to verify a created but unverified
/// account.
struct UserVerificationData: Content {
    /// The registration code provided to the user.
    let verification: String
}

extension UserCreateData: Validatable, Reflectable {
    /// Validates that a .username is 1 or more alphanumeric characters,
    /// .password is least 6 characters in length,
    /// and that an optional .verification code is either 6 or 7 characters.
    /// (depending on if it includes a space) in length if present.
    static func validations() throws -> Validations<UserCreateData> {
        var validations = Validations(UserCreateData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics))
        try validations.add(\.password, .count(6...))
        try validations.add(\.verification, .count(6...7) || .nil)
        return validations
    }
}
