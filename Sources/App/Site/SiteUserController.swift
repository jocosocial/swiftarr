import Vapor
import Crypto
import FluentSQL

struct PublicProfileContext : Encodable {
	var trunk: TrunkContext
	var profile: ProfilePublicData
	var noteFormAction: String
	
	init(_ req: Request, profile: ProfilePublicData) throws {
		trunk = .init(req, title: "User Profile", tab: .none)
		self.profile = profile
		noteFormAction = "/profile/note/\(profile.header.userID)"
	}
}
	
struct ProfileFormContent: Content {
	var avatarPhotoInput: Data?
	var serverAvatarPhoto: String
	var displayName: String
	var realName: String
	var preferredPronoun: String
	var homeLocation: String
	var roomNumber: String
	var email: String
	var message: String
	var about: String
}
	
struct SiteUserController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		
		// Routes that the user does not need to be logged in to access.
		let flexRoutes = getOpenRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .images))
        flexRoutes.get("avatar", "full", userIDParam, use: userAvatarHandler)
        flexRoutes.get("avatar", "thumb", userIDParam, use: userAvatarHandler)
	
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .users))
        globalRoutes.get("user", userIDParam, use: userProfilePageHandler)
        globalRoutes.get("username", ":username", use: usernameProfilePageHandler)
        globalRoutes.get("profile", ":username", use: usernameProfilePageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .users))
        privateRoutes.get("profile", use: selfProfilePageHandler)
        privateRoutes.get("profile", "edit", use: selfProfileEditPageHandler)
        privateRoutes.get("profile", "edit", userIDParam, use: userProfileEditPageHandler)
        privateRoutes.post("profile", "edit", use: userProfileEditPostHandler)
        privateRoutes.post("profile", "edit", userIDParam, use: userProfileEditPostHandler)
        privateRoutes.post("profile", "note", userIDParam, use: userNotePostHandler)
        privateRoutes.get("profile", "report", userIDParam, use: profileReportPageHandler)
        privateRoutes.post("profile", "report", userIDParam, use: profileReportPostHandler)
	}
	
	/// GET /avatar/full/ID
	/// GET /avatar/thumb/ID
	///
	/// Gets a user's avatar image. Calls through to `/api/v3/image/user/SIZE/ID`, and, if called with session credentials, will
	/// pass through the creds (which mostly affects quarantined users and moderators). 
	func userAvatarHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid userID parameter"
    	}
    	let sizeType = req.url.path.hasPrefix("/avatar/full") ? "full" : "thumb"
    	// The important headers are Accept, Accept-Encoding, and If-None-Match 
    	var headers = HTTPHeaders()
    	headers.add(contentsOf: req.headers)
    	return apiQuery(req, endpoint: "/image/user/\(sizeType)/\(userID)", defaultHeaders: headers).map { apiResponse in
    		var body = Response.Body.empty
    		if let apiResponseBody = apiResponse.body {
    			body = Response.Body(buffer: apiResponseBody)
			}
			let response = Response(status: apiResponse.status, headers: apiResponse.headers, body: body)
			return response
    	}.flatMapErrorThrowing { error in
    		switch error {
    			case let abortErr as Abort where abortErr.status == .notModified:
     				return Response(status: .notModified)
   				case let errorResponse as ErrorResponse where errorResponse.status == 304:
    				return Response(status: .notModified)
				default:
					throw error
    		}
    		
    	}
	}
	
	// GET /profile
	//
	// Shows a user their own profile page.
	func selfProfilePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	return apiQuery(req, endpoint: "/user/profile").throwingFlatMap { response in
			let profile = try response.content.decode(ProfilePublicData.self)
			struct UserProfileContext : Encodable {
				var trunk: TrunkContext
				var profile: ProfilePublicData
				
				init(_ req: Request, profile: ProfilePublicData) throws {
					trunk = .init(req, title: "User Profile", tab: .none)
					self.profile = profile
				}
			}
			let ctx = try UserProfileContext(req, profile: profile)
			return req.view.render("User/userProfile", ctx)			
    	}
	}

	// GET /user/ID
	//
	// Shows a user profile page; the user is specified by their ID
	func userProfilePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid user ID"
    	}
    	return apiQuery(req, endpoint: "/users/\(userID)/profile").throwingFlatMap { response in
			let profile = try response.content.decode(ProfilePublicData.self)
			let ctx = try PublicProfileContext(req, profile: profile)
			return req.view.render("User/userProfile", ctx)			
    	}
	}

	// GET /user/STRING
	//
	// Shows a user profile page; the user is specified by username. Since usernames can be changed, 
	// `/user/ID` is preferable if you have the userID.
	func usernameProfilePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let username = req.parameters.get("username")?.percentEncodeFilePathEntry() else {
    		throw "Invalid username parameter"
    	}
    	return apiQuery(req, endpoint: "/users/find/\(username)").throwingFlatMap { headerResponse in
			let userHeader = try headerResponse.content.decode(UserHeader.self)
			return apiQuery(req, endpoint: "/users/\(userHeader.userID)/profile").throwingFlatMap { response in
				let profile = try response.content.decode(ProfilePublicData.self)
				let ctx = try PublicProfileContext(req, profile: profile)
				return req.view.render("User/userProfile", ctx)			
			}
		}
	}
	
	// GET /profile/edit
	//
	// Shows a user a page that lets them edit their own profile.
	func selfProfileEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	return apiQuery(req, endpoint: "/user/profile").throwingFlatMap { response in
			let profile = try response.content.decode(ProfilePublicData.self)
			struct UserProfileEditContext : Encodable {
				var trunk: TrunkContext
				var profile: ProfilePublicData
				var formAction: String
				var postSuccessURL: String
				
				init(_ req: Request, profile: ProfilePublicData) throws {
					trunk = .init(req, title: "Edit Profile", tab: .none)
					self.profile = profile
					formAction = "/profile/edit"
					postSuccessURL = "/profile"
				}
			}
			let ctx = try UserProfileEditContext(req, profile: profile)
			return req.view.render("User/userProfileEdit", ctx)			
		}
	}
	
	// GET /profile/edit/ID
	//
	// Shows mods a page that lets them edit others profiles. Note: Non-mods cannot use this endpoint
	// to edit their own profile, even if they pass in their own userID.
	func userProfileEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		let user = try req.auth.require(User.self)
		guard let targetUserID = req.parameters.get(userIDParam.paramString, as: UUID.self),
				user.accessLevel.hasAccess(.moderator) else {
			// Actually trying to post changes to someone else's profile will fail at the API level, but we want
			// to catch it before showing the page.
			throw Abort(.forbidden, reason: "User isn't authorized to edit other users' profiles.")
    	}
    	return apiQuery(req, endpoint: "/users/\(targetUserID)/profile").throwingFlatMap { response in
			let profile = try response.content.decode(ProfilePublicData.self)
			struct PublicProfileEditContext : Encodable {
				var trunk: TrunkContext
				var profile: ProfilePublicData
				var formAction: String
				var postSuccessURL: String
				
				init(_ req: Request, profile: ProfilePublicData, targetUserID: UUID) throws {
					trunk = .init(req, title: "Edit @\(profile.header.username)'s Profile", tab: .none)
					self.profile = profile
					formAction = "/profile/edit/\(targetUserID)"
					postSuccessURL = "/user/\(targetUserID)"
				}
			}
			let ctx = try PublicProfileEditContext(req, profile: profile, targetUserID: targetUserID)
			return req.view.render("User/userProfileEdit", ctx)			
		}
	}
	
	// POST /profile/edit
	// POST /profile/edit/ID
	//
	// Posts an edit to the user's own profile, or lets mods post edits to other user's profiles.
	func userProfileEditPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		var path = "/user/profile"
		var targetUserID: UUID?
		if let targetUserIDVal = req.parameters.get(userIDParam.paramString, as: UUID.self) {
			path = "/user/\(targetUserIDVal)/profile"
			targetUserID = targetUserIDVal
    	}
		let profileStruct = try req.content.decode(ProfileFormContent.self)
		let postContent = UserProfileUploadData(header: nil, displayName: profileStruct.displayName, realName: profileStruct.realName, 
				preferredPronoun: profileStruct.preferredPronoun, homeLocation: profileStruct.homeLocation, 
				roomNumber: profileStruct.roomNumber, email: profileStruct.email,
				message: profileStruct.message, about: profileStruct.about)
    	return apiQuery(req, endpoint: path, method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent) 
		}).throwingFlatMap { response in
			if let targetUserIDVal = targetUserID {
				// We can only delete the avatar of another user, and only mods can do it.
				if profileStruct.serverAvatarPhoto.hasPrefix("/api/v3/image/user/identicon") {
					return apiQuery(req, endpoint: "/user/\(targetUserIDVal)/image", method: .DELETE).transform(to: .ok)
				}
				else {
					return req.eventLoop.future(.ok)
				}
			}
			else if let imageUploadData = ImageUploadData(nil, profileStruct.avatarPhotoInput) {
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
	
	// POST /profile/note/ID
	//
	func userNotePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let targetUserID = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
    		throw "Invalid userID parameter"
    	}
		struct ProfileNoteFormContent: Content {
			var noteText: String
		}
		let noteStruct = try req.content.decode(ProfileNoteFormContent.self)
		let postContent = NoteCreateData(note: noteStruct.noteText)
    	return apiQuery(req, endpoint: "/users/\(targetUserID)/note", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent) 
		}).map { response in
			return .ok
		}
	}
	
	/// `GET /profile/report/ID`
	///
	/// Reports content in a user's profile, either the profile text fields or the avatar image. NOTE: This isn't reporting the **user**, you can't report
	/// users directly, just content they create. 
    func profileReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let targetUserID = req.parameters.get(userIDParam.paramString) else {
    		throw "Invalid userID parameter"
    	}
		let ctx = try ReportPageContext(req, userID: targetUserID)
    	return req.view.render("reportCreate", ctx)
    }
    
	/// `POST /profile/report/ID`
	///
	func profileReportPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let targetUserID = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
    		throw "Invalid userID parameter"
    	}
    	// The only field in ReportData is the message; we can use it as both the form data from the reportCreate webpage
    	// and the DTO for the API layer.
		let postStruct = try req.content.decode(ReportData.self)
 		return apiQuery(req, endpoint: "/users/\(targetUserID)/report", method: .POST, beforeSend: { req throws in
			try req.content.encode(postStruct)
		}).flatMapThrowing { response in
			return .created
		}
    }
}
