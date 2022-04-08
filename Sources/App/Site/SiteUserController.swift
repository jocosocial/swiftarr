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

struct AddWordFormStruct: Decodable {
	var newKeyword: String?
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
		privateRoutes.post("user", userIDParam, "block", use: blockUserPostHandler)
		privateRoutes.post("user", userIDParam, "unblock", use: unblockUserPostHandler)
		privateRoutes.post("user", userIDParam, "mute", use: muteUserPostHandler)
		privateRoutes.post("user", userIDParam, "unmute", use: unmuteUserPostHandler)
		privateRoutes.get("blocks", use: blocksPageHandler)
		privateRoutes.get("alertwords", use: alertMuteWordsPageHandler)
		privateRoutes.get("mutewords", use: alertMuteWordsPageHandler)
		privateRoutes.post("alertword", "add", use: addAlertwordPostHandler)
		privateRoutes.post("alertword", alertWordParam, "remove", use: removeAlertwordPostHandler)
		privateRoutes.post("muteword", "add", use: addMutewordPostHandler)
		privateRoutes.post("muteword", muteWordParam, "remove", use: removeMutewordPostHandler)
	}
	
	/// GET /avatar/full/ID
	/// GET /avatar/thumb/ID
	///
	/// Gets a user's avatar image. Calls through to `/api/v3/image/user/SIZE/ID`, and, if called with session credentials, will
	/// pass through the creds (which mostly affects quarantined users and moderators). 
	func userAvatarHandler(_ req: Request) async throws -> Response {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid userID parameter"
		}
		do {
			let sizeType = req.url.path.hasPrefix("/avatar/full") ? "full" : "thumb"
			// The important headers are Accept, Accept-Encoding, and If-None-Match 
			var headers = HTTPHeaders()
			headers.add(contentsOf: req.headers)
			let response = try await apiQuery(req, endpoint: "/image/user/\(sizeType)/\(userID)", defaultHeaders: headers)
			var body = Response.Body.empty
			if let apiResponseBody = response.body {
				body = Response.Body(buffer: apiResponseBody)
			}
			return Response(status: response.status, headers: response.headers, body: body)
		}
		catch {
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
	func selfProfilePageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/user/profile")
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
		return try await req.view.render("User/userProfile", ctx)			
	}

	// GET /user/ID
	//
	// Shows a user profile page; the user is specified by their ID
	func userProfilePageHandler(_ req: Request) async throws -> View {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid user ID"
		}
		let response = try await apiQuery(req, endpoint: "/users/\(userID)/profile")
		let profile = try response.content.decode(ProfilePublicData.self)
		let ctx = try PublicProfileContext(req, profile: profile)
		return try await req.view.render("User/userProfile", ctx)			
	}

	// GET /user/STRING
	//
	// Shows a user profile page; the user is specified by username. Since usernames can be changed, 
	// `/user/ID` is preferable if you have the userID.
	func usernameProfilePageHandler(_ req: Request) async throws -> View {
		guard let username = req.parameters.get("username")?.percentEncodeFilePathEntry() else {
			throw "Invalid username parameter"
		}
		let userHeaderResponse = try await apiQuery(req, endpoint: "/users/find/\(username)")
		let userHeader = try userHeaderResponse.content.decode(UserHeader.self)
		let profileResponse = try await apiQuery(req, endpoint: "/users/\(userHeader.userID)/profile")
		let profile = try profileResponse.content.decode(ProfilePublicData.self)
		let ctx = try PublicProfileContext(req, profile: profile)
		return try await req.view.render("User/userProfile", ctx)			
	}
	
	
	// GET /blocks
	//
	// Show the user a page listing all the accounts they have blocked or muted, and allowing the user to unblock/unmute
	// acconts. Has to exist here because a user generally can't get to the user profile page of a user they're blocking/muting,
	// and that's where the block/mute buttons are.
	// 
	// By design, blocks do not show alt accounts of the blocked person (although all alts belonging to a blocked account 
	// get blocked), nor does a blocked user see blocks applied against their account (although they won't be able to see 
	// content created by the blocking user).
	func blocksPageHandler(_ req: Request) async throws -> View {
		async let blocksResponse = try apiQuery(req, endpoint: "/users/blocks")
		async let mutesResponse = try await apiQuery(req, endpoint: "/users/mutes")
		let blockedUsers = try await blocksResponse.content.decode([UserHeader].self)
		let mutedUsers = try await mutesResponse.content.decode([UserHeader].self)
		struct BlocksContext : Encodable {
			var trunk: TrunkContext
			var blocks: [UserHeader]
			var mutes: [UserHeader]
			
			init(_ req: Request, blocks: [UserHeader], mutes: [UserHeader]) throws {
				trunk = .init(req, title: "Manage Blocks and Mutes", tab: .none)
				self.blocks = blocks
				self.mutes = mutes
			}
		}
		let ctx = try BlocksContext(req, blocks: blockedUsers, mutes: mutedUsers)
		return try await req.view.render("User/userBlocks", ctx)			
	}
	
	// POST /user/:user_ID/block
	//
	// Applies a block against the given user ID.
	func blockUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString) else {
			throw "Invalid username parameter"
		}
		try await apiQuery(req, endpoint: "/users/\(userID)/block", method: .POST)
		return .created
	}

	// POST /user/:user_ID/unblock
	//
	// Removes a block against the given user ID.
	func unblockUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString) else {
			throw "Invalid username parameter"
		}
		try await apiQuery(req, endpoint: "/users/\(userID)/unblock", method: .POST)
		return .ok
	}
	
	// POST /user/:user_ID/mute
	//
	// Mutes the given user ID.
	func muteUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString) else {
			throw "Invalid username parameter"
		}
		try await apiQuery(req, endpoint: "/users/\(userID)/mute", method: .POST)
		return .created
	}

	// POST /user/:user_ID/unmute
	//
	// Unmutes the given user ID.
	func unmuteUserPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString) else {
			throw "Invalid username parameter"
		}
		try await apiQuery(req, endpoint: "/users/\(userID)/unmute", method: .POST)
		return .ok
	}
	
	// GET /alertwords
	// GET /mutewords
	//
	// Shows a page with the user's mute and alert keywords, with controls for deleting current words
	// and adding new ones to each word set.
	func alertMuteWordsPageHandler(_ req: Request) async throws -> View {
		async let alertwordsResponse = try apiQuery(req, endpoint: "/user/alertwords")
		async let mutewordsResponse = try apiQuery(req, endpoint: "/user/mutewords")
		let alertwordsData = try await alertwordsResponse.content.decode(KeywordData.self)
		let mutewords = try await mutewordsResponse.content.decode(KeywordData.self)
		struct AlertwordsContext : Encodable {
			var trunk: TrunkContext
			var alertKeywords: [String]
			var muteKeywords: [String]
			
			init(_ req: Request, alertWords: [String], muteWords: [String]) throws {
				trunk = .init(req, title: "Manage Alertwords", tab: .none)
				self.alertKeywords = alertWords
				self.muteKeywords = muteWords
			}
		}
		let ctx = try AlertwordsContext(req, alertWords: alertwordsData.keywords, muteWords: mutewords.keywords)
		return try await req.view.render("User/alertwords", ctx)			
	}
	
	// POST /alertword/add
	//
	// Adds the word in the form to the user's list of alert keywords.
	func addAlertwordPostHandler(_ req: Request) async throws -> HTTPStatus {
		let alertwordFormStruct = try req.content.decode(AddWordFormStruct.self)
		guard let newAlertword = alertwordFormStruct.newKeyword?.percentEncodeQueryValue() else {
			throw "Invalid alertword parameter"
		}
		try await apiQuery(req, endpoint: "/user/alertwords/add/\(newAlertword)", method: .POST)
		return .created
	}

	// POST /muteword/add
	//
	// Adds the word in the form to the user's list of mute keywords.
	func addMutewordPostHandler(_ req: Request) async throws -> HTTPStatus {
		let mutewordFormStruct = try req.content.decode(AddWordFormStruct.self)
		guard let newMuteword = mutewordFormStruct.newKeyword?.percentEncodeQueryValue() else {
			throw "Invalid muteword parameter"
		}
		try await apiQuery(req, endpoint: "/user/mutewords/add/\(newMuteword)", method: .POST)
		return .created
	}

	// POST /alertword/:alert_word/remove
	//
	// Remove the given alert keyword.
	func removeAlertwordPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let alertWord = req.parameters.get(alertWordParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid alertword parameter"
		}
		try await apiQuery(req, endpoint: "/user/alertwords/remove/\(alertWord)", method: .POST)
		return .ok
	}

	// POST /muteword/:mute_word/remove
	//
	// Remove the given mute keyword.
	func removeMutewordPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let muteWord = req.parameters.get(muteWordParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid muteword parameter"
		}
		try await apiQuery(req, endpoint: "/user/mutewords/remove/\(muteWord)", method: .POST)
		return .ok
	}
	
	// GET /profile/edit
	//
	// Shows a user a page that lets them edit their own profile.
	func selfProfileEditPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/user/profile")
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
		return try await req.view.render("User/userProfileEdit", ctx)			
	}
	
	// GET /profile/edit/ID
	//
	// Shows mods a page that lets them edit others profiles. Note: Non-mods cannot use this endpoint
	// to edit their own profile, even if they pass in their own userID.
	func userProfileEditPageHandler(_ req: Request) async throws -> View {
		guard let targetUserID = req.parameters.get(userIDParam.paramString, as: UUID.self),
				let userAccessLevelStr = req.session.data["accessLevel"],
				let userAccessLevel = UserAccessLevel(rawValue: userAccessLevelStr),
				userAccessLevel.hasAccess(.moderator) else {
			// Actually trying to post changes to someone else's profile will fail at the API level, but we want
			// to catch it before showing the page.
			throw Abort(.forbidden, reason: "User isn't authorized to edit other users' profiles.")
		}
		let response = try await apiQuery(req, endpoint: "/users/\(targetUserID)/profile")
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
		return try await req.view.render("User/userProfileEdit", ctx)			
	}
	
	// POST /profile/edit
	// POST /profile/edit/:user_id
	//
	// Posts an edit to the user's own profile, or lets mods post edits to other user's profiles.
	func userProfileEditPostHandler(_ req: Request) async throws -> HTTPStatus {
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
		try await apiQuery(req, endpoint: path, method: .POST, encodeContent: postContent)
		if let targetUserIDVal = targetUserID {
			// Only mods can change another user's avatar, and the only allowed operation is to delete a custom avatar and replace 
			// it with the default (mods can't install a different custom pic)
			if profileStruct.serverAvatarPhoto.hasPrefix("/api/v3/image/user/identicon") {
				try await apiQuery(req, endpoint: "/user/\(targetUserIDVal)/image", method: .DELETE)
			}
		}
		else if let imageUploadData = ImageUploadData(nil, profileStruct.avatarPhotoInput) {
			try await apiQuery(req, endpoint: "/user/image", method: .POST, encodeContent: imageUploadData) 
		}
		else if profileStruct.serverAvatarPhoto.hasPrefix("/api/v3/image/user/identicon") {
			try await apiQuery(req, endpoint: "/user/image", method: .DELETE)
		}
		return .ok
	}
	
	// POST /profile/note/ID
	//
	func userNotePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let targetUserID = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
			throw "Invalid userID parameter"
		}
		struct ProfileNoteFormContent: Content {
			var noteText: String
		}
		let noteStruct = try req.content.decode(ProfileNoteFormContent.self)
		let postContent = NoteCreateData(note: noteStruct.noteText)
		try await apiQuery(req, endpoint: "/users/\(targetUserID)/note", method: .POST, encodeContent: postContent)
		return .ok
	}
	
	/// `GET /profile/report/ID`
	///
	/// Reports content in a user's profile, either the profile text fields or the avatar image. NOTE: This isn't reporting the **user**, you can't report
	/// users directly, just content they create. 
	func profileReportPageHandler(_ req: Request) async throws -> View {
		guard let targetUserID = req.parameters.get(userIDParam.paramString) else {
			throw "Invalid userID parameter"
		}
		let ctx = try ReportPageContext(req, userID: targetUserID)
		return try await req.view.render("reportCreate", ctx)
	}
	
	/// `POST /profile/report/ID`
	///
	func profileReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let targetUserID = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
			throw "Invalid userID parameter"
		}
		// The only field in ReportData is the message; we can use it as both the form data from the reportCreate webpage
		// and the DTO for the API layer.
		let postStruct = try req.content.decode(ReportData.self)
 		try await apiQuery(req, endpoint: "/users/\(targetUserID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}
}
