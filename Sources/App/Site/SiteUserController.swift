import Vapor
import Crypto
import FluentSQL

struct SiteUserController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app)
        globalRoutes.get("user", userIDParam, use: userProfilePageHandler)
        globalRoutes.get("username", ":username", use: usernameProfilePageHandler)
        globalRoutes.get("profile", ":username", use: usernameProfilePageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app)
        privateRoutes.get("profile", use: selfProfilePageHandler)
        privateRoutes.get("profile", "edit", use: userProfileEditPageHandler)
        privateRoutes.post("profile", "edit", use: userProfileEditPostHandler)
	}
	
	struct UserProfileContext : Encodable {
		var trunk: TrunkContext
		var profile: ProfilePublicData
		
		init(_ req: Request, profile: ProfilePublicData) throws {
			trunk = .init(req, title: "User Profile", tab: .none)
			self.profile = profile
		}
	}
	
	// GET /profile
	//
	// Shows a user their own profile page.
	func selfProfilePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		let user = try req.auth.require(User.self)
    	return try apiQuery(req, endpoint: "/users/\(user.requireID())/profile").throwingFlatMap { response in
			let profile = try response.content.decode(ProfilePublicData.self)
			let ctx = try UserProfileContext(req, profile: profile)
			return req.view.render("user/userProfile", ctx)			
    	}
	}


	// GET /user/ID
	//
	// Shows a user profile page; the user is specified by their ID
	func userProfilePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let userID = req.parameters.get(userIDParam.paramString) else {
    		throw "Invalid user ID"
    	}
    	return apiQuery(req, endpoint: "/users/\(userID)/profile").throwingFlatMap { response in
			let profile = try response.content.decode(ProfilePublicData.self)
			let ctx = try UserProfileContext(req, profile: profile)
			return req.view.render("user/userProfile", ctx)			
    	}
	}

	// GET /user/STRING
	//
	// Shows a user profile page; the user is specified by username. Since usernames can be changed, 
	// `/user/ID` is preferable if you have the userID.
	func usernameProfilePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let username = req.parameters.get("username") else {
    		throw "Invalid username parameter"
    	}
    	return apiQuery(req, endpoint: "/users/find/\(username)").throwingFlatMap { headerResponse in
			let userHeader = try headerResponse.content.decode(UserHeader.self)
			return apiQuery(req, endpoint: "/users/\(userHeader.userID)/profile").throwingFlatMap { response in
				let profile = try response.content.decode(ProfilePublicData.self)
				let ctx = try UserProfileContext(req, profile: profile)
				return req.view.render("user/userProfile", ctx)			
			}
		}
	}
	
	// GET /profile/edit
	// GET /profile/edit/ID
	func userProfileEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		let user = try req.auth.require(User.self)
		var profileUsername = user.username
		if let username = req.parameters.get("username"), username != profileUsername {
			profileUsername = username
			guard user.accessLevel.hasAccess(.moderator) else {
				throw Abort(.forbidden, reason: "User isn't authorized to edit other users' profiles.")
			}
    	}
    	return apiQuery(req, endpoint: "/user/profile").throwingFlatMap { response in
			let profile = try response.content.decode(UserProfileData.self)
			struct UserProfileEditContext : Encodable {
				var trunk: TrunkContext
				var profile: UserProfileData
				var formAction: String
				var postSuccessURL: String
				
				init(_ req: Request, profile: UserProfileData) throws {
					trunk = .init(req, title: "Edit Profile", tab: .none)
					self.profile = profile
					formAction = "/profile/edit"
					postSuccessURL = "/profile"
				}
			}
			let ctx = try UserProfileEditContext(req, profile: profile)
			return req.view.render("user/userProfileEdit", ctx)			
		}
	}
	
	struct ProfileFormContent: Content {
		var avatarPhotoInput: Data?
		var serverAvatarPhoto: String
		var displayName: String
		var realName: String
		var email: String
		var homeLocation: String
		var message: String
		var preferredPronoun: String
		var roomNumber: String
	}
	
	// POST /profile/edit
	// POST /profile/edit/ID
	func userProfileEditPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let user = try req.auth.require(User.self)
		var profileUsername = user.username
		if let username = req.parameters.get("username"), username != profileUsername {
			profileUsername = username
			guard user.accessLevel.hasAccess(.moderator) else {
				throw Abort(.forbidden, reason: "User isn't authorized to edit other users' profiles.")
			}
    	}
		let profileStruct = try req.content.decode(ProfileFormContent.self)
		let postContent = UserProfileData(header: nil, displayName: profileStruct.displayName, about: profileStruct.message, 
				email: profileStruct.email, homeLocation: profileStruct.homeLocation, message: profileStruct.message, 
				preferredPronoun: profileStruct.preferredPronoun, realName: profileStruct.realName, 
				roomNumber: profileStruct.roomNumber)
    	return apiQuery(req, endpoint: "/user/profile", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent) 
		}).throwingFlatMap { response in
			if let imageUploadData = ImageUploadData(nil, profileStruct.avatarPhotoInput) {
				return apiQuery(req, endpoint: "/user/image", method: .POST, beforeSend: { req throws in 
					try req.content.encode(imageUploadData)
				}).transform(to: .ok)
			}
			else if profileStruct.serverAvatarPhoto.hasPrefix("/api/v3/image/user/identicon") {
				return apiQuery(req, endpoint: "/user/image", method: .DELETE).transform(to: .ok)
			}
			else {
				return req.eventLoop.future(.ok)
			}
		}
	}

}
