import Vapor
import Crypto
import FluentSQL

struct SiteAdminController: SiteControllerUtils {

	var dailyThemeParam = PathComponent(":theme_id")

	func registerRoutes(_ app: Application) throws {
		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateTTRoutes = getPrivateRoutes(app).grouped(SiteRequireTwitarrTeamMiddleware()).grouped("admin")
		
		privateTTRoutes.get("", use: adminRootPageHandler)

		privateTTRoutes.get("announcements", use: announcementsAdminPageHandler)
		privateTTRoutes.get("announcement", "create", use: announcementCreatePageHandler)
		privateTTRoutes.post("announcement", "create", use: announcementCreatePostHandler)
		privateTTRoutes.get("announcement", announcementIDParam, "edit", use: announcementEditPageHandler)
		privateTTRoutes.post("announcement", announcementIDParam, "edit", use: announcementEditPostHandler)
		privateTTRoutes.post("announcement", announcementIDParam, "delete", use: announcementDeletePostHandler)

		privateTTRoutes.get("dailythemes", use: dailyThemesViewHandler)
		privateTTRoutes.get("dailytheme", "create", use: dailyThemeCreateViewHandler)
		privateTTRoutes.post("dailytheme", "create", use: dailyThemeCreatePostHandler)
		privateTTRoutes.get("dailytheme", dailyThemeParam, "edit", use: dailyThemeEditViewHandler)
		privateTTRoutes.post("dailytheme", dailyThemeParam, "edit", use: dailyThemeEditPostHandler)
		privateTTRoutes.post("dailytheme", dailyThemeParam, "delete", use: dailyThemeDeletePostHandler)
		privateTTRoutes.delete("dailytheme", dailyThemeParam, use: dailyThemeDeletePostHandler)
		
		privateTTRoutes.get("serversettings", use: settingsViewHandler)
		privateTTRoutes.post("serversettings", use: settingsPostHandler)

		privateTTRoutes.get("scheduleupload", use: scheduleUploadViewHandler)
		privateTTRoutes.post("scheduleupload", use: scheduleUploadPostHandler)
		privateTTRoutes.get("scheduleverify", use: scheduleVerifyViewHandler)
		privateTTRoutes.post("scheduleverify", use: scheduleVerifyPostHandler)
		privateTTRoutes.get("scheduleupload", "complete", use: scheduleUpdateCompleteViewtHandler)

		privateTTRoutes.get("regcodes", use: getRegCodeHandler)
		
		privateTTRoutes.get("karaoke", "managers", use: getKaraokeManagersHandler)
		privateTTRoutes.post("user", userIDParam, "karaoke", "manager", "promote", use: promoteKaraokeManager)
		privateTTRoutes.post("user", userIDParam, "karaoke", "manager", "demote", use: demoteKaraokeManager)

		// Mods, TwitarrTeam, and THO levels can all be promoted to, but they all demote back to Verified.
		let privateTHORoutes = getPrivateRoutes(app).grouped(SiteRequireTHOMiddleware()).grouped("admin")
		privateTHORoutes.get("mods", use: getModsHandler)
		privateTHORoutes.get("twitarrteam", use: getTwitarrTeamHandler)
		privateTHORoutes.get("tho", use: getTHOHandler)
		privateTHORoutes.post("user", userIDParam, "moderator", "promote", use: promoteUserLevel)
		privateTHORoutes.post("user", userIDParam, "twitarrteam", "promote", use: promoteUserLevel)
		privateTHORoutes.post("user", userIDParam, "verified", "demote", use: demoteToVerified)
		
		let privateAdminRoutes = getPrivateRoutes(app).grouped(SiteRequireAdminMiddleware()).grouped("admin")
		privateAdminRoutes.post("user", userIDParam, "tho", "promote", use: promoteUserLevel)
		
		
	}
	
// MARK: - Admin Pages

	// This exists because we can't eval `displayUntil < Date()` inside Leaf.
	struct AnnouncementViewData: Content {
		var id: Int
		var author: UserHeader
		var text: String
		var updatedAt: Date
		var displayUntil: Date
		var isDeleted: Bool
		var isExpired: Bool
		
		init(from: AnnouncementData) {
			id = from.id
			author = from.author
			text = from.text
			updatedAt = from.updatedAt
			displayUntil = from.displayUntil
			isDeleted = from.isDeleted
			isExpired = from.displayUntil < Date()
		}
	}
	
	struct ManageUserLevelViewContext : Encodable {
		var trunk: TrunkContext
		var currentMembers: [UserHeader]
		var userSearch: String
		var searchResults: [UserHeader]?
		var levelName: String
		var targetLevel: String
		
		init(_ req: Request, current: [UserHeader], searchStr: String, searchResults: [UserHeader]?) throws {
			trunk = .init(req, title: "Manage Moderators", tab: .admin)
			self.currentMembers = current
			self.userSearch = searchStr
			self.searchResults = searchResults
			levelName = ""
			targetLevel = ""
		}
	}

	// GET /admin
	// Shows the root admin page, which just shows links to other pages.
	func adminRootPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct AdminRootPageContext : Encodable {
			var trunk: TrunkContext
			
			init(_ req: Request) throws {
				trunk = .init(req, title: "Server Admin", tab: .admin)
			}
		}
		let ctx = try AdminRootPageContext(req)
		return req.view.render("admin/root", ctx)
	}


	// GET /admin/announcements
	// Shows a list of all existing announcements
	func announcementsAdminPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/notification/announcements?inactives=true").throwingFlatMap { response in
 			let announcements = try response.content.decode([AnnouncementData].self)
 			let announcementViews = announcements.map { AnnouncementViewData(from: $0) }
			struct AnnouncementPageContext : Encodable {
				var trunk: TrunkContext
				var announcements: [AnnouncementViewData]
				
				init(_ req: Request, announcements: [AnnouncementViewData]) throws {
					trunk = .init(req, title: "Announcements", tab: .admin)
					self.announcements = announcements
				}
			}
			let ctx = try AnnouncementPageContext(req, announcements: announcementViews)
			return req.view.render("admin/announcements", ctx)
		}
	}
	
	// GET /admin/announcement/create
	func announcementCreatePageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct AnnouncementEditContext : Encodable {
			var trunk: TrunkContext
			var post: MessagePostContext
			var timeZoneName: String

			init(_ req: Request) throws {
				trunk = .init(req, title: "Create Announcement", tab: .admin)
				self.post = .init(forType: .announcement)
				timeZoneName = TimeZone.autoupdatingCurrent.abbreviation() ?? "EST"
			}
		}
		let ctx = try AnnouncementEditContext(req)
		return req.view.render("admin/announcementEdit", ctx)
	}
	
	// POST /admin/announcement/create
	func announcementCreatePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		guard let text = postStruct.postText, let displayUntil = postStruct.displayUntil else {
			throw Abort(.badRequest, reason: "Input form is missing members.")
		}
		guard let displayUntilDate = dateFromW3DatetimeString(displayUntil) else {
			throw Abort(.badRequest, reason: "Display Until date is misformatted.")
		}
		let postContent = AnnouncementCreateData(text: text, displayUntil: displayUntilDate)
		return apiQuery(req, endpoint: "/notification/announcement/create", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			if response.status.code < 300 {
				return Response(status: .created)
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
	}
	
	// GET /admin/announcement/ID/edit
	func announcementEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing announcement_id parameter.")
		}
		return apiQuery(req, endpoint: "/notification/announcement/\(announcementID)").throwingFlatMap { response in
 			let announcementData = try response.content.decode(AnnouncementData.self)

			struct AnnouncementEditContext : Encodable {
				var trunk: TrunkContext
				var post: MessagePostContext
				var timeZoneName: String

				init(_ req: Request, data: AnnouncementData) throws {
					trunk = .init(req, title: "Edit Announcement", tab: .admin)
					self.post = .init(forType: .announcementEdit(data))
					timeZoneName = TimeZone.autoupdatingCurrent.abbreviation() ?? "EST"
				}
			}
			let ctx = try AnnouncementEditContext(req, data: announcementData)
			return req.view.render("admin/announcementEdit", ctx)
		}
	}
	
	// POST /admin/announcement/ID/edit
	func announcementEditPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing announcement_id parameter.")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		guard let text = postStruct.postText, let displayUntil = postStruct.displayUntil else {
			throw Abort(.badRequest, reason: "Input form is missing members.")
		}
		guard let displayUntilDate = dateFromW3DatetimeString(displayUntil) else {
			throw Abort(.badRequest, reason: "Display Until date is misformatted.")
		}
		let postContent = AnnouncementCreateData(text: text, displayUntil: displayUntilDate)
		return apiQuery(req, endpoint: "/notification/announcement/\(announcementID)/edit", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			if response.status.code < 300 {
				return Response(status: .created)
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
	}
	
	// POST /admin/announcement/ID/delete
	//
	// Deletes an announcement.
	func announcementDeletePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/notification/announcement/\(announcementID)", method: .DELETE).map { response in
			return response.status
		}
	}
	
	// GET /admin/dailythemes
	// Shows all daily themes
	func dailyThemesViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/notification/dailythemes").throwingFlatMap { response in
 			let themeData = try response.content.decode([DailyThemeData].self)
			
			struct ThemeDataViewContext : Encodable {
				var trunk: TrunkContext
				var themes: [DailyThemeData]
				var currentCruiseDay: Int

				init(_ req: Request, data: [DailyThemeData]) throws {
					trunk = .init(req, title: "Daily Tmemes", tab: .admin)
					themes = data
					
					let cal = Calendar.current
					let components = cal.dateComponents([.day], from: cal.startOfDay(for: Settings.shared.cruiseStartDate), 
							to: cal.startOfDay(for: Date()))
					currentCruiseDay = Int(components.day ?? 0)

				}
			}
			let ctx = try ThemeDataViewContext(req, data: themeData)
			return req.view.render("admin/dailyThemes", ctx)
		}
	}
	
	// GET /admin/dailytheme/create
	func dailyThemeCreateViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct ThemeCreateViewContext : Encodable {
			var trunk: TrunkContext
			var post: MessagePostContext
			var breadcrumb: String

			init(_ req: Request) throws {
				trunk = .init(req, title: "Create New Daily Theme", tab: .admin)
				post = .init(forType: .theme)
				breadcrumb = "Create New Daily Theme"
			}
		}
		let ctx = try ThemeCreateViewContext(req)
		return req.view.render("admin/themeCreate", ctx)
	}
	
	// POST /admin/dailytheme/create
	func dailyThemeCreatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = DailyThemeUploadData(title: postStruct.forumTitle ?? "", info: postStruct.postText ?? "", 
				image: ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1), cruiseDay: postStruct.cruiseDay ?? 0)
		return apiQuery(req, endpoint: "/admin/dailytheme/create", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			return .created
		}
	}
	
	// GET /admin/dailytheme/ID/edit
	func dailyThemeEditViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let themeIDStr = req.parameters.get(dailyThemeParam.paramString), let themeID = UUID(themeIDStr) else {
    		throw "Invalid daily theme ID"
    	}
		return apiQuery(req, endpoint: "/notification/dailythemes").throwingFlatMap { response in
 			let themeData = try response.content.decode([DailyThemeData].self)
			guard let themeToEdit = themeData.first(where: { $0.themeID == themeID }) else {
				throw Abort(.badRequest, reason: "No Daily Theme found with id \(themeID).")
			}
		
			struct ThemeEditViewContext : Encodable {
				var trunk: TrunkContext
				var post: MessagePostContext
				var breadcrumb: String
				

				init(_ req: Request, _ theme: DailyThemeData) throws {
					trunk = .init(req, title: "Edit Daily Theme", tab: .admin)
					post = .init(forType: .themeEdit(theme))
					breadcrumb = "Edit Daily Theme"
				}
			}
			let ctx = try ThemeEditViewContext(req, themeToEdit)
			return req.view.render("admin/themeCreate", ctx)
		}
	}
	
	// POST /admin/dailytheme/ID/edit
	func dailyThemeEditPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let themeID = req.parameters.get(dailyThemeParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid daily theme ID"
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = DailyThemeUploadData(title: postStruct.forumTitle ?? "", info: postStruct.postText ?? "", 
				image: ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1), cruiseDay: postStruct.cruiseDay ?? 0)
		return apiQuery(req, endpoint: "/admin/dailytheme/\(themeID)/edit", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			 return .created
		}
	}
	
	// POST /admin/dailytheme/ID/delete
	// DELETE /admin/dailytheme/ID
	// Deletes a daily theme record.
	func dailyThemeDeletePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let themeID = req.parameters.get(dailyThemeParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid daily theme ID"
    	}
		return apiQuery(req, endpoint: "/admin/dailytheme/\(themeID)", method: .DELETE).map { response in
			return .noContent
		}
	}
	
	// GET /admin/serversettings
	//
	// Show a page for editing server settings values.
	func settingsViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/admin/serversettings", method: .GET).throwingFlatMap { response in
 			let settings = try response.content.decode(SettingsAdminData.self)
			struct SettingsViewContext : Encodable {
				var trunk: TrunkContext
				var settings: SettingsAdminData
				var clientAppNames: [String]
				var appFeatureNames: [String]

				init(_ req: Request, settings: SettingsAdminData) throws {
					trunk = .init(req, title: "Edit Server Settings", tab: .admin)
					self.settings = settings
					clientAppNames = SwiftarrClientApp.allCases.compactMap { $0 == .unknown ? nil : $0.rawValue }
					appFeatureNames = SwiftarrFeature.allCases.compactMap { $0 == .unknown ? nil : $0.rawValue }
				}
			}
			let ctx = try SettingsViewContext(req, settings: settings)
			return req.view.render("admin/serversettings", ctx)
		}
	}
	
	// POST /admin/serversettings
	//
	// Updates server settings.
	func settingsPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		// The web form decodes into this from a multipart-form
		struct SettingsPostFormContent: Decodable {
			var maxAlternateAccounts: Int
			var maximumTwarrts: Int
			var maximumForums: Int
			var maximumForumPosts: Int
			var maxImageSize: Int
			var forumAutoQuarantineThreshold: Int
			var postAutoQuarantineThreshold: Int
			var userAutoQuarantineThreshold: Int
			var shipWifiSSID: String?
			var allowAnimatedImages: String?
			var disableAppName: String
			var disableFeatureName: String
			// In the .leaf file, the name property for the select that sets this is "reenable[]". 
			// The "[]" in the name is magic, somewhere in multipart-kit. It collects all form-data value with the same name into an array.
			var reenable: [String]?				
		}
		let postStruct = try req.content.decode(SettingsPostFormContent.self)
		
		// The API lets us apply multiple app:feature disables at once, but the UI can only add one at a time.
		var enablePairs: [SettingsAppFeaturePair] = []
		var disablePairs: [SettingsAppFeaturePair] = []
		if !postStruct.disableAppName.isEmpty && !postStruct.disableFeatureName.isEmpty	{
			disablePairs.append(SettingsAppFeaturePair(app: postStruct.disableAppName, feature: postStruct.disableFeatureName))
		}
		
		if let reenables = postStruct.reenable {
			for pair in reenables {
				let parts = pair.split(separator: ":")
				if parts.count != 2 { continue }
				enablePairs.append(SettingsAppFeaturePair(app: String(parts[0]), feature: String(parts[1])))
			}
		}

		let apiPostContent = SettingsUpdateData(
				maxAlternateAccounts: postStruct.maxAlternateAccounts,
				maximumTwarrts: postStruct.maximumTwarrts,
				maximumForums: postStruct.maximumForums, 
				maximumForumPosts: postStruct.maximumForumPosts, 
				maxImageSize: postStruct.maxImageSize * 1048576, 
				forumAutoQuarantineThreshold: postStruct.forumAutoQuarantineThreshold, 
				postAutoQuarantineThreshold: postStruct.postAutoQuarantineThreshold, 
				userAutoQuarantineThreshold: postStruct.userAutoQuarantineThreshold, 
				allowAnimatedImages: postStruct.allowAnimatedImages == "on",
				enableFeatures: enablePairs, disableFeatures: disablePairs,
				shipWifiSSID: postStruct.shipWifiSSID)
		return apiQuery(req, endpoint: "/admin/serversettings/update", method: .POST, beforeSend: { req throws in
			try req.content.encode(apiPostContent)
		}).flatMapThrowing { response in
			return .ok
		}	
	}
	
	// GET /admin/scheduleupload
	//
	// Shows a form with a file upload button for upload a new schedule.ics file. This the start of a flow, going from
	// scheduleupload to scheduleverify to scheduleapply.
	func scheduleUploadViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct ScheduleUploadViewContext : Encodable {
			var trunk: TrunkContext

			init(_ req: Request) throws {
				trunk = .init(req, title: "Upload Schedule", tab: .admin)
			}
		}
		let ctx = try ScheduleUploadViewContext(req)
		return req.view.render("admin/scheduleUpload", ctx)
	}
	
	// POST /admin/scheduleupload
	//
	// Handles the POST of an uploaded schedule file. Reads the file in and saves it in "<workingDir>/admin/uploadschedule.ics".
	// Does not immediately parse the file or apply it to the DB. See scheduleVerifyViewHandler().
	func scheduleUploadPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		struct ScheduleUploadData: Content {
			/// The schedule in `String` format. 
			var schedule: String
		}
		let uploadData = try req.content.decode(ScheduleUploadData.self)
		return apiQuery(req, endpoint: "/admin/schedule/update", method: .POST, beforeSend: { req throws in
			let apiPostData = EventsUpdateData(schedule: uploadData.schedule)
			try req.content.encode(apiPostData)
		}).transform(to: .ok)
	}
	
	// GET /admin/scheduleverify
	//
	// Displays a page showing the schedule changes that will happen when the (saved) uploaded schedule is applied.
	// We diff the existing schedule with the new update, and display the adds, deletes, and modified events for review.
	// This page also has a form where the user can approve the changes to apply them to the db. 
	func scheduleVerifyViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/admin/schedule/verify").throwingFlatMap { response in
			let differenceData = try response.content.decode(EventUpdateDifferenceData.self)

			struct ScheduleUpdateVerifyViewContext : Encodable {
				var trunk: TrunkContext
				var diff: EventUpdateDifferenceData
				
				init(_ req: Request, differenceData: EventUpdateDifferenceData) throws {
					trunk = .init(req, title: "Edit Daily Theme", tab: .admin)
					self.diff = differenceData
				}
			}
			let ctx = try ScheduleUpdateVerifyViewContext(req, differenceData: differenceData)
			return req.view.render("admin/scheduleVerify", ctx)
		}
	}
	
	// POST /admin/scheduleverify
	//
	// Handled the POST from the schedule verify page form. Schedule Verify shows the admin the changes that will be applied
	// before they happen. Accepting the changes POSTs to here. There are 2 options on the form as well:
	// - Add Posts in Forum Thread. This option, if selected, will create a post in the Event Forum thread of each affected
	//	 event, (except maybe creates?) explaining the change that occurred.
	// - Ignore Deleted Events. This option causes deletes to not be applied. In a case where you need to update a single event's
	// 	 time or location, you could make a .ics that only contains that event and upload/apply that file. Without this 
	// 	 option, that one event would be considered an exhaustive list of events for the week, and all other events would be deleted.
	func scheduleVerifyPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		struct ScheduleVerifyData: Content {
			var addForumPosts: String?
			var ignoreDeletes: String?
		}
		let formData = try req.content.decode(ScheduleVerifyData.self)
		var query = [URLQueryItem]()
		if formData.addForumPosts == "on" {
			query.append(URLQueryItem(name: "forumPosts", value: "true"))
		}
		if formData.ignoreDeletes != "on" {
			query.append(URLQueryItem(name: "processDeletes", value: "true"))
		}
		var components = URLComponents()
		components.queryItems = query
		return apiQuery(req, endpoint: "/admin/schedule/update/apply?\(components.percentEncodedQuery ?? "")",
				method: .POST).map { response in
			return .ok
		}
	}
	
	// GET /admin/scheduleupload/complete
	//
	func scheduleUpdateCompleteViewtHandler(_ req: Request) throws -> EventLoopFuture<View> {
			struct ScheduleUpdateCompleteViewContext : Encodable {
				var trunk: TrunkContext
				
				init(_ req: Request) throws {
					trunk = .init(req, title: "Schedule Update Complete", tab: .admin)
				}
			}
			let ctx = try ScheduleUpdateCompleteViewContext(req)
			return req.view.render("admin/scheduleUpdateComplete", ctx)
	}
	
	// GET /admin/regcodes
	//
	// Shows stats on reg code use. Lets admins search on a regcode and get the user it's associated with, if any.
	func getRegCodeHandler(_ req: Request) throws -> EventLoopFuture<View> {
        var regCodeSearchFuture: EventLoopFuture<String> = req.eventLoop.future("")
		if var regCode = req.query[String.self, at: "search"]?.removingPercentEncoding?.lowercased() {
			regCode.removeAll { $0 == " " }
			if regCode.count == 6, regCode.allSatisfy({ $0.isLetter || $0.isNumber }) {
				regCodeSearchFuture = apiQuery(req, endpoint: "/admin/regcodes/find/\(regCode)").flatMapThrowing { response in
					let headers = try response.content.decode([UserHeader].self)
					if headers.count > 0 {
						return "User \"\(headers[0].username)\" is associated with registration code \"\(regCode)\""
					}
					else {
						return "\(regCode) is a valid code, not associated with a user."
					}
				}.flatMapError { error in 
					if let apiError = error as? ErrorResponse {
						return req.eventLoop.future("Error: \(apiError.reason)")
					}
					return req.eventLoop.future("\(error)")
				}
			}
			else {
				regCodeSearchFuture = req.eventLoop.future("Invalid registration code")
			}
       	}
		return apiQuery(req, endpoint: "/admin/regcodes/stats").and(regCodeSearchFuture).throwingFlatMap { (response, searchResults) in
			let regCodeData = try response.content.decode(RegistrationCodeStatsData.self)
			struct RegCodeStatsContext : Encodable {
				var trunk: TrunkContext
				var stats: RegistrationCodeStatsData
				var searchResults: String
				
				init(_ req: Request, stats: RegistrationCodeStatsData, searchResults: String) throws {
					trunk = .init(req, title: "Registration Codes", tab: .admin)
					self.stats = stats
					self.searchResults = searchResults
				}
			}
			let ctx = try RegCodeStatsContext(req, stats: regCodeData, searchResults: searchResults)
			return req.view.render("admin/regcodes", ctx)
		}
	}
	
	// GET /admin/mods
	//
	// Only THO and above--mods cannot make more mods.
	func getModsHandler(_ req: Request) throws -> EventLoopFuture<View> {
		var searchFuture: EventLoopFuture<[UserHeader]?> = req.eventLoop.future(nil)
		var searchStr = ""
		if let str = req.query[String.self, at: "search"]?.percentEncodeFilePathEntry() {
			searchStr = str
			searchFuture = apiQuery(req, endpoint: "/users/match/allnames/\(searchStr)").flatMapThrowing { response in
				return try response.content.decode([UserHeader].self)
			}
		}
		return apiQuery(req, endpoint: "/admin/moderators").and(searchFuture).throwingFlatMap { (response, searchResults) in
			let currentMembers = try response.content.decode([UserHeader].self)
			var ctx = try ManageUserLevelViewContext(req, current: currentMembers, searchStr: searchStr, searchResults: searchResults)
			ctx.levelName = "Moderator"
			ctx.targetLevel = "moderator"
			return req.view.render("admin/showModerators", ctx)
		}
	}

	// GET /admin/twitarrteam
	//
	// Only THO and above may see this
	func getTwitarrTeamHandler(_ req: Request) throws -> EventLoopFuture<View> {
		var searchFuture: EventLoopFuture<[UserHeader]?> = req.eventLoop.future(nil)
		var searchStr = ""
		if let str = req.query[String.self, at: "search"]?.percentEncodeFilePathEntry() {
			searchStr = str
			searchFuture = apiQuery(req, endpoint: "/users/match/allnames/\(searchStr)").flatMapThrowing { response in
				return try response.content.decode([UserHeader].self)
			}
		}
		return apiQuery(req, endpoint: "/admin/twitarrteam").and(searchFuture).throwingFlatMap { (response, searchResults) in
			let currentMembers = try response.content.decode([UserHeader].self)
			var ctx = try ManageUserLevelViewContext(req, current: currentMembers, searchStr: searchStr, searchResults: searchResults)
			ctx.levelName = "TwitarrTeam"
			ctx.targetLevel = "twitarrteam"
			return req.view.render("admin/showModerators", ctx)
		}
	}
	
	// GET /admin/tho
	//
	// Only THO and above may see this
	func getTHOHandler(_ req: Request) throws -> EventLoopFuture<View> {
		var searchFuture: EventLoopFuture<[UserHeader]?> = req.eventLoop.future(nil)
		var searchStr = ""
		if let str = req.query[String.self, at: "search"]?.percentEncodeFilePathEntry() {
			searchStr = str
			searchFuture = apiQuery(req, endpoint: "/users/match/allnames/\(searchStr)").flatMapThrowing { response in
				return try response.content.decode([UserHeader].self)
			}
		}
		return apiQuery(req, endpoint: "/admin/tho").and(searchFuture).throwingFlatMap { (response, searchResults) in
			let currentMembers = try response.content.decode([UserHeader].self)
			var ctx = try ManageUserLevelViewContext(req, current: currentMembers, searchStr: searchStr, searchResults: searchResults)
			ctx.levelName = "THO"
			ctx.targetLevel = "tho"
			return req.view.render("admin/showModerators", ctx)
		}
	}

	// POST /admin/user/:user_id/moderator/promote
	// POST /admin/user/:user_id/twitarrteam/promote
	// POST /admin/user/:user_id/tho/promote
	//
	func promoteUserLevel(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid user ID"
    	}
    	var targetLevel = "moderator"
    	if let pathCount = req.route?.path.count, pathCount == 5, let urlLevel = req.route?.path[3].paramString {
    		if urlLevel == "twitarrteam" || urlLevel == "tho" {
    			targetLevel = urlLevel
    		}
    	}
		return apiQuery(req, endpoint: "/admin/\(targetLevel)/promote/\(userID)", method: .POST).map { response in
			return response.status
		}
	}
	
	// POST /admin/user/:user_id/verified/demote
	//
	func demoteToVerified(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid user ID"
    	}
		return apiQuery(req, endpoint: "/admin/user/demote/\(userID)", method: .POST).map { response in
			return response.status
		}
	}
	
	// GET /admin/karaoke/managers
	//
	func getKaraokeManagersHandler(_ req: Request) throws -> EventLoopFuture<View> {
		var searchFuture: EventLoopFuture<[UserHeader]?> = req.eventLoop.future(nil)
		var searchStr = ""
		if let str = req.query[String.self, at: "search"]?.percentEncodeFilePathEntry() {
			searchStr = str
			searchFuture = apiQuery(req, endpoint: "/users/match/allnames/\(searchStr)").flatMapThrowing { response in
				return try response.content.decode([UserHeader].self)
			}
		}
		return apiQuery(req, endpoint: "/admin/karaoke/managers").and(searchFuture).throwingFlatMap { (response, searchResults) in
			let currentMgrs = try response.content.decode([UserHeader].self)
			struct KaraokeManagersViewContext : Encodable {
				var trunk: TrunkContext
				var currentMgrs: [UserHeader]
				var userSearch: String
				var searchResults: [UserHeader]?
				
				init(_ req: Request, currentMgrs: [UserHeader], searchStr: String, searchResults: [UserHeader]?) throws {
					trunk = .init(req, title: "Karaoke Managers", tab: .admin)
					self.currentMgrs = currentMgrs
					self.userSearch = searchStr
					self.searchResults = searchResults
				}
			}
			let ctx = try KaraokeManagersViewContext(req, currentMgrs: currentMgrs, searchStr: searchStr, searchResults: searchResults)
			return req.view.render("admin/showKaraokeManagers", ctx)
		}
	}

	// POST /admin/user/:user_id/karaoke/manager/promote
	//
	func promoteKaraokeManager(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid user ID"
    	}
		return apiQuery(req, endpoint: "/admin/karaoke/manager/promote/\(userID)", method: .POST).map { response in
			return response.status
		}
	}
	
	// POST /admin/user/:user_id/karaoke/manager/demote
	//
	func demoteKaraokeManager(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid user ID"
    	}
		return apiQuery(req, endpoint: "/admin/karaoke/manager/demote/\(userID)", method: .POST).map { response in
			return response.status
		}
	}
}

