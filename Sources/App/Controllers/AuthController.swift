import Vapor
import Authentication
import FluentSQL

/// The collection of `/api/v3/auth/*` route endpoints and handler functions related
/// to authentication.
///
/// API v3 requires the use of either `HTTP Basic Authentication`
/// ([RFC7617](https://tools.ietf.org/html/rfc7617)) or `HTTP Bearer Authentication` (based on
/// [RFC6750](https://tools.ietf.org/html/rfc6750#section-2.1)) for virtually all endpoint
/// access, with very few exceptions carved out for fully public data (such as the Event
/// Schedule). The query-based `&key=` scheme used in v2 is not supported at all.
///
/// This means that essentially all HTTP requests ***must*** contain an `Authorization` header.
///
/// A valid `HTTP Basic Authentication` header resembles:
///
///     Authorization: Basic YWRtaW46cGFzc3dvcmQ=
///
/// The data value in a Basic header is the base64-encoded utf-8 string representation of the
/// user's username and password, separated by a colon. In Swift, a one-off version might resemble
/// something along the lines of:
///
///     var request = URLRequest(...)
///     let credentials = "username:password".data(using: .utf8).base64encodedString()
///     request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
///     ...
///
/// Successful execution of sending this request to the login endpoint returns a JSON-encoded
/// token string:
///
///     {
///         "token": "y+jiK8w/7Ta21m/O8F2edw=="
///     }
///
/// which is then used in `HTTP Bearer Authentication` for all subsequent requests:
///
///     Authorization: Bearer y+jiK8w/7Ta21m/O8F2edw==
///
/// A generated token string remains valid across all clients on all devices until the user
/// explicitly logs out, or it otherwise expires or is administratively deleted. If the user
/// explicitly logs out on *any* client on *any* device, the token is deleted and the
/// `/api/v3/auth/login` endpoint will need to be hit again to generate a new one.

struct AuthController: RouteCollection {
    
    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/auth endpoints
        let authRoutes = router.grouped("api", "v3", "auth")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let basicAuthGroup = authRoutes.grouped(basicAuthMiddleware)
        let tokenAuthGroup = authRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        authRoutes.post(RecoveryData.self, at: "recovery", use: recoveryHandler)
        
        // endpoints available only when not logged in
        basicAuthGroup.post("login", use: loginHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.post("logout", use: logoutHandler)
    }
    
    // MARK: - Open Access Handlers
    
    /// `POST /api/v3/auth/recovery`
    ///
    /// Attempts to authorize the user using a combination of `User.username` and *any one* of
    /// the `User.verification` (registration code), `User.password` or `User.recoveryKey`
    /// (returned by `UserController.createHandler(_:)`) values.
    ///
    /// The use case is a forgotten password. While an API client has probably stored the
    /// information internally, that doesn't necessarily help if the user is setting up another
    /// client or on another device, and is even less likely to be of use for logging into the
    /// web front end.
    ///
    /// The intended API client flow here is (a) use this endpoint to obtain an `HTTP Bearer
    /// Authentication` token upon success, then (b) use the returned token to immediately
    /// `POST` to the `/api/v3/user/password` endpoint for password change/reset.
    ///
    /// - Note: To prevent brute force malicious attempts, there is a limit on successive
    /// failed recovery attempts, currently hard-coded to 10.
    ///
    /// - Requires: `RecoveryData` payload in the HTTP body.
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Parameter data: `RecoveryData` struct containing the username and recoveryKey
    /// pair to attempt.
    /// - Throws: 400 error if the recovery fails. 403 error if the maximum number of successive
    /// failed recovery attempts has been reached. A 5xx response should be reported as a
    /// likely bug, please and thank you.
    /// - Returns: An authentication token (string) that should be used for all subsequent
    /// HTTP requests, until expiry or revocation.
    
    func recoveryHandler(_ req: Request, data: RecoveryData) throws -> Future<TokenStringData> {
        // find data.username user
        return User.query(on: req)
            .filter(\.username == data.username)
            .first()
            .flatMap {
                (existingUser) in
                // abort if user not found
                guard let user = existingUser else {
                    let responseStatus = HTTPResponseStatus(
                        statusCode: 400,
                        reasonPhrase: "username \"\(data.username)\" not found"
                    )
                    throw Abort(responseStatus)
                }
                // abort if account is seeing potential malicious activity
                guard user.recoveryAttempts < 10 else {
                    let responseStatus = HTTPResponseStatus(
                        statusCode: 403,
                        reasonPhrase: "please see a Twit-arr Team member for password recovery"
                    )
                    throw Abort(responseStatus)
                }
                
                // attempt data.recoveryKey match
                var foundMatch = false
                // registration codes are normalized prior to storage
                let normalizedKey = data.recoveryKey.lowercased().replacingOccurrences(of: " ", with: "")
                if normalizedKey == user.verification {
                    foundMatch = true
                } else {
                    // password and recoveryKey require hash verification
                    let verifier = BCryptDigest()
                    if try verifier.verify(data.recoveryKey, created: user.password) {
                        foundMatch = true
                    } else {
                        // user.recoveryKey is normalized prior to hashing
                        if try verifier.verify(normalizedKey, created: user.recoveryKey) {
                            foundMatch = true
                        }
                    }
                }
                // abort if no match
                guard foundMatch else {
                    // track the attempt count
                    user.recoveryAttempts += 1
                    _ = user.save(on: req)
                    
                    let responseStatus = HTTPResponseStatus(
                        statusCode: 400,
                        reasonPhrase: "no match for supplied recovery key"
                    )
                    throw Abort(responseStatus)
                }
                
                // user appears valid, zero out attempt tracking
                user.recoveryAttempts = 0
                _ = user.save(on: req)
                
                // return existing token if any
                return try Token.query(on: req)
                    .filter(\.userID == user.requireID())
                    .first()
                    .flatMap {
                        (existingToken) in
                        if let existing = existingToken {
                            return req.future(TokenStringData(token: existing))
                        } else {
                            // otherwise generate and return new token
                            let token = try Token.generate(for: user)
                            return token.save(on: req).map {
                                (savedToken) in
                                return TokenStringData(token: savedToken)
                            }
                        }
                }
        }
    }
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // header in the post request.
    
    /// `POST /api/v3/auth/login`
    ///
    /// Our basic login handler that utilizes the user's username and password.
    ///
    /// The login credentials are expected to be provided using `HTTP Basic Authentication`.
    /// That is, a base64-encoded utf-8 string representation of the user's username and
    /// password, separated by a colon ("username:password"), in the `Authorization` header
    /// of the `POST`request. For example:
    ///
    ///     let credentials = "username:password".data(using: .utf8).base64encodedString()
    ///     request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
    ///
    /// would generate an HTTP header of:
    ///
    ///     Authorization: Basic YWRtaW46cGFzc3dvcmQ=
    ///
    /// There is no payload in the HTTP body; this header field carries all the necessary
    /// data. The token string returned by successful execution of this login handler
    ///
    ///     {
    ///         "token": "y+jiK8w/7Ta21m/O8F2edw=="
    ///     }
    ///
    /// is then used for `HTTP Bearer Authentication` in all subsequent requests:
    ///
    ///     Authorization: Bearer y+jiK8w/7Ta21m/O8F2edw==
    ///
    /// In order to support the simultaneous use of multiple clients and/or devices by a
    /// single user, any existing token will be returned in lieu of generating a new one.
    /// A token will remain valid until the user explicitly logs out (or it otherwise
    /// expires or is administratively revoked), at which point this endpoint will need to
    /// be hit again to generate a new token.
    ///
    /// - Note: API v2 query parameter style logins and subsequent key submissions are
    /// **not** supported in API v3.
    ///
    /// - Requires: `User.accessLevel` other than `.banned`.
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 401 error if the Basic authentication fails. 403 error if the user is
    /// banned. A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: An authentication token (string) that should be used for all subsequent
    /// HTTP requests, until expiry or revocation.
    func loginHandler(_ req: Request) throws -> Future<TokenStringData> {
        let user = try req.requireAuthenticated(User.self)
        // no login for punks
        guard user.accessLevel != .banned else {
            throw Abort(.forbidden)
        }
        // return existing token if one exists
        return try Token.query(on: req)
            .filter(\.userID == user.requireID())
            .first()
            .flatMap {
                (existingToken) in
                if let existing = existingToken {
                    return req.future(TokenStringData(token: existing))
                } else {
                    // otherwise generate and return new token
                    let token = try Token.generate(for: user)
                    return token.save(on: req).map {
                        (savedToken) in
                        return TokenStringData(token: savedToken)
                    }
                }
        }
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authorization
    // header in the post request.
    
    /// `POST /api/v3/auth/logout`
    ///
    /// Unauthenticates the user and deletes the user's authentication token. It is
    /// the responsibility of the client to respond appropriately to the returned
    /// `HTTPStatus`, which should be one of:
    ///
    /// * 204 No Content
    /// * 401 Unauthorized {"error": "true", "reason": "User not authenticated."}
    /// * 409 Conflict { "error": "true", "reason": "user is not logged in" }
    ///
    /// A 409 response most likely indicates a theoretically possible race condition.
    /// There is no side effect and it is likely harmless. But please do report a 409
    /// error if you encounter one, so that the specifics can be looked into.
    ///
    /// - Requires: Currently logged in.
    /// - Parameter req: The incoming request `Container`, provided automatically.
    /// - Throws: 401 error if the authentication failed. 409 error if the user somehow
    /// wasn't logged in. A 5xx response should be reported as a likely bug, please and
    /// thank you.
    /// - Returns: HTTPStatus response. 204 if the token was successfully deleted.
    func logoutHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        try req.unauthenticate(User.self)
        return try Token.query(on: req)
            .filter(\.userID == user.requireID())
            .first()
            .flatMap {
                (existingToken) in
                if let existing = existingToken {
                    return existing.delete(on: req).transform(to: HTTPStatus.noContent)
                } else {
                    let status = HTTPStatus(statusCode: 409, reasonPhrase: "user is not logged in")
                    return req.future(status)
                }
        }
    }
}

/// Used by `AuthController.recoveryHandler(_:data:)` for the incoming recovery attempt.
struct RecoveryData: Content {
    /// The user's username.
    let username: String
    /// The string to use – any one of: password / registration key / recovery key.
    let recoveryKey: String
}

/// Used by `AuthController.loginHandler(_:)` and `AuthController.recoveryHandler(_:data:)`
/// to return a token string upon successful execution.
struct TokenStringData: Content {
    /// The token string.
    let token: String
    /// Creates a `TokenStringData` from a `Token`.
    /// - Parameter token: The `Token` associated with the logged in user.
    init(token: Token) {
        self.token = token.token
    }
}
