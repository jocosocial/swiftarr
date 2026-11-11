import FluentSQL
import Vapor

/// The collection of `/api/v3/auth/*` route endpoints and handler functions related
/// to authentication.
///
/// API v3 requires the use of either `HTTP Basic Authentication`
/// ([RFC7617](https://tools.ietf.org/html/rfc7617)) or `HTTP Bearer Authentication` (based on
/// [RFC6750](https://tools.ietf.org/html/rfc6750#section-2.1)) for virtually all endpoint
/// access, with very few exceptions carved out for fully public data (such as the Event
/// Schedule).
///
/// This means that essentially all HTTP requests ***must*** contain an `Authorization` header.
///
///  - Important: The query-based `&key=` scheme used in v2 is not supported at all.
///
/// A valid `HTTP Basic Authentication` header resembles:
///
///	 Authorization: Basic YWRtaW46cGFzc3dvcmQ=
///
/// The data value in a Basic header is the base64-encoded utf-8 string representation of the
/// user's username and password, separated by a colon. In Swift, a one-off version might resemble
/// something along the lines of:
///
///	 var request = URLRequest(...)
///	 let credentials = "username:password".data(using: .utf8).base64encodedString()
///	 request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
///	 ...
///
/// Successful execution of sending this request to the login endpoint returns a JSON-encoded
/// token string:
///
///	 {
///		 "token": "y+jiK8w/7Ta21m/O8F2edw=="
///	 }
///
/// which is then used in `HTTP Bearer Authentication` for all subsequent requests:
///
///	 Authorization: Bearer y+jiK8w/7Ta21m/O8F2edw==
///
/// A generated token string remains valid across all clients on all devices until the user
/// explicitly logs out, or it otherwise expires or is administratively deleted. If the user
/// explicitly logs out on *any* client on *any* device, the token is deleted and the
/// `/api/v3/auth/login` endpoint will need to be hit again to generate a new one.

struct AuthController: APIRouteCollection {

	// MARK: RouteCollection Conformance

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/auth endpoints
		let authRoutes = app.grouped("api", "v3", "auth")

		// open access endpoints
		authRoutes.post("recovery", use: recoveryHandler)
		authRoutes.post("username", use: usernameHandler)

		// endpoints available only when not logged in
		let basicAuthGroup = authRoutes.addBasicAuthRequirement()
		basicAuthGroup.post("login", use: loginHandler).setUsedForPreregistration()

		// endpoints available only when logged in
		let tokenAuthGroup = authRoutes.addTokenAuthRequirement()
		tokenAuthGroup.post("logout", use: logoutHandler)
	}

	// MARK: - Open Access Handlers

	/// `POST /api/v3/auth/recovery`
	///
	/// Attempts to authorize the user using a combination of `User.username` and *any one* of
	/// the `User.verification` (registration code), `User.password` or `User.recoveryKey`
	/// (returned by `UserController.createHandler(_:data:)`) values.
	///
	/// The use case is a forgotten password. While an API client has probably stored the
	/// information internally, that doesn't necessarily help if the user is setting up another
	/// client or on another device, and is even less likely to be of use for logging into the
	/// web front end.
	///
	/// Upon successful authentication, the user's password is set to the `newPassword` value in the provided
	/// `UserRecoveryData`, the user's existing login token is revoked (logging them out of every client, device,
	/// and web session), and a new login `TokenStringData` is returned (the same struct returned by `/api/v3/login`).
	///
	/// - Note: The `User.verification` registration code can only be used to recover *once*.
	///   This limitation is to prevent a possible race condition in which a malicious
	///   user has obtained another's registration code. After one successful recovery has
	///   been executed via the code, subsequent recovery can only be done via the recoveryKey
	///   provided during initial account creation.
	///
	/// - Note: To prevent brute-force malicious attempts, there is a limit on successive
	///   failed recovery attempts, currently hard-coded to 5.
	///
	/// - Note: An unknown username fails with the same 400 as a wrong recovery key, so this endpoint can't be used
	///   to discover which usernames exist.
	///
	/// - Parameter requestBody: `UserRecoveryData`
	/// - Throws: 400 error if the recovery fails. 403 error if the maximum number of successive
	///   failed recovery attempts has been reached, or if the credentials match a banned user.
	///   A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `TokenStringData` containing a new authentication token (string) that should
	///   be used for all subsequent HTTP requests, until expiry or revocation.
	func recoveryHandler(_ req: Request) async throws -> TokenStringData {
		// see `UserRecoveryData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserRecoveryData.self, fromBodyOf: req)
		let isRegistrationCode = RegistrationCode.isWellFormed(data.recoveryKey)
		let noMatch = Abort(.badRequest, reason: "no match for supplied recovery key")
		// find data.username user
		guard let user = try await User.query(on: req.db).filter(\.$username, .custom("ilike"), data.username).first()
		else {
			// Spend the same bcrypt time as the wrong-key path below (password, then recovery key), so an unknown
			// username can't be told apart from a real one.
			if !isRegistrationCode {
				await CryptoHelper.dummyPasswordVerify(data.recoveryKey, on: req)
				await CryptoHelper.dummyRecoveryKeyVerify(data.recoveryKey, on: req)
			}
			throw noMatch
		}
		// abort if account is seeing potential brute-force attack
		guard user.recoveryAttempts < 5 else {
			throw Abort(.forbidden, reason: "please see a Twit-arr Team member for password recovery")
		}

		// Registration codes are normalized (lowercase, all whitespace stripped) prior to storage.
		// Recovery keys are hashed after ASCII spaces are removed; passwords are matched as typed.
		var foundMatch = false
		if isRegistrationCode {
			// A 6-character alphanumeric key is a registration code, not a password or recovery key.
			// Spent codes are stored with a '*' prefix on User.verification; do not fall through.
			let normalizedKey = RegistrationCode.normalized(data.recoveryKey)
			if let stored = user.unspentVerification, RegistrationCode.normalized(stored) == normalizedKey {
				// Only explain that the code is spent to a caller who submitted the right code.
				if user.verificationUsed {
					throw Abort(
						.badRequest,
						reason: "account must be recovered using the recovery key or an account manager"
					)
				}
				foundMatch = true
				user.markVerificationUsed()
			}
		}
		else {
			// password and recoveryKey require hash verification
			if try await req.password.async.verify(data.recoveryKey, created: user.password) {
				foundMatch = true
			}
			else {
				// user.recoveryKey is hashed from the 3-word key with ASCII spaces removed
				let normalizedRecoveryKey = data.recoveryKey.lowercased().replacingOccurrences(of: " ", with: "")
				if try await req.password.async.verify(normalizedRecoveryKey, created: user.recoveryKey) {
					foundMatch = true
				}
			}
		}
		// abort if no match
		guard foundMatch else {
			// track the attempt count
			user.recoveryAttempts += 1
			try await user.save(on: req.db)
			throw noMatch
		}
		// no login for punks. Checked after the credentials so ban status is only revealed to the account holder.
		guard user.accessLevel != .banned else {
			throw Abort(.forbidden, reason: "User is banned, and cannot login.")
		}

		// user appears valid, zero out attempt tracking and save new password
		user.recoveryAttempts = 0
		user.password = try await req.password.async.hash(data.newPassword)

		// Whoever had the old password may still be logged in; revoke that login and issue a fresh token. The password reset
		// and the token are saved together, so a failure can't leave the account recovered (and a one-time registration
		// code spent) without the client getting a token.
		return try await AuthController.rotateToken(for: user, on: req)
	}

	/// `POST /api/v3/auth/username`
	///
	/// Looks up a forgotten username from a registration code plus a second factor. The second
	/// factor must be the account password or the recovery key generated at account creation.
	/// A registration code is not accepted as the second factor — even the same code, and even
	/// a different well-formed 6-character code.
	///
	/// The use case is a forgotten username during preregistration or later. The caller already
	/// has a registration code (mailed before the cruise) and either the password they chose
	/// or the recovery key shown when the account was created.
	///
	/// If the password matches a sub-account, that sub-account's `UserHeader` is returned. The
	/// recovery key is shared across a primary account and its alts, so a recovery-key match
	/// returns the primary account.
	///
	/// Username lookup does not spend the registration code and does not log the user in.
	///
	/// - Note: To prevent brute-force malicious attempts, there is a limit on successive
	///   failed attempts, currently hard-coded to 5, shared with password recovery.
	///
	/// - Parameter requestBody: `UserUsernameLookupData`
	/// - Throws: 400 error if the lookup fails or the second factor is a registration code.
	///   403 error if the maximum number of successive failed recovery attempts has been reached.
	/// - Returns: `UserHeader` for the matching account.
	func usernameHandler(_ req: Request) async throws -> UserHeader {
		// see `UserUsernameLookupData.validations()`
		let data = try ValidatingJSONDecoder().decode(UserUsernameLookupData.self, fromBodyOf: req)
		let storedCodes = User.storedVerificationValues(for: data.registrationCode)

		let users = try await User.query(on: req.db).filter(\.$verification ~~ storedCodes).all()

		// Same generic failure for unknown codes and bad second factors so a valid
		// registration code is not distinguishable from a made-up one.
		let noMatch = Abort(.badRequest, reason: "no match for supplied credentials")
		guard !users.isEmpty else {
			throw noMatch
		}

		// abort if account is seeing potential brute-force attack
		guard users.allSatisfy({ $0.recoveryAttempts < 5 }) else {
			throw Abort(.forbidden, reason: "please see a Twit-arr Team member for account recovery")
		}

		// Prefer a password match (identifies a specific primary or alt) over a recovery-key
		// match (shared across the family). Walk primaries first so a recovery-key-only hit
		// returns the account the registration code was originally assigned to.
		let orderedUsers = users.sorted { lhs, rhs in
			lhs.$parent.id == nil && rhs.$parent.id != nil
		}
		var passwordMatch: User?
		var recoveryKeyMatch: User?
		for user in orderedUsers {
			// password is matched as typed
			if try await req.password.async.verify(data.recoveryKey, created: user.password) {
				passwordMatch = user
				break
			}
			// recoveryKey is hashed from the 3-word key with ASCII spaces removed
			if recoveryKeyMatch == nil {
				let normalizedRecoveryKey = data.recoveryKey.lowercased().replacingOccurrences(of: " ", with: "")
				if try await req.password.async.verify(normalizedRecoveryKey, created: user.recoveryKey) {
					recoveryKeyMatch = user
				}
			}
		}

		// abort if no match
		guard let matched = passwordMatch ?? recoveryKeyMatch else {
			// track the attempt count on every account sharing this registration code
			for user in users {
				user.recoveryAttempts += 1
				try await user.save(on: req.db)
			}
			throw noMatch
		}

		return try UserHeader(user: matched)
	}

	// MARK: - basicAuthGroup Handlers (not logged in)
	// All handlers in this route group require a valid HTTP Basic Authentication
	// header in the request.

	/// `POST /api/v3/auth/login`
	///
	/// Our basic login handler that utilizes the user's username and password.
	///
	/// The login credentials are expected to be provided using `HTTP Basic Authentication`.
	/// That is, a base64-encoded utf-8 string representation of the user's username and
	/// password, separated by a colon ("username:password"), in the `Authorization` header
	/// of the `POST` request. For example:
	///
	///	 let credentials = "username:password".data(using: .utf8).base64encodedString()
	///	 request.addValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
	///
	/// would generate an HTTP header of:
	///
	///	 Authorization: Basic YWRtaW46cGFzc3dvcmQ=
	///
	/// There is no payload in the HTTP body; this header field carries all the necessary
	/// data. The token string returned by successful execution of this login handler
	///
	///	 {
	///		 "token": "y+jiK8w/7Ta21m/O8F2edw=="
	///	 }
	///
	/// is then used for `HTTP Bearer Authentication` in all subsequent requests:
	///
	///	 Authorization: Bearer y+jiK8w/7Ta21m/O8F2edw==
	///
	/// In order to support the simultaneous use of multiple clients and/or devices by a
	/// single user, any existing token will be returned in lieu of generating a new one.
	/// A token will remain valid until the user explicitly logs out (or it otherwise
	/// expires or is administratively revoked), at which point this endpoint will need to
	/// be hit again to generate a new token.
	///
	/// - Note: API v2 query parameter style logins and subsequent key submissions are
	///   **not** supported in API v3.
	///
	/// - Requires: `User.accessLevel` other than `.banned`.
	/// - Requires: HTTP Basic Auth in `Authorization` header.
	/// - Throws: 401 error if the Basic authentication fails. 403 error if the user is
	///   banned. A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `TokenStringData` containing an authentication token (string) that should
	///   be used for all subsequent HTTP requests, until expiry or revocation.
	func loginHandler(_ req: Request) async throws -> TokenStringData {
		// By the time we get here, basic auth has *already happened* via middleware that runs before the route handler.
		let cacheUser = try req.auth.require(UserCacheData.self)
		// no login for punks
		guard cacheUser.accessLevel != .banned else {
			throw Abort(.forbidden, reason: "User is banned, and cannot login.")
		}
		// return existing token if one exists
		if let fastResult = TokenStringData(cacheUser: cacheUser) {
			return fastResult
		}
		// otherwise generate and return new token
		let random = [UInt8].random(count: 16).base64
		let token = Token(token: random, userID: cacheUser.userID)
		try await token.save(on: req.db)
		let ucd = try await req.userCache.updateUser(cacheUser.userID)
		return TokenStringData(accessLevel: ucd.accessLevel, token: token)
	}

	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.

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
	/// There should be no side effect and it is likely harmless, but please do report
	/// a 409 error if you encounter one so that the specifics can be looked into.
	///
	/// - Throws: 401 error if the authentication failed. 409 error if the user somehow
	///   wasn't logged in.
	/// - Returns: 204 No Content if the token was successfully deleted.
	func logoutHandler(_ req: Request) async throws -> HTTPStatus {
		let user = try req.auth.require(UserCacheData.self)
		// Close any open sockets, keep going if we get an error.
		try? await req.webSocketStore.handleUserLogout(user.userID)
		// revoke token
		guard let token = try await Token.query(on: req.db).filter(\.$user.$id == user.userID).first() else {
			throw Abort(.conflict, reason: "user is not logged in")
		}
		try await token.delete(on: req.db)
		try await req.userCache.updateUser(user.userID)
		return .noContent
	}

	// MARK: - Utilities

	/// Logs the user out everywhere: closes their sockets, deletes their login token, clears their web session list,
	/// and refreshes the user cache. Deleting the token also ends every web session, since `UserCacheData.SessionAuth`
	/// only accepts a session whose stored token matches the user's current one.
	static func revokeLogins(forUserID userID: UUID, on req: Request) async throws {
		// Close any open sockets, keep going if we get an error.
		try? await req.webSocketStore.handleUserLogout(userID)
		try await Token.query(on: req.db).filter(\.$user.$id == userID).delete()
		try await req.redis.clearAllSessionMarkers(forUserID: userID)
		try await req.userCache.updateUser(userID)
	}

	/// Revokes the user's existing logins (see `revokeLogins(forUserID:on:)`) and returns a newly generated token.
	/// Use after a password change, so anyone still holding the old login is logged out.
	/// Also saves the user, in the same transaction as the token swap.
	static func rotateToken(for user: User, on req: Request) async throws -> TokenStringData {
		let userID = try user.requireID()
		let token = try Token.generate(for: user)
		try await req.db.transaction { db in
			try await user.save(on: db)
			try await Token.query(on: db).filter(\.$user.$id == userID).delete()
			try await token.save(on: db)
		}
		// The old token is already gone; close any open sockets (keep going on error) and clear the web sessions.
		try? await req.webSocketStore.handleUserLogout(userID)
		try await req.redis.clearAllSessionMarkers(forUserID: userID)
		try await req.userCache.updateUser(userID)
		return try TokenStringData(user: user, token: token)
	}
}
