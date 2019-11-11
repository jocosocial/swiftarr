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
        
        // endpoints available only when not logged in
        basicAuthGroup.post(UserVerifyData.self, at: "register", use: verifyHandler)
        
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
    ///   - data: `UserCreateData` struct containing the user's desired username and password.
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
                    verification: nil,
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
    
    /// `POST /api/v3/user/verify`
    ///
    /// Changes a `User.accessLevel` from `.unverified` to `.verified` on successful submission
    /// of a registration code.
    ///
    /// - Requires: `UserVerifyData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming request `Container`, provided automatically.
    ///   - data: `UserVerifyData` struct containing a registration code.
    /// - Throws: 400 error if the user is already verified or the registration code is not
    ///   a valid one. 409 error if the registration code has already been allocated to
    ///   another user.
    /// - Returns: HTTP status 200 on success.
    func verifyHandler(_ req: Request, data: UserVerifyData) throws -> Future<HTTPResponseStatus> {
        let user = try req.requireAuthenticated(User.self)
        // return if user is already verified
        guard user.verification == nil else {
            let responsStatus = HTTPResponseStatus(
                statusCode: 400,
                reasonPhrase: "user is already verified"
            )
            throw Abort(responsStatus)
        }
        // see `UserVerifyData.validations()`
        try data.validate()
        // check that it's a valid code
        return RegistrationCode.query(on: req)
            .filter(\.code == data.verification)
            .first()
            .flatMap {
                (existingCode) in
                // does code exist?
                guard let registrationCode = existingCode else {
                    let responseStatus = HTTPResponseStatus(
                        statusCode: 400,
                        reasonPhrase: "registration code not found"
                    )
                    throw Abort(responseStatus)
                }
                // is code already used?
                guard registrationCode.userID == nil else {
                    let responseStatus = HTTPResponseStatus(
                        statusCode: 409,
                        reasonPhrase: "registration code has already been used"
                    )
                    throw Abort(responseStatus)
                }
                // update models and return 200
                return req.transaction(on: .psql) {
                    (connection) in
                    // update registrationCode
                    registrationCode.userID = try user.requireID()
                    return registrationCode.save(on: connection).flatMap {
                        (savedCode) in
                        // update user
                        user.accessLevel = .verified
                        user.verification = registrationCode.code
                        return user.save(on: connection).transform(to: .ok)
                    }
                }
        }
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
}

/// Used by `UserController.verifyHandler(_:)` to verify a created but unverified
/// account.
struct UserVerifyData: Content {
    /// The registration code provided to the user.
    let verification: String
}

extension UserCreateData: Validatable, Reflectable {
    /// Validates that `.username` is 1 or more alphanumeric characters,
    /// and `.password` is least 6 characters in length.
    static func validations() throws -> Validations<UserCreateData> {
        var validations = Validations(UserCreateData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics))
        try validations.add(\.password, .count(6...))
        return validations
    }
}

extension UserVerifyData: Validatable, Reflectable {
    /// Validates that a `.verification` registration code is either 6 or 7 alphanumeric
    /// characters in length (allows for inclusion or exclusion of the space).
    static func validations() throws -> Validations<UserVerifyData> {
        var validations = Validations(UserVerifyData.self)
        try validations.add(\.verification, .count(6...7) && .characterSet(.alphanumerics))
        return validations
    }
}
