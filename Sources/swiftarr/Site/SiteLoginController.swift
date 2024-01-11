import Crypto
import FluentSQL
import Vapor

struct SiteLoginController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {

		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app)
		openRoutes.get("login", use: loginPageViewHandler)
		openRoutes.post("login", use: loginPagePostHandler)
		openRoutes.get("createAccount", use: createAccountPageHandler)
		openRoutes.post("createAccount", use: createAccountPostHandler)
		openRoutes.get("resetPassword", use: resetPasswordViewHandler)
		openRoutes.post("resetPassword", use: resetPasswordPostHandler)  // Change pw while logged in
		openRoutes.post("recoverPassword", use: recoverPasswordPostHandler)  // Change pw while not logged in
		openRoutes.get("codeOfConduct", use: codeOfConductViewHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app)
		privateRoutes.get("logout", use: loginPageViewHandler)
		privateRoutes.post("logout", use: loginPageLogoutHandler)

		privateRoutes.get("createAltAccount", use: createAltAccountViewHandler)
		privateRoutes.post("createAltAccount", use: createAltAccountPostHandler)
	}

	// MARK: - Login
	struct LoginPageContext: Encodable {
		var trunk: TrunkContext
		var error: ErrorResponse?
		var operationSuccess: Bool
		var operationName: String
		var sessions: [String]
		var prevRegcode: String?
		var prevUsername: String?
		var prevDisplayName: String?

		init(_ req: Request, error: Error? = nil) async throws {
			trunk = .init(req, title: "Login", tab: .none)
			operationSuccess = false
			operationName = "Login"
			var sessionInfo = [String]()
			if let user = req.auth.get(UserCacheData.self) {
				let sessionData = try await req.redis.getUserSessions(user.userID)
				for (sessionID, deviceInfo) in sessionData {
					if sessionID == req.session.id?.string {
						sessionInfo.append("\(deviceInfo) (this device)")
					}
					else {
						sessionInfo.append(deviceInfo)
					}
				}
			}
			sessions = sessionInfo
			switch error {
				case nil:
					break
				case let abort as Abort:
					self.error = ErrorResponse(error: true, status: abort.status.code, reason: abort.reason, fieldErrors: nil)
				case let errorResponse as ErrorResponse:
					self.error = errorResponse
				case let errorStr as String:
					self.error = ErrorResponse(error: true, status: 500, reason: errorStr, fieldErrors: nil)
				default:
					self.error = ErrorResponse(error: true, status: 500, reason: error?.localizedDescription ?? "Internal Error")
			}
		}
	}

	struct UserCreatedContext: Encodable {
		var trunk: TrunkContext
		var username: String
		var recoveryKey: String
		var redirectURL: String?

		init(_ req: Request, username: String, recoveryKey: String) {
			trunk = .init(req, title: "Account Created", tab: .none)
			self.username = username
			self.recoveryKey = recoveryKey
		}
	}

	/// `GET /login`
	/// `GET /logout`
	///
	/// When the caller is a logged-in user with a session token, this shows a logout page. When the caller is not logged-in, this shows a login page.
	func loginPageViewHandler(_ req: Request) async throws -> View {
		return try await req.view.render("Login/login", LoginPageContext(req))
	}

	/// `POST /login`
	///
	func loginPagePostHandler(_ req: Request) async throws -> View {
		struct PostStruct: Codable {
			var username: String
			var password: String
		}
		do {
			let postStruct = try req.content.decode(PostStruct.self)
			let credentials = "\(postStruct.username):\(postStruct.password)".data(using: .utf8)!.base64EncodedString()
			let headers = HTTPHeaders([("Authorization", "Basic \(credentials)")])
			let response = try await apiQuery(req, endpoint: "/auth/login", method: .POST, defaultHeaders: headers)
			let tokenResponse = try response.content.decode(TokenStringData.self)
			try await loginUser(with: tokenResponse, on: req)
			var loginContext = try await LoginPageContext(req)
			loginContext.trunk.metaRedirectURL = req.session.data["returnAfterLogin"] ?? "/"
			loginContext.operationSuccess = true
			return try await req.view.render("Login/login", loginContext)
		}
		catch {
			var ctx = try await LoginPageContext(req, error: error)
			if let postStruct = try? req.content.decode(PostStruct.self) {
				ctx.prevUsername = postStruct.username
			}
			return try await req.view.render("Login/login", ctx)
		}
	}

	/// `POST /logout`
	///
	/// ** Form Submission Parameters**
	/// * `allaccounts=true` - Logs the user out of all sessions by removing the user's auth token.
	///
	/// There's a single URL for login/logout; it shows you the right page depending on your current login status.
	/// The logout form shows the user who they're logged in as, and has a single 'Logout' button.
	func loginPageLogoutHandler(_ req: Request) async throws -> View {
		struct PostStruct: Codable {
			var allaccounts: String?
		}
		let postStruct = try? req.content.decode(PostStruct.self)
		if postStruct?.allaccounts?.lowercased() == "true" {
			try await apiQuery(req, endpoint: "/auth/logout", method: .POST)
			if let user = req.auth.get(UserCacheData.self) {
				try await req.redis.clearAllSessionMarkers(forUserID: user.userID)
			}
		}
		else if let user = req.auth.get(UserCacheData.self) {
			try await req.redis.clearSessionMarker(req.session.id, forUserID: user.userID)
		}
		req.session.destroy()
		req.auth.logout(UserCacheData.self)
		req.auth.logout(Token.self)
		var loginContext = try await LoginPageContext(req)
		loginContext.trunk.metaRedirectURL = "/login"
		loginContext.operationSuccess = true
		loginContext.operationName = "Logout"
		return try await req.view.render("Login/login", loginContext)
	}

	/// `GET /createAccount`
	///
	/// Shows the Account Creation form if not logged in. For logged-in users this shows the Logout form.
	func createAccountPageHandler(_ req: Request) async throws -> View {
		return try await req.view.render("Login/createAccount", LoginPageContext(req))
	}

	/// `POST /createAccount`
	///
	/// Called when the Create Account form is POSTed.
	func createAccountPostHandler(_ req: Request) async throws -> View {
		struct PostStruct: Codable {
			var regcode: String
			var username: String
			var displayname: String?
			var password: String
			var passwordConfirm: String
		}
		do {
			// Try to capture all the input validation errors into one big error with field markers for each invalid field.
			// This way we can present all the form input errors at once.
			let postStruct = try req.content.decode(PostStruct.self)
			var validationError = ValidationError()
			if postStruct.password != postStruct.passwordConfirm {
				validationError.validationFailures.append(
					ValidationFailure(path: "", field: "password", errorString: "Password fields do not match")
				)
			}
			if let displayName = postStruct.displayname, !displayName.isEmpty {
				if displayName.count < 2 || displayName.count > 50 {
					validationError.validationFailures.append(
						ValidationFailure(
							path: "",
							field: "displayname",
							errorString: "Display Name must be between 2 and 50 characters"
						)
					)
				}
			}
			let createData = UserCreateData(
				username: postStruct.username,
				password: postStruct.password,
				verification: postStruct.regcode
			)
			if let decoderErrors = try ValidatingJSONDecoder()
				.validate(UserCreateData.self, from: JSONEncoder().encode(createData))
			{
				validationError.validationFailures.append(contentsOf: decoderErrors.validationFailures)
			}
			if !validationError.validationFailures.isEmpty {
				throw ErrorResponse(
					error: true,
					status: 403,
					reason: validationError.collectReasonString(),
					fieldErrors: validationError.collectFieldErrors()
				)
			}
			let createResponse = try await apiQuery(
				req,
				endpoint: "/user/create",
				method: .POST,
				encodeContent: createData
			)
			let createUserResponse = try createResponse.content.decode(CreatedUserData.self)
			do {
				// Try to login immediately after account creation, but if login fails, still show the
				// AccountCreated page with the Recovery Key. The user can login manually later.
				let credentials = "\(postStruct.username):\(postStruct.password)".data(using: .utf8)!
					.base64EncodedString()
				let headers = HTTPHeaders([("Authorization", "Basic \(credentials)")])
				let loginResponse = try await apiQuery(
					req,
					endpoint: "/auth/login",
					method: .POST,
					defaultHeaders: headers
				)
				let token = try loginResponse.content.decode(TokenStringData.self)
				try await loginUser(with: token, on: req)
				if let displayname = postStruct.displayname {
					// Set displayname; ignore result. We *could* direct errors here to show an alert in the
					// accountCreated webpage, but don't allow failures at this point to prevent showing the page.
					let profileData = UserProfileUploadData(
						header: nil,
						displayName: displayname,
						realName: nil,
						preferredPronoun: nil,
						homeLocation: nil,
						roomNumber: nil,
						email: nil,
						message: nil,
						about: nil,
						dinnerTeam: nil
					)
					try await apiQuery(req, endpoint: "/user/profile", method: .POST, encodeContent: profileData)
				}
				var userCreatedContext = UserCreatedContext(
					req,
					username: createUserResponse.username,
					recoveryKey: createUserResponse.recoveryKey
				)
				userCreatedContext.redirectURL = req.session.data["returnAfterLogin"]
				return try await req.view.render("Login/accountCreated", userCreatedContext)
			}
			catch {
				// We created the account, but couldn't log them in.
				var userCreatedContext = UserCreatedContext(
					req,
					username: createUserResponse.username,
					recoveryKey: createUserResponse.recoveryKey
				)
				userCreatedContext.redirectURL = req.session.data["returnAfterLogin"]
				return try await req.view.render("Login/accountCreated", userCreatedContext)
			}
		}
		catch {
			// If we get here we couldn't verify that the user created an account. Show the Create Acct page again, with the error.
			var ctx = try await LoginPageContext(req, error: error)
			if let postStruct = try? req.content.decode(PostStruct.self) {
				ctx.prevUsername = postStruct.username
				ctx.prevRegcode = postStruct.regcode
				ctx.prevDisplayName = postStruct.displayname
			}
			return try await req.view.render("Login/createAccount", ctx)
		}
	}

	/// `GET /resetPassword`
	///
	/// Shows the Reset Password page.
	/// Uses password update if you're logged in, else uses the recover password flow.
	func resetPasswordViewHandler(_ req: Request) async throws -> View {
		return try await req.view.render("Login/resetPassword", LoginPageContext(req))
	}

	/// `POST /resetPassword`
	///
	// Change password for logged-in user
	func resetPasswordPostHandler(_ req: Request) async throws -> View {
		struct PostStruct: Codable {
			var currentPassword: String
			var password: String
			var confirmPassword: String
		}
		do {
			let postStruct = try req.content.decode(PostStruct.self)
			guard postStruct.password == postStruct.confirmPassword else {
				throw ErrorResponse(
					error: true,
					status: 500,
					reason: "Password fields do not match",
					fieldErrors: ["password": "Password fields do not match"]
				)
			}
			let userPwData = UserPasswordData(
				currentPassword: postStruct.currentPassword,
				newPassword: postStruct.password
			)
			try await apiQuery(req, endpoint: "/user/password", method: .POST, encodeContent: userPwData)
			var context = try await LoginPageContext(req)
			context.operationName = "Change Password"
			context.operationSuccess = true
			context.trunk.metaRedirectURL = "/"
			return try await req.view.render("Login/resetPassword", context)
		}
		catch {
			return try await req.view.render("Login/resetPassword", LoginPageContext(req, error: error))
		}
	}

	/// `POST /recoverPassword`
	///
	/// Change password for logged-out user, using regcode, current password, or recovery code.
	func recoverPasswordPostHandler(_ req: Request) async throws -> View {
		struct PostStruct: Codable {
			var username: String
			var regCode: String
			var password: String
			var passwordConfirm: String
		}
		do {
			let postStruct = try req.content.decode(PostStruct.self)
			guard postStruct.password == postStruct.passwordConfirm else {
				throw ErrorResponse(
					error: true,
					status: 500,
					reason: "Password fields do not match",
					fieldErrors: ["password": "Password fields do not match"]
				)
			}
			let recoveryData = UserRecoveryData(
				username: postStruct.username,
				recoveryKey: postStruct.regCode,
				newPassword: postStruct.password
			)
			let apiResponse = try await apiQuery(
				req,
				endpoint: "/auth/recovery",
				method: .POST,
				encodeContent: recoveryData
			)
			let tokenResponse = try apiResponse.content.decode(TokenStringData.self)
			try await loginUser(with: tokenResponse, on: req)
			var loginContext = try await LoginPageContext(req)
			loginContext.trunk.metaRedirectURL = req.session.data["returnAfterLogin"] ?? "/"
			loginContext.operationSuccess = true
			loginContext.operationName = "Password Change"
			return try await req.view.render("Login/login", loginContext)
		}
		catch {
			var ctx = try await LoginPageContext(req, error: error)
			if let postStruct = try? req.content.decode(PostStruct.self) {
				ctx.prevUsername = postStruct.username
				ctx.prevRegcode = postStruct.regCode
			}
			return try await req.view.render("Login/resetPassword", ctx)
		}
	}

	/// `GET /codeOfConduct`
	///
	func codeOfConductViewHandler(_ req: Request) async throws -> View {
		var urlComponents = Settings.shared.apiUrlComponents
		urlComponents.path = "/public/codeofconduct.json"
		guard let apiURLString = urlComponents.string else {
			throw Abort(.internalServerError, reason: "Unable to build URL to API endpoint.")
		}
		let response = try await req.client.send(.GET, to: URI(string: apiURLString))
		let document = try response.content.decode(ConductDoc.self)

		struct ConductDocParagraph: Codable {
			var text: String?
			var list: [String]?
		}

		struct ConductDocSection: Codable {
			var header: String?
			var paragraphs: [ConductDocParagraph]?
		}

		struct ConductDocDocument: Codable {
			var header: String?
			var sections: [ConductDocSection]?
		}

		struct ConductDoc: Codable {
			var codeofconduct: ConductDocDocument
			var guidelines: ConductDocDocument
			var twitarrconduct: ConductDocDocument
		}

		struct ConductContext: Encodable {
			var trunk: TrunkContext
			var conductDocuments: [ConductDocDocument]

			init(_ req: Request, conductDocument: ConductDoc) throws {
				trunk = .init(req, title: "Code of Conduct", tab: .none)
				self.conductDocuments = [conductDocument.guidelines, conductDocument.codeofconduct, conductDocument.twitarrconduct]
			}
		}

		let ctx = try ConductContext(req, conductDocument: document)
		return try await req.view.render("codeOfConduct", ctx)
	}

	/// `GET /createAltAccount`
	///
	/// Must be logged in, although you can be logged in as an alt account, in which case this method creates another alt as a child
	/// of the parent account. All accounts are parents or children, never both.
	func createAltAccountViewHandler(_ req: Request) async throws -> View {
		return try await req.view.render("Login/createAltAccount", LoginPageContext(req))
	}

	/// `POST /createAltAccount`
	///
	func createAltAccountPostHandler(_ req: Request) async throws -> View {
		struct PostStruct: Codable {
			var username: String
			var password: String
			var passwordConfirm: String
		}
		do {
			let postStruct = try req.content.decode(PostStruct.self)
			guard postStruct.password == postStruct.passwordConfirm else {
				throw ErrorResponse(
					error: true,
					status: 500,
					reason: "Password fields do not match",
					fieldErrors: ["password": "Password fields do not match"]
				)
			}
			let createData = UserCreateData(
				username: postStruct.username,
				password: postStruct.password,
				verification: ""
			)
			try await apiQuery(req, endpoint: "/user/add", method: .POST, encodeContent: createData)
			//		let createUserResponse = try apiResponse.content.decode(AddedUserData.self)
			var loginContext = try await LoginPageContext(req)
			loginContext.trunk.metaRedirectURL = "/"
			loginContext.operationSuccess = true
			loginContext.operationName = "Alt account creation"
			return try await req.view.render("Login/createAltAccount", loginContext)
		}
		catch {
			var ctx = try await LoginPageContext(req, error: error)
			if let postStruct = try? req.content.decode(PostStruct.self) {
				ctx.prevUsername = postStruct.username
			}
			return try await req.view.render("Login/createAltAccount", ctx)
		}
	}

	// MARK: - Utilities

	// Currently we do a direct DB lookup on login so that we can call auth.login() on the User that logged in.
	// This breaks the idea of the web client only relying on the API. I believe a better solution will be to
	// make a new Authenticatable type (WebUser?) that isn't database-backed and is stored in the Session, and
	// then the web client can Auth on that type instead of User. But, I want to be sure we *really* don't need
	// User before embarking on this.
	func loginUser(with tokenResponse: TokenStringData, on req: Request, defaultDeviceType: String = "unknown device")
		async throws
	{
		guard let user = req.userCache.getUser(tokenResponse.userID) else {
			throw Abort(.unauthorized, reason: "User not found")
		}
		// auth.login just logs the user in for the duration of this request.
		req.auth.login(user)
		req.session.data["token"] = tokenResponse.token
		req.session.data["accessLevel"] = tokenResponse.accessLevel.rawValue
		req.session.data["userID"] = String(tokenResponse.userID)

		var deviceType = defaultDeviceType
		if let userAgent = req.headers.first(name: "User-Agent") {
			if let openParen = userAgent.firstIndex(of: "("), let semicolon = userAgent.firstIndex(of: ";"),
				semicolon > openParen
			{
				let afterParen = userAgent.index(after: openParen)
				deviceType = String(userAgent[afterParen..<semicolon])
			}
		}
		try await req.redis.storeSessionMarker(req.session.id, marker: deviceType, forUserID: user.userID)
	}
}
