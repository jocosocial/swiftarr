import Vapor
import Crypto
import FluentSQL

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
                    verification: data.verification?.lowercased().replacingOccurrences(of: " ", with: "") ?? nil,
                    parentID: nil,
                    accessLevel: .unverified
                )
                // save user
                return user.save(on: req).flatMap {
                    (savedUser) in
                    guard let id = savedUser.id else {
                        throw Abort(.internalServerError)
                    }
                    // create profile
                    let profile = UserProfile(userID: id, username: savedUser.username)
                    return profile.save(on: req).map {
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
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // header in the post request.
    
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authorization
    // header in the post request.
    
}


// MARK: - Helper Functions

private func generateRecoveryKey() -> String {
    // FIXME: implement actual recovery key generation
    return "recovery key"
}

// MARK: - Helper Structs

/// Returned by `UserController.createHandler(_:data:).`
struct CreatedUserData: Content {
    // The newly created user's ID.
    let userID: UUID
    // The newly created user's username
    let username: String
    // If an optional `UserCreateData.verification` registration code was supplied in the
    // request and this is a primary account, the generated recovery key, otherwise `nil`.
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

extension UserCreateData: Validatable, Reflectable {
    /// Validates that a .username is 1 or more alphanumeric characters,
    /// .password is least 6 characters in length,
    /// and that an optional .verification code is either 6 or 7 characters
    /// (depending on if it includes a space) in length if present.
    static func validations() throws -> Validations<UserCreateData> {
        var validations = Validations(UserCreateData.self)
        try validations.add(\.username, .count(1...) && .characterSet(.alphanumerics))
        try validations.add(\.password, .count(6...))
        try validations.add(\.verification, .count(6...7) || .nil)
        return validations
    }
    
    
}
