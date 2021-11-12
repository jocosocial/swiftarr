import Vapor
import Crypto
import FluentSQL

struct SiteLoginController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {

		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app)
        openRoutes.get("login", use: loginPageViewHandler)
        openRoutes.post("login", use: loginPagePostHandler)
        openRoutes.get("createAccount", use: createAccountPageHandler)
        openRoutes.post("createAccount", use: createAccountPostHandler)
        openRoutes.get("resetPassword", use: resetPasswordViewHandler)
        openRoutes.post("resetPassword", use: resetPasswordPostHandler)			// Change pw while logged in
        openRoutes.post("recoverPassword", use: recoverPasswordPostHandler)		// Change pw while not logged in
        openRoutes.get("codeOfConduct", use: codeOfConductViewHandler)
				
		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app)
        privateRoutes.get("logout", use: loginPageViewHandler)
        privateRoutes.post("logout", use: loginPageLogoutHandler)

        privateRoutes.get("createAltAccount", use: createAltAccountViewHandler)
        privateRoutes.post("createAltAccount", use: createAltAccountPostHandler)
	}
	    
// MARK: - Login
	struct LoginPageContext : Encodable {
		var trunk: TrunkContext
		var error: ErrorResponse?
		var operationSuccess: Bool
		var operationName: String
		
		init(_ req: Request, error: Error? = nil) {
			trunk = .init(req, title: "Login", tab: .none)
			operationSuccess = false
			operationName = "Login"
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
	
	struct UserCreatedContext : Encodable {
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
    func loginPageViewHandler(_ req: Request) -> EventLoopFuture<View> {
		return req.view.render("Login/login", LoginPageContext(req))
	}
	    
	/// `POST /login`
	///
    func loginPagePostHandler(_ req: Request) -> EventLoopFuture<View> {
    	struct PostStruct : Codable {
    		var username: String
    		var password: String
    	}
    	do {
			let postStruct = try req.content.decode(PostStruct.self)
			let credentials = "\(postStruct.username):\(postStruct.password)".data(using: .utf8)!.base64EncodedString()
			let headers = HTTPHeaders([("Authorization", "Basic \(credentials)")])
			return apiQuery(req, endpoint: "/auth/login", method: .POST, defaultHeaders: headers)
					.throwingFlatMap { apiResponse in
				let tokenResponse = try apiResponse.content.decode(TokenStringData.self)
				return try loginUser(with: tokenResponse, on: req).flatMap {
					var loginContext = LoginPageContext(req)
					loginContext.trunk.metaRedirectURL = req.session.data["returnAfterLogin"] ?? "/tweets"
					loginContext.operationSuccess = true
					return req.view.render("Login/login", loginContext)
				}.flatMapError { error in 
					return req.view.render("Login/login", LoginPageContext(req, error: error))
				}
			}.flatMapError { error in
				return req.view.render("Login/login", LoginPageContext(req, error: error)) 
			}
		}
		catch {
			return req.view.render("Login/login", LoginPageContext(req, error: error))
		}
	}
	    
	/// `POST /logout`
	///
	/// There's a single URL for login/logout; it shows you the right page depending on your current login status.
	/// The logout form shows the user who they're logged in as, and has a single 'Logout' button.
    func loginPageLogoutHandler(_ req: Request) -> EventLoopFuture<View> {
    	return apiQuery(req, endpoint: "/auth/logout", method: .POST).flatMap { response in
			req.session.destroy()
			req.auth.logout(UserCacheData.self)
			req.auth.logout(Token.self)
			var loginContext = LoginPageContext(req)
			loginContext.trunk.metaRedirectURL = "/login"
			loginContext.operationSuccess = true
			loginContext.operationName = "Logout"
			return req.view.render("Login/login", loginContext)
		}
    }
    
	/// `GET /createAccount`
	///
	/// Shows the Account Creation form if not logged in. For logged-in users this shows the Logout form.
	func createAccountPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return req.view.render("Login/createAccount", LoginPageContext(req))
    }
    
	/// `POST /createAccount`
	///
    /// Called when the Create Account form is POSTed.
	func createAccountPostHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	struct PostStruct : Codable {
    		var regcode: String?
    		var username: String
    		var displayname: String?
    		var password: String
    		var passwordConfirm: String
    	}
    	do {
			let postStruct = try req.content.decode(PostStruct.self)
			guard postStruct.password == postStruct.passwordConfirm else {
				return req.view.render("Login/createAccount", LoginPageContext(req, error: "Password fields do not match"))
			}
			return apiQuery(req, endpoint: "/user/create", method: .POST, beforeSend: { req throws in
				let createData = UserCreateData(username: postStruct.username, password: postStruct.password, 
						verification: postStruct.regcode)
				try req.content.encode(createData)
			}).throwingFlatMap { apiResponse in
				let createUserResponse = try apiResponse.content.decode(CreatedUserData.self)
				
				// Try to login immediately after account creation, but if login fails, still show the 
				// AccountCreated page with the Recovery Key. The user can login manually later.
				let credentials = "\(postStruct.username):\(postStruct.password)".data(using: .utf8)!.base64EncodedString()
				let headers = HTTPHeaders([("Authorization", "Basic \(credentials)")])
				return apiQuery(req, endpoint: "/auth/login", method: .POST, defaultHeaders: headers)
						.throwingFlatMap { apiResponse in
					let tokenResponse = try apiResponse.content.decode(TokenStringData.self)
					return try loginUser(with: tokenResponse, on: req).flatMap {
						if let displayname = postStruct.displayname {
							// Set displayname; ignore result. We *could* direct errors here to show an alert in the 
							// accountCreated webpage, but don't allow failures at this point to prevent showing the page.
							_ = apiQuery(req, endpoint: "/user/profile", method: .POST, beforeSend: { req throws in
								let profileData = UserProfileUploadData(header: nil, displayName: displayname, realName: nil,
										preferredPronoun: nil, homeLocation: nil, roomNumber: nil, 
										email: nil, message: nil, about: nil)
								try req.content.encode(profileData)
							})
						}
						var userCreatedContext = UserCreatedContext(req, username: createUserResponse.username, 
								recoveryKey: createUserResponse.recoveryKey)
						userCreatedContext.redirectURL = req.session.data["returnAfterLogin"]
						return req.view.render("Login/accountCreated", userCreatedContext)
					}.flatMapError { error in 
						var userCreatedContext = UserCreatedContext(req, username: createUserResponse.username, 
								recoveryKey: createUserResponse.recoveryKey)
						userCreatedContext.redirectURL = req.session.data["returnAfterLogin"]
						return req.view.render("Login/accountCreated", userCreatedContext)
					}
				}.flatMapError { error in
					// We created the account, but couldn't log them in.
					var userCreatedContext = UserCreatedContext(req, username: createUserResponse.username, 
							recoveryKey: createUserResponse.recoveryKey)
					userCreatedContext.redirectURL = req.session.data["returnAfterLogin"]
					return req.view.render("Login/accountCreated", userCreatedContext)
				}
			}.flatMapError { error in
				return req.view.render("Login/createAccount", LoginPageContext(req, error: error))
			}
		}
		catch {
			return req.view.render("Login/createAccount", LoginPageContext(req, error: error))
		}
	}
	
	/// `GET /resetPassword`
	///
	/// Shows the Reset Password page.
	/// Uses password update if you're logged in, else uses the recover password flow.
    func resetPasswordViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return req.view.render("Login/resetPassword", LoginPageContext(req))
    }

	/// `POST /resetPassword`
	///
	// Change password for logged-in user
    func resetPasswordPostHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	struct PostStruct : Codable {
    		var currentPassword: String
    		var password: String
    		var confirmPassword: String
    	}
    	do {
			let postStruct = try req.content.decode(PostStruct.self)
			guard postStruct.password == postStruct.confirmPassword else {
				return req.view.render("Login/resetPassword", LoginPageContext(req, error: "Password fields do not match"))
			}
			return apiQuery(req, endpoint: "/user/password", method: .POST, beforeSend: { req throws in
				let userPwData = UserPasswordData(currentPassword: postStruct.currentPassword, newPassword: postStruct.password)
				try req.content.encode(userPwData)
			}).throwingFlatMap { apiResponse in
				var context = LoginPageContext(req)
				context.operationName = "Change Password"
				context.operationSuccess = true
				context.trunk.metaRedirectURL = "/"
				return req.view.render("Login/resetPassword", context)
			}.flatMapError { error in 
				return req.view.render("Login/resetPassword", LoginPageContext(req, error: error))
			}
		}
		catch {
			return req.view.render("Login/resetPassword", LoginPageContext(req, error: error))
		}
    }
    
	/// `POST /recoverPassword`
	///
	func recoverPasswordPostHandler(_ req: Request) -> EventLoopFuture<View> {
		struct PostStruct : Codable {
			var username: String
			var regCode: String
			var password: String
			var confirmPassword: String
		}
    	do {
			let postStruct = try req.content.decode(PostStruct.self)
			guard postStruct.password == postStruct.confirmPassword else {
				return req.view.render("Login/resetPassword", LoginPageContext(req, error: "Password fields do not match"))
			}
			return apiQuery(req, endpoint: "/auth/recovery", method: .POST, beforeSend: { req throws in
				let recoveryData = UserRecoveryData(username: postStruct.username, recoveryKey: postStruct.regCode, 
						newPassword: postStruct.password)
				try req.content.encode(recoveryData)
			}).throwingFlatMap { apiResponse in
				let tokenResponse = try apiResponse.content.decode(TokenStringData.self)
				return try loginUser(with: tokenResponse, on: req).flatMap {
					var loginContext = LoginPageContext(req)
					loginContext.trunk.metaRedirectURL = req.session.data["returnAfterLogin"] ?? "/tweets"
					loginContext.operationSuccess = true
					loginContext.operationName = "Password Change"
					return req.view.render("Login/login", loginContext)
				}.flatMapError { error in 
					return req.view.render("Login/resetPassword", LoginPageContext(req, error: error))
				}				
			}.flatMapError { error in
				return req.view.render("Login/resetPassword", LoginPageContext(req, error: error))
			}
		}
		catch {
			return req.view.render("Login/resetPassword", LoginPageContext(req, error: error))
		}
    }
    
	/// `GET /codeOfConduct`
	///
    func codeOfConductViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return req.view.render("codeOfConduct", LoginPageContext(req))
    }
    
	/// `GET /createAltAccount`
	///
	/// Must be logged in, although you can be logged in as an alt account, in which case this method creates another alt as a child
	/// of the parent account. All accounts are parents or children, never both.
    func createAltAccountViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	let _ = try req.auth.require(UserCacheData.self)
		return req.view.render("Login/createAltAccount", LoginPageContext(req))
    }

	/// `POST /createAltAccount`
	///
	func createAltAccountPostHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct PostStruct : Codable {
    		var username: String
    		var password: String
    		var confirmPassword: String
    	}
		let postStruct = try req.content.decode(PostStruct.self)
		guard postStruct.password == postStruct.confirmPassword else {
			return req.view.render("Login/createAltAccount", LoginPageContext(req, error: "Password fields do not match"))
		}
		return apiQuery(req, endpoint: "/user/add", method: .POST, beforeSend: { req throws in
			let createData = UserCreateData(username: postStruct.username, password: postStruct.password)
			try req.content.encode(createData)
		}).throwingFlatMap { apiResponse in
//			let createUserResponse = try apiResponse.content.decode(AddedUserData.self)
			var loginContext = LoginPageContext(req)
			loginContext.trunk.metaRedirectURL = "/"
			loginContext.operationSuccess = true
			loginContext.operationName = "Alt account creation"
			return req.view.render("Login/createAltAccount", loginContext)
		}
	}
	

// MARK: - Utilities

	// Currently we do a direct DB lookup on login so that we can call auth.login() on the User that logged in.
	// This breaks the idea of the web client only relying on the API. I believe a better solution will be to
	// make a new Authenticatable type (WebUser?) that isn't database-backed and is stored in the Session, and
	// then the web client can Auth on that type instead of User. But, I want to be sure we *really* don't need 
	// User before embarking on this.
	func loginUser(with tokenResponse: TokenStringData, on req: Request) throws -> EventLoopFuture<Void> {
		guard let user = req.userCache.getUser(tokenResponse.userID) else {
			throw Abort(.unauthorized, reason: "User not found")
		}
		req.auth.login(user)
		req.session.data["token"] = tokenResponse.token
		req.session.data["accessLevel"] = tokenResponse.accessLevel.rawValue			
		return req.eventLoop.future()
	}
}
