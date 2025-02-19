import FluentSQL
import Vapor

// Used by the rollup code to map a user-readable name for each table row.
extension ServerRollupData.CountType {
	func name() -> String {
		switch self {
			case .user: return "Users"
			case .profileEdit: return "Profile Edits"
			case .userNote: return "User Notes"
			case .alertword: return "Alert Words"
			case .muteword: return "Mute Words"
			case .photoStream: return "Photo Stream Photos"
			case .lfg: return "LFGs"
			case .lfgParticipant: return "LFG Participants"
			case .lfgPost: return "LFG Posts"
			case .seamail: return "Seamails"
			case .seamailPost: return "Seamail Posts"
			case .forum: return "Forum Threads"
			case .forumPost: return "Forum Posts"
			case .forumPostEdit: return "Forum Post Edits"
			case .forumPostLike: return "Forum Post Likes"
			case .karaokePlayedSong: return "Karaoke Played Songs"
			case .microKaraokeSnippet: return "Micro Karaoke Snippets"
			case .userFavorite: return "User Favorites"
			case .eventFavorite: return "Event Favorites"
			case .forumFavorite: return "Forum Favorites"
			case .forumPostFavorite: return "Forum Post Favorites"
			case .boardgameFavorite: return "Boardgame Favorites"
			case .karaokeFavorite: return "Karaoke Song Favorites"
			case .report: return "Moderation Reports"
			case .moderationAction: return "Moderation Actions"
		}
	}
}

struct SiteAdminController: SiteControllerUtils {

	var dailyThemeParam = PathComponent(":theme_id")
	var userRoleParam = PathComponent(":user_role")

	func registerRoutes(_ app: Application) throws {
		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateTTRoutes = getPrivateRoutes(app, minAccess: .twitarrteam, path: "admin")

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
		privateTTRoutes.get("rollup", use: rollupHandler)

		privateTTRoutes.get("timezonechanges", use: timeZonesViewHandler)
		privateTTRoutes.post("serversettings", "reloadtzfile", use: settingsReloadTZFilePostHandler)

		privateTTRoutes.get("schedule", use: scheduleManagerViewHandler)
		privateTTRoutes.post("scheduleupload", use: scheduleUploadPostHandler)
		privateTTRoutes.get("scheduleverify", use: scheduleVerifyViewHandler)
		privateTTRoutes.post("scheduleverify", use: scheduleVerifyPostHandler)
		privateTTRoutes.get("scheduleupload", "complete", use: scheduleUpdateCompleteViewtHandler)
		privateTTRoutes.get("schedulelogview", scheduleLogIDParam, use: scheduleLogEntryViewer)
		privateTTRoutes.post("schedulereload", use: scheduleReloadHandler)
		privateTTRoutes.post("notificationcheck", use: notificationConsistencyCheckHandler)

		
		privateTTRoutes.get("bulkuser", use: bulkUserRootViewHandler)
		privateTTRoutes.get("bulkuser", "download", use: bulkUserFileDownload)
		privateTTRoutes.on(.POST, "bulkuser", "upload", body: .collect(maxSize: "1gb"), use: bulkUserfileUploadPostHandler)
		privateTTRoutes.get("bulkuser", "upload", "verify", use: bulkUserVerifyViewHandler)
		privateTTRoutes.get("bulkuser", "upload", "commit", use: bulkUserUpdateCommitHandler)
		

		privateTTRoutes.get("regcodes", use: getRegCodeHandler)
		privateTTRoutes.get("regcodes", "showuser", userIDParam, use: getRegCodeForUserHandler)
		privateTTRoutes.get("regcodes", "discord", "assign", use: assignRegCodeToDiscordUser)
		privateTTRoutes.post("regcodes", "discord", "assign", use: assignRegCodeToDiscordUserResult)
		

		privateTTRoutes.get("userroles", use: getUserRoleManagementHandler)
		privateTTRoutes.get("userroles", userRoleParam, use: getUserRoleManagementHandler)
		privateTTRoutes.post("userroles", userRoleParam, "addrole", userIDParam, use: addRoleToUser)
		privateTTRoutes.post("userroles", userRoleParam, "removerole", userIDParam, use: removeRoleFromUser)

		
		privateTTRoutes.get("hunts", use: huntHandler)
		privateTTRoutes.post("hunt", "create", use: huntPostHandler)
		privateTTRoutes.post("hunt", huntIDParam, "delete", use: huntDeleteHandler)
		privateTTRoutes.get("hunt", huntIDParam, "edit", use: huntEditHandler)
		privateTTRoutes.post("hunt", huntIDParam, "edit", use: huntEditPostHandler)
		privateTTRoutes.post("puzzle", puzzleIDParam, "edit", use: puzzleEditPostHandler)

		// Mods, TwitarrTeam, and THO levels can all be promoted to, but they all demote back to Verified.
		let privateTHORoutes = getPrivateRoutes(app, minAccess: .tho, path: "admin")
		privateTHORoutes.get("mods", use: getModsHandler)
		privateTHORoutes.get("twitarrteam", use: getTwitarrTeamHandler)
		privateTHORoutes.get("tho", use: getTHOHandler)
		privateTHORoutes.post("user", userIDParam, "moderator", "promote", use: promoteUserLevel)
		privateTHORoutes.post("user", userIDParam, "twitarrteam", "promote", use: promoteUserLevel)
		privateTHORoutes.post("user", userIDParam, "verified", "demote", use: demoteToVerified)

		let privateAdminRoutes = getPrivateRoutes(app, minAccess: .admin, path: "admin")
		privateAdminRoutes.post("user", userIDParam, "tho", "promote", use: promoteUserLevel)
		privateAdminRoutes.get("karaoke", use: karaokeHandler)
		privateAdminRoutes.post("karaoke", "reload", use: karaokePostHandler)
		privateAdminRoutes.get("boardgames", use: boardGamesHandler)
		privateAdminRoutes.post("boardgames", "reload", use: boardGamesPostHandler)
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

	struct ManageUserLevelViewContext: Encodable {
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
	func adminRootPageHandler(_ req: Request) async throws -> View {
		struct AdminRootPageContext: Encodable {
			var trunk: TrunkContext

			init(_ req: Request) throws {
				trunk = .init(req, title: "Server Admin", tab: .admin)
			}
		}
		let ctx = try AdminRootPageContext(req)
		return try await req.view.render("admin/root", ctx)
	}
	
// MARK: - Announcements
	// GET /admin/announcements
	// Shows a list of all existing announcements
	func announcementsAdminPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/notification/announcements?inactives=true")
		let announcements = try response.content.decode([AnnouncementData].self)
		let announcementViews = announcements.map { AnnouncementViewData(from: $0) }
		struct AnnouncementPageContext: Encodable {
			var trunk: TrunkContext
			var announcements: [AnnouncementViewData]

			init(_ req: Request, announcements: [AnnouncementViewData]) throws {
				trunk = .init(req, title: "Announcements", tab: .admin)
				self.announcements = announcements
			}
		}
		let ctx = try AnnouncementPageContext(req, announcements: announcementViews)
		return try await req.view.render("admin/announcements", ctx)
	}

	// GET /admin/announcement/create
	func announcementCreatePageHandler(_ req: Request) async throws -> View {
		struct AnnouncementEditContext: Encodable {
			var trunk: TrunkContext
			var post: MessagePostContext

			init(_ req: Request) throws {
				trunk = .init(req, title: "Create Announcement", tab: .admin)
				self.post = .init(forType: .announcement)
			}
		}
		let ctx = try AnnouncementEditContext(req)
		return try await req.view.render("admin/announcementEdit", ctx)
	}

	// POST /admin/announcement/create
	func announcementCreatePostHandler(_ req: Request) async throws -> HTTPStatus {
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		guard let text = postStruct.postText, let displayUntil = postStruct.displayUntil else {
			throw Abort(.badRequest, reason: "Input form is missing members.")
		}
		guard let displayUntilDate = dateFromW3DatetimeString(displayUntil) else {
			throw Abort(.badRequest, reason: "Display Until date is misformatted.")
		}
		let postContent = AnnouncementCreateData(text: text, displayUntil: displayUntilDate)
		try await apiQuery(
			req,
			endpoint: "/notification/announcement/create",
			method: .POST,
			encodeContent: postContent
		)
		return .created
	}

	// GET /admin/announcement/ID/edit
	func announcementEditPageHandler(_ req: Request) async throws -> View {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString)?.percentEncodeFilePathEntry()
		else {
			throw Abort(.badRequest, reason: "Missing announcement_id parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/notification/announcement/\(announcementID)")
		let announcementData = try response.content.decode(AnnouncementData.self)

		struct AnnouncementEditContext: Encodable {
			var trunk: TrunkContext
			var post: MessagePostContext

			init(_ req: Request, data: AnnouncementData) throws {
				trunk = .init(req, title: "Edit Announcement", tab: .admin)
				self.post = .init(forType: .announcementEdit(data))
			}
		}
		let ctx = try AnnouncementEditContext(req, data: announcementData)
		return try await req.view.render("admin/announcementEdit", ctx)
	}

	// POST /admin/announcement/ID/edit
	func announcementEditPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString)?.percentEncodeFilePathEntry()
		else {
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
		try await apiQuery(
			req,
			endpoint: "/notification/announcement/\(announcementID)/edit",
			method: .POST,
			encodeContent: postContent
		)
		return .created
	}

	// POST /admin/announcement/ID/delete
	//
	// Deletes an announcement.
	func announcementDeletePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let announcementID = req.parameters.get(announcementIDParam.paramString)?.percentEncodeFilePathEntry()
		else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let response = try await apiQuery(
			req,
			endpoint: "/notification/announcement/\(announcementID)",
			method: .DELETE
		)
		return response.status
	}

// MARK: - Daily Themes
	// GET /admin/dailythemes
	// Shows all daily themes
	func dailyThemesViewHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/notification/dailythemes")
		let themeData = try response.content.decode([DailyThemeData].self)

		struct ThemeDataViewContext: Encodable {
			var trunk: TrunkContext
			var themes: [DailyThemeData]
			var currentCruiseDay: Int

			init(_ req: Request, data: [DailyThemeData]) throws {
				trunk = .init(req, title: "Daily Tmemes", tab: .admin)
				themes = data

				let cal = Settings.shared.getPortCalendar()
				let components = cal.dateComponents(
					[.day],
					from: cal.startOfDay(for: Settings.shared.cruiseStartDate()),
					to: cal.startOfDay(for: Date())
				)
				currentCruiseDay = Int(components.day ?? 0)
			}
		}
		let ctx = try ThemeDataViewContext(req, data: themeData)
		return try await req.view.render("admin/dailyThemes", ctx)
	}

	// GET /admin/dailytheme/create
	func dailyThemeCreateViewHandler(_ req: Request) async throws -> View {
		struct ThemeCreateViewContext: Encodable {
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
		return try await req.view.render("admin/themeCreate", ctx)
	}

	// POST /admin/dailytheme/create
	func dailyThemeCreatePostHandler(_ req: Request) async throws -> HTTPStatus {
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = DailyThemeUploadData(
			title: postStruct.forumTitle ?? "",
			info: postStruct.postText ?? "",
			image: ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
			cruiseDay: postStruct.cruiseDay ?? 0
		)
		try await apiQuery(req, endpoint: "/admin/dailytheme/create", method: .POST, encodeContent: postContent)
		return .created
	}

	// GET /admin/dailytheme/ID/edit
	func dailyThemeEditViewHandler(_ req: Request) async throws -> View {
		guard let themeIDStr = req.parameters.get(dailyThemeParam.paramString), let themeID = UUID(themeIDStr) else {
			throw "Invalid daily theme ID"
		}
		let response = try await apiQuery(req, endpoint: "/notification/dailythemes")
		let themeData = try response.content.decode([DailyThemeData].self)
		guard let themeToEdit = themeData.first(where: { $0.themeID == themeID }) else {
			throw Abort(.badRequest, reason: "No Daily Theme found with id \(themeID).")
		}

		struct ThemeEditViewContext: Encodable {
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
		return try await req.view.render("admin/themeCreate", ctx)
	}

	// POST /admin/dailytheme/ID/edit
	func dailyThemeEditPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let themeID = req.parameters.get(dailyThemeParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid daily theme ID"
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = DailyThemeUploadData(
			title: postStruct.forumTitle ?? "",
			info: postStruct.postText ?? "",
			image: ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
			cruiseDay: postStruct.cruiseDay ?? 0
		)
		try await apiQuery(
			req,
			endpoint: "/admin/dailytheme/\(themeID)/edit",
			method: .POST,
			encodeContent: postContent
		)
		return .created
	}

	// POST /admin/dailytheme/ID/delete
	// DELETE /admin/dailytheme/ID
	// Deletes a daily theme record.
	func dailyThemeDeletePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let themeID = req.parameters.get(dailyThemeParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid daily theme ID"
		}
		try await apiQuery(req, endpoint: "/admin/dailytheme/\(themeID)", method: .DELETE)
		return .noContent
	}

// MARK: - Settings
	// GET /admin/serversettings
	//
	// Show a page for editing server settings values.
	func settingsViewHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/admin/serversettings", method: .GET)
		let settings = try response.content.decode(SettingsAdminData.self)
		struct SettingsViewContext: Encodable {
			var trunk: TrunkContext
			var settings: SettingsAdminData
			var clientAppNames: [String]
			var appFeatureNames: [String]
			var enableFields: Bool

			init(_ req: Request, settings: SettingsAdminData) throws {
				trunk = .init(req, title: "Edit Server Settings", tab: .admin)
				self.settings = settings
				clientAppNames = SwiftarrClientApp.allCases.compactMap { $0 == .unknown ? nil : $0.rawValue }
				appFeatureNames = SwiftarrFeature.allCases.compactMap { $0 == .unknown ? nil : $0.rawValue }
				enableFields = trunk.username == "admin" ? true : false
			}
		}
		let ctx = try SettingsViewContext(req, settings: settings)
		return try await req.view.render("admin/serversettings", ctx)
	}

	// POST /admin/serversettings
	//
	// Updates server settings.
	func settingsPostHandler(_ req: Request) async throws -> HTTPStatus {
		// The web form decodes into this from a multipart-form
		struct SettingsPostFormContent: Decodable {
			var minAccessLevel: String
			var enablePreregistration: String?
			var maxAlternateAccounts: Int
			var maximumTwarrts: Int
			var maximumForums: Int
			var maximumForumPosts: Int
			var maxImageSize: Int
			var forumAutoQuarantineThreshold: Int
			var postAutoQuarantineThreshold: Int
			var userAutoQuarantineThreshold: Int
			var shipWifiSSID: String?
			var scheduleUpdateURL: String?
			var allowAnimatedImages: String?
			var disableAppName: String
			var disableFeatureName: String
			var upcomingEventNotificationSeconds: Int
			var upcomingEventNotificationSetting: EventNotificationSetting
			var upcomingLFGNotificationSetting: EventNotificationSetting
			// In the .leaf file, the name property for the select that sets this is "reenable[]".
			// The "[]" in the name is magic, somewhere in multipart-kit. It collects all form-data value with the same name into an array.
			var reenable: [String]?
			var enableSiteNotificationDataCaching: String?
		}
		let postStruct = try req.content.decode(SettingsPostFormContent.self)

		// The API lets us apply multiple app:feature disables at once, but the UI can only add one at a time.
		var enablePairs: [SettingsAppFeaturePair] = []
		var disablePairs: [SettingsAppFeaturePair] = []
		if !postStruct.disableAppName.isEmpty && !postStruct.disableFeatureName.isEmpty {
			disablePairs.append(
				SettingsAppFeaturePair(app: postStruct.disableAppName, feature: postStruct.disableFeatureName)
			)
		}

		if let reenables = postStruct.reenable {
			for pair in reenables {
				let parts = pair.split(separator: ":")
				if parts.count != 2 { continue }
				enablePairs.append(SettingsAppFeaturePair(app: String(parts[0]), feature: String(parts[1])))
			}
		}

		let apiPostContent = SettingsUpdateData(
			minUserAccessLevel: postStruct.minAccessLevel,
			enablePreregistration: postStruct.enablePreregistration == "on",
			maxAlternateAccounts: postStruct.maxAlternateAccounts,
			maximumTwarrts: postStruct.maximumTwarrts,
			maximumForums: postStruct.maximumForums,
			maximumForumPosts: postStruct.maximumForumPosts,
			maxImageSize: postStruct.maxImageSize * 1_048_576,
			forumAutoQuarantineThreshold: postStruct.forumAutoQuarantineThreshold,
			postAutoQuarantineThreshold: postStruct.postAutoQuarantineThreshold,
			userAutoQuarantineThreshold: postStruct.userAutoQuarantineThreshold,
			allowAnimatedImages: postStruct.allowAnimatedImages == "on",
			enableFeatures: enablePairs,
			disableFeatures: disablePairs,
			shipWifiSSID: postStruct.shipWifiSSID,
			scheduleUpdateURL: postStruct.scheduleUpdateURL,
			upcomingEventNotificationSeconds: postStruct.upcomingEventNotificationSeconds,
			upcomingEventNotificationSetting: postStruct.upcomingEventNotificationSetting,
			upcomingLFGNotificationSetting: postStruct.upcomingLFGNotificationSetting,
			enableSiteNotificationDataCaching: postStruct.enableSiteNotificationDataCaching == "on"
		)
		try await apiQuery(req, endpoint: "/admin/serversettings/update", method: .POST, encodeContent: apiPostContent)
		return .ok
	}

	// POST /admin/serversettings/reloadtzfile
	//
	// Kicks off a reload operation. Admin only; the new time zone data file must be uploaded to /seeds, probably via git push.
	func settingsReloadTZFilePostHandler(_ req: Request) async throws -> HTTPStatus {
		try await apiQuery(req, endpoint: "/admin/timezonechanges/reloadtzdata", method: .POST)
		return .ok
	}
	
	// GET /admin/rollup
	//
	// Shows a table containing row counts for several database tables.
	func rollupHandler(_ req: Request) async throws -> View {
		let apiResponse = try await apiQuery(req, endpoint: "/admin/rollup")
		let response = try apiResponse.content.decode(ServerRollupData.self)
		struct TableRow: Encodable {
			var title: String
			var total: Int32
		}
		let rows = response.counts.enumerated().map { TableRow(title: ServerRollupData.CountType(rawValue: $0)?.name() ?? "unknown", total: $1) }
		struct RollupContext: Encodable {
			var trunk: TrunkContext
			var tableRows: [TableRow]
		}
		let ctx = RollupContext(trunk: .init(req, title: "Server Counts", tab: .admin), tableRows: rows)
		return try await req.view.render("admin/serverRollup", ctx)
	}

// MARK: - TZ, Karaoke, Games, Hunts
	// GET /admin/timezonechanges
	//
	// Shows the list of time zone changes that occur during the cruise.
	func timeZonesViewHandler(_ req: Request) async throws -> View {
		let apiResponse = try await apiQuery(req, endpoint: "/admin/timezonechanges", method: .GET)
		let response = try apiResponse.content.decode(TimeZoneChangeData.self)
		struct TZViewContext: Encodable {
			var trunk: TrunkContext
			var timeZones: TimeZoneChangeData

			init(_ req: Request, timeZones: TimeZoneChangeData) throws {
				trunk = .init(req, title: "Time Zone Change Table", tab: .admin)
				self.timeZones = timeZones
			}
		}
		let ctx = try TZViewContext(req, timeZones: response)
		return try await req.view.render("admin/timezonechanges", ctx)
	}

	// GET /admin/karaoke
	//
	// Shows administrator settings for karaoke.
	func karaokeHandler(_ req: Request) async throws -> View {
		struct AdminKaraokeContext: Encodable {
			var trunk: TrunkContext

			init(_ req: Request) throws {
				trunk = .init(req, title: "Karaoke Admin", tab: .admin)
			}
		}
		let ctx = try AdminKaraokeContext(req)
		return try await req.view.render("admin/karaoke", ctx)
	}

	// POST /admin/karaoke/reload
	//
	// Kicks off a reload operation. Admin only; the data file must be uploaded to /seeds,
	// probably via git push.
	func karaokePostHandler(_ req: Request) async throws -> HTTPStatus {
		try await apiQuery(req, endpoint: "/karaoke/reload", method: .POST)
		return .ok
	}

	// GET /admin/boardgames
	//
	// Shows administrator settings for board games.
	func boardGamesHandler(_ req: Request) async throws -> View {
		struct AdminBoardGamesContext: Encodable {
			var trunk: TrunkContext

			init(_ req: Request) throws {
				trunk = .init(req, title: "Board Games Admin", tab: .admin)
			}
		}
		let ctx = try AdminBoardGamesContext(req)
		return try await req.view.render("admin/boardgames", ctx)
	}

	// POST /admin/boardgames/reload
	//
	// Kicks off a reload operation. Admin only; the data file must be uploaded to /seeds,
	// probably via git push.
	func boardGamesPostHandler(_ req: Request) async throws -> HTTPStatus {
		try await apiQuery(req, endpoint: "/boardgames/reload", method: .POST)
		return .ok
	}

	func huntHandler(_ req: Request) async throws -> View {
		struct AdminHuntsContext: Encodable {
			var trunk: TrunkContext
			var hunts: HuntListData

			init(_ req: Request, _ hunts: HuntListData) throws {
				trunk = .init(req, title: "Hunts Admin", tab: .admin)
				self.hunts = hunts
			}
		}
		let response = try await apiQuery(req, endpoint: "/hunts")
		let ctx = try AdminHuntsContext(req, try response.content.decode(HuntListData.self))
		return try await req.view.render("admin/hunts", ctx)
	}

	func huntPostHandler(_ req: Request) async throws -> HTTPStatus {
		struct HuntPostContent: Codable {
			let huntJson: String
		}
		let postStruct = try req.content.decode(HuntPostContent.self)
		guard let jsonData = postStruct.huntJson.data(using: .utf8) else {
			return .badRequest
		}
		try await apiQuery(req, endpoint: "/hunts/create", method: .POST, encodeContent: try JSONDecoder.custom(dates: .iso8601).decode(HuntCreateData.self, from: jsonData))
		return .ok
	}

    func huntEditHandler(_ req: Request) async throws -> View {
		struct HintContext: Encodable {
			var key: String
			var value: String
			init(_ element: [String:String].Element) {
				key = element.key
				value = element.value
			}
		}
		struct PuzzleContext: Encodable {
			var id: UUID
			var title: String
			var body: String
			var answer: String
			var unlockTime: Date?
			var hints: [HintContext]
			init(_ puzzle: HuntPuzzleData) throws {
				id = puzzle.puzzleID
				title = puzzle.title
				body = puzzle.body
				guard let answer = puzzle.answer else {
					throw "answer must be set for admin"
				}
				self.answer = answer
				unlockTime = puzzle.unlockTime
				hints = puzzle.hints?.sorted(by: <).map({HintContext($0)}) ?? []
			}
		}
        struct SingleHuntPageContext: Encodable {
            var trunk: TrunkContext
			var id: UUID
			var title: String
			var description: String
			var puzzles: [PuzzleContext]
            init(_ req: Request, _ hunt: HuntData) throws {
                trunk = .init(req, title: "\(hunt.title) | Hunt Admin", tab: .admin)
				id = hunt.huntID
				title = hunt.title
				description = hunt.description
				puzzles = try hunt.puzzles.map({try PuzzleContext($0)})
            }
        }
		guard let huntID = req.parameters.get(huntIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid hunt ID"
		}
        let response = try await apiQuery(req, endpoint: "/hunts/\(huntID)/admin")
        let ctx = try SingleHuntPageContext(req, try response.content.decode(HuntData.self))
        return try await req.view.render("admin/huntEdit", ctx)
    }

	func huntEditPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let huntID = req.parameters.get(huntIDParam.paramString)?.percentEncodeFilePathEntry() else {
			return .badRequest
		}
		let postStruct = try req.content.decode(HuntPatchData.self)
        let response = try await apiQuery(req, endpoint: "/hunts/\(huntID)", method: .PATCH, encodeContent: postStruct)
		return response.status
	}

	func puzzleEditPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let puzzleID = req.parameters.get(puzzleIDParam.paramString)?.percentEncodeFilePathEntry() else {
			return .badRequest
		}
		// Needs to be slightly different from HuntPuzzlePatchData because we need to feed unlockTime through
		// dateFromW3DatetimeString.
		struct PuzzleEditPostData: Content {
			var title: String?
			var body: String?
			var answer: String?
			var unlockTime: String?
			var hintName: String?
			var hintValue: String?
		}
		let postStruct = try req.content.decode(PuzzleEditPostData.self)
		var patchStruct = HuntPuzzlePatchData(title: postStruct.title, body: postStruct.body, answer: postStruct.answer, unlockTime: .absent)
		if let unlockTime = postStruct.unlockTime {
			if unlockTime == "" {
				patchStruct.unlockTime = .null
			} else {
				guard let unlockDate = dateFromW3DatetimeString(unlockTime) else {
					return .badRequest
				}
				patchStruct.unlockTime = .present(unlockDate)
			}
		} else {
			patchStruct.unlockTime = .absent
		}
		if let hintName = postStruct.hintName, let hintValue = postStruct.hintValue {
			patchStruct.hints = [hintName: hintValue]
		}
        let response = try await apiQuery(req, endpoint: "/hunts/puzzles/\(puzzleID)", method: .PATCH, encodeContent: patchStruct)
		return response.status
	}

	func huntDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let huntID = req.parameters.get(huntIDParam.paramString)?.percentEncodeFilePathEntry() else {
			return .badRequest
		}
		try await apiQuery(req, endpoint: "/hunts/\(huntID)", method: .DELETE)
		return .ok
	}

// MARK: - Schedule
	// GET /admin/schedule
	//
	// Shows a form with a file upload button for upload a new schedule.ics file. This the start of a flow, going from
	// scheduleupload to scheduleverify to scheduleapply.
	func scheduleManagerViewHandler(_ req: Request) async throws -> View {
		struct ScheduleUploadViewContext: Encodable {
			var trunk: TrunkContext
			var updateLog: [EventUpdateLogData]

			init(_ req: Request, logEntries: [EventUpdateLogData]) throws {
				trunk = .init(req, title: "Upload Schedule", tab: .admin)
				updateLog = logEntries
			}
		}
		let response = try await apiQuery(req, endpoint: "/admin/schedule/viewlog")
		let logEntries = try response.content.decode([EventUpdateLogData].self)
		let ctx = try ScheduleUploadViewContext(req, logEntries: logEntries)
		return try await req.view.render("admin/scheduleUpload", ctx)
	}

	// GET /admin/schedulelogview/:log_id
	//
	// Displays a page showing the schedule changes
	func scheduleLogEntryViewer(_ req: Request) async throws -> View {
		guard let logIDString = req.parameters.get(scheduleLogIDParam.paramString, as: String.self), let logID = Int(logIDString) else {
			throw Abort(.badRequest, reason: "Could not parse log ID from request URL.")
		}
		let response = try await apiQuery(req, endpoint: "/admin/schedule/viewlog/\(logID)")
		let differenceData = try response.content.decode(EventUpdateDifferenceData.self)

		struct ScheduleUpdateVerifyViewContext: Encodable {
			var trunk: TrunkContext
			var diff: EventUpdateDifferenceData

			init(_ req: Request, differenceData: EventUpdateDifferenceData) throws {
				trunk = .init(req, title: "Verify Schedule Changes", tab: .admin)
				self.diff = differenceData
			}
		}
		let ctx = try ScheduleUpdateVerifyViewContext(req, differenceData: differenceData)
		return try await req.view.render("admin/scheduleLogView", ctx)
	}

	// POST /admin/scheduleupload
	//
	// Handles the POST of an uploaded schedule file. Reads the file in and saves it in "<workingDir>/admin/uploadschedule.ics".
	// Does not immediately parse the file or apply it to the DB. See scheduleVerifyViewHandler().
	func scheduleUploadPostHandler(_ req: Request) async throws -> HTTPStatus {
		struct ScheduleUploadData: Content {
			/// The schedule in `String` format.
			var schedule: String
		}
		let uploadData = try req.content.decode(ScheduleUploadData.self)
		let apiPostData = EventsUpdateData(schedule: uploadData.schedule)
		try await apiQuery(req, endpoint: "/admin/schedule/update", method: .POST, encodeContent: apiPostData)
		return .ok
	}

	// GET /admin/scheduleverify
	//
	// Displays a page showing the schedule changes that will happen when the (saved) uploaded schedule is applied.
	// We diff the existing schedule with the new update, and display the adds, deletes, and modified events for review.
	// This page also has a form where the user can approve the changes to apply them to the db.
	func scheduleVerifyViewHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/admin/schedule/verify")
		let differenceData = try response.content.decode(EventUpdateDifferenceData.self)

		struct ScheduleUpdateVerifyViewContext: Encodable {
			var trunk: TrunkContext
			var diff: EventUpdateDifferenceData

			init(_ req: Request, differenceData: EventUpdateDifferenceData) throws {
				trunk = .init(req, title: "Verify Schedule Changes", tab: .admin)
				self.diff = differenceData
			}
		}
		let ctx = try ScheduleUpdateVerifyViewContext(req, differenceData: differenceData)
		return try await req.view.render("admin/scheduleVerify", ctx)
	}

	func scheduleReloadHandler(_ req: Request) async throws -> HTTPStatus {
		let _ = try await apiQuery(req, endpoint: "/admin/schedule/reload", method: .POST)
		return .ok
	}

	func notificationConsistencyCheckHandler(_ req: Request) async throws -> HTTPStatus {
		let _ = try await apiQuery(req, endpoint: "/admin/notifications/reload", method: .POST)
		return .ok
	}

	// POST /admin/scheduleverify
	//
	// Handles the POST from the schedule verify page form. Schedule Verify shows the admin the changes that will be applied
	// before they happen. Accepting the changes POSTs to here. There are 2 options on the form as well:
	// - Add Posts in Forum Thread. This option, if selected, will create a post in the Event Forum thread of each affected
	//	 event, (except maybe creates?) explaining the change that occurred.
	// - Ignore Deleted Events. This option causes deletes to not be applied. In a case where you need to update a single event's
	// 	 time or location, you could make a .ics that only contains that event and upload/apply that file. Without this
	// 	 option, that one event would be considered an exhaustive list of events for the week, and all other events would be deleted.
	func scheduleVerifyPostHandler(_ req: Request) async throws -> HTTPStatus {
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
		try await apiQuery(
			req,
			endpoint: "/admin/schedule/update/apply?\(components.percentEncodedQuery ?? "")",
			method: .POST
		)
		return .ok
	}

	// GET /admin/scheduleupload/complete
	//
	func scheduleUpdateCompleteViewtHandler(_ req: Request) async throws -> View {
		struct ScheduleUpdateCompleteViewContext: Encodable {
			var trunk: TrunkContext

			init(_ req: Request) throws {
				trunk = .init(req, title: "Schedule Update Complete", tab: .admin)
			}
		}
		let ctx = try ScheduleUpdateCompleteViewContext(req)
		return try await req.view.render("admin/scheduleUpdateComplete", ctx)
	}
	
// MARK: - Bulk User Import/Export
	// GET /admin/bulkuser
	//
	// Shows a form with a file upload button for upload a new schedule.ics file. This the start of a flow, going from
	// scheduleupload to scheduleverify to scheduleapply.
	func bulkUserRootViewHandler(_ req: Request) async throws -> View {
		struct BulkUserRootContext: Encodable {
			var trunk: TrunkContext

			init(_ req: Request) throws {
				trunk = .init(req, title: "Bulk User Import/Export", tab: .admin)
			}
		}
		let ctx = try BulkUserRootContext(req)
		return try await req.view.render("admin/bulkUser", ctx)
	}

	// GET /admin/bulkuser/download
	//
	// Initiates a download of the twitarr userfile, a zip archive containing info on all the registered users.
	func bulkUserFileDownload(_ req: Request) async throws -> Response {
		await req.storage.setWithAsyncShutdown(SiteErrorStorageKey.self, to: SiteErrorMiddlewareStorage(produceHTMLFormattedErrors: true))
		return try await apiQuery(req, endpoint: "/admin/bulkuserfile/download").encodeResponse(for: req)
	}

	// POST /admin/bulkuser/upload 
	//
	// Uploads a previously archived userfile. 
	func bulkUserfileUploadPostHandler(_ req: Request) async throws -> HTTPStatus {
		try await apiQuery(req, endpoint: "/admin/bulkuserfile/upload", method: .POST, beforeSend: { clientReq in
			clientReq.body = req.body.data
		})
		return .ok
	}
	
	// GET /admin/bulkuser/upload/verify
	//
	// Displays a page showing the schedule changes that will happen when the (saved) uploaded schedule is applied.
	// We diff the existing schedule with the new update, and display the adds, deletes, and modified events for review.
	// This page also has a form where the user can approve the changes to apply them to the db.
	func bulkUserVerifyViewHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/admin/bulkuserfile/verify")
		let verificationData = try response.content.decode(BulkUserUpdateVerificationData.self)

		struct UserfileUpdateVerifyViewContext: Encodable {
			var trunk: TrunkContext
			var diff: BulkUserUpdateVerificationData

			init(_ req: Request, verificationData: BulkUserUpdateVerificationData) throws {
				trunk = .init(req, title: "Verify Bulk User Import Changes", tab: .admin)
				self.diff = verificationData
			}
		}
		let ctx = try UserfileUpdateVerifyViewContext(req, verificationData: verificationData)
		return try await req.view.render("admin/bulkUserVerify", ctx)
	}
	
	// GET /admin/bulkuser/upload/commit
	//
	// Handles the POST from the schedule verify page form. Schedule Verify shows the admin the changes that will be applied
	// before they happen. Accepting the changes POSTs to here. There are 2 options on the form as well:
	// - Add Posts in Forum Thread. This option, if selected, will create a post in the Event Forum thread of each affected
	//	 event, (except maybe creates?) explaining the change that occurred.
	// - Ignore Deleted Events. This option causes deletes to not be applied. In a case where you need to update a single event's
	// 	 time or location, you could make a .ics that only contains that event and upload/apply that file. Without this
	// 	 option, that one event would be considered an exhaustive list of events for the week, and all other events would be deleted.
	func bulkUserUpdateCommitHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "admin/bulkuserfile/update/apply")
		let verificationData = try response.content.decode(BulkUserUpdateVerificationData.self)
		struct UserfileUpdateVerifyViewContext: Encodable {
			var trunk: TrunkContext
			var diff: BulkUserUpdateVerificationData

			init(_ req: Request, verificationData: BulkUserUpdateVerificationData) throws {
				trunk = .init(req, title: "Bulk User Import Applied", tab: .admin)
				self.diff = verificationData
			}
		}
		let ctx = try UserfileUpdateVerifyViewContext(req, verificationData: verificationData)
		return try await req.view.render("admin/bulkUserVerify", ctx)
	}


// MARK: - Reg Codes
	// GET /admin/regcodes
	//
	// Shows stats on reg code use. Lets admins search on a regcode and get the user it's associated with, if any.
	func getRegCodeHandler(_ req: Request) async throws -> View {
		var regCodeSearchResults = ""
		var searchResultHeaders = [UserHeader]()
		if let regCode = req.query[String.self, at: "search"]?.removingPercentEncoding?.lowercased()
			.filter({ $0 != " " })
		{
			regCodeSearchResults = "Invalid registration code"
			if regCode.count == 6, regCode.allSatisfy({ $0.isLetter || $0.isNumber }) {
				do {
					let response = try await apiQuery(req, endpoint: "/admin/regcodes/find/\(regCode)")
					searchResultHeaders = try response.content.decode([UserHeader].self)
					if searchResultHeaders.count > 0 {
						regCodeSearchResults =
							"User \"\(searchResultHeaders[0].username)\" is associated with registration code \"\(regCode)\""
					}
					else {
						regCodeSearchResults = "\(regCode) is a valid code, not associated with a user."
					}
				}
				catch let error as ErrorResponse {
					regCodeSearchResults = "Error: \(error.reason)"
				}
				catch {
					regCodeSearchResults = error.localizedDescription
				}
			}
		}
		let response = try await apiQuery(req, endpoint: "/admin/regcodes/stats")
		let regCodeData = try response.content.decode(RegistrationCodeStatsData.self)
		struct RegCodeStatsContext: Encodable {
			var trunk: TrunkContext
			var stats: RegistrationCodeStatsData
			var searchResults: String
			var searchResultUsers: [UserHeader]

			init(
				_ req: Request,
				stats: RegistrationCodeStatsData,
				searchResults: String,
				searchResultUsers: [UserHeader]
			) throws {
				trunk = .init(req, title: "Registration Codes", tab: .admin)
				self.stats = stats
				self.searchResults = searchResults
				self.searchResultUsers = searchResultUsers
			}
		}
		let ctx = try RegCodeStatsContext(
			req,
			stats: regCodeData,
			searchResults: regCodeSearchResults,
			searchResultUsers: searchResultHeaders
		)
		return try await req.view.render("admin/regcodes", ctx)
	}

	// GET /admin/regcodes/showuser/:user_id
	//
	// Shows stats on reg code use. Lets admins search on a regcode and get the user it's associated with, if any.
	func getRegCodeForUserHandler(_ req: Request) async throws -> View {
		guard let targetUserID = req.parameters.get(userIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Missing user_id parameter")
		}
		let response = try await apiQuery(req, endpoint: "/admin/regcodes/findbyuser/\(targetUserID)")
		let regCodeData = try response.content.decode(RegistrationCodeUserData.self)
		guard !regCodeData.users.isEmpty else {
			throw Abort(.internalServerError, reason: "No user found")
		}
		struct RegCodeUserContext: Encodable {
			var trunk: TrunkContext
			var data: RegistrationCodeUserData
			var primaryUser: UserHeader
			var altUsers: [UserHeader]
			var regCode: String

			init(_ req: Request, data: RegistrationCodeUserData) throws {
				trunk = .init(req, title: "Registration Code for User", tab: .admin)
				self.data = data
				self.primaryUser = data.users[0]
				self.altUsers = Array(data.users.dropFirst(1))
				self.regCode = data.regCode.isEmpty ? "No registration code found for this user" : data.regCode
			}
		}
		let ctx = try RegCodeUserContext(req, data: regCodeData)
		return try await req.view.render("admin/regCodeForUser", ctx)
	}
	
	// GET /admin/regcodes/discord/assign
	//
	// Shows the form allowing TT and above to assign a Registration Code to a user by tagging that code with a Discord Username.
	// The reg code chosen will be from the pool allocated for Discord use. This pool only exists on pre-production servers,
	// therefore this only works for pre-prod. 
	//
	// Intent here is to give TT a more structured way to hand out reg codes than looking up unused codes in the table directly
	// and telling whomever to use that code to create an account.
	func assignRegCodeToDiscordUser(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/admin/regcodes/stats")
		let regCodeData = try response.content.decode(RegistrationCodeStatsData.self)

		struct RegCodeContext: Encodable {
			var trunk: TrunkContext
			var regCodeStats: RegistrationCodeStatsData

			init(_ req: Request, stats: RegistrationCodeStatsData) throws {
				trunk = .init(req, title: "Assign Registration Code To Discord User", tab: .admin)
				regCodeStats = stats
			}
		}
		let ctx = try RegCodeContext(req, stats: regCodeData)
		return try await req.view.render("admin/assignRegCodeForm", ctx)
	}
	
	// POST /admin/regcodes/discord/assign
	//
	// Shows the result page for assigning a reg code to a Discord user. Has a proposed direct Discord message contining
	// the assigned code and instructions on how to use it.
	func assignRegCodeToDiscordUserResult(_ req: Request) async throws -> View {
		struct UsernameData: Content {
			var username: String
		}
		let discordUsername = try req.content.decode(UsernameData.self).username
		let response = try await apiQuery(req, endpoint: "/admin/regcodes/discord/allocate/\(discordUsername)")
		let regCodeData = try response.content.decode(RegistrationCodeUserData.self)
		struct RegCodeContext: Encodable {
			var trunk: TrunkContext
			var data: RegistrationCodeUserData

			init(_ req: Request, data: RegistrationCodeUserData) throws {
				trunk = .init(req, title: "Assign Registration Code To Discord User", tab: .admin)
				self.data = data
			}
		}
		let ctx = try RegCodeContext(req, data: regCodeData)
		return try await req.view.render("admin/regCodeAssigned", ctx)

	}

// MARK: - UserLevels and Roles
	// GET /admin/mods
	//
	// Only THO and above--mods cannot make more mods.
	func getModsHandler(_ req: Request) async throws -> View {
		var searchResults: [UserHeader]?
		var searchStr = ""
		if let str = req.query[String.self, at: "search"]?.percentEncodeFilePathEntry() {
			searchStr = str
			let searchResponse = try await apiQuery(req, endpoint: "/users/match/allnames/\(searchStr)")
			searchResults = try searchResponse.content.decode([UserHeader].self)
		}
		let response = try await apiQuery(req, endpoint: "/admin/moderators")
		let currentMembers = try response.content.decode([UserHeader].self)
		var ctx = try ManageUserLevelViewContext(
			req,
			current: currentMembers,
			searchStr: searchStr,
			searchResults: searchResults
		)
		ctx.levelName = "Moderator"
		ctx.targetLevel = "moderator"
		return try await req.view.render("admin/showModerators", ctx)
	}

	// GET /admin/twitarrteam
	//
	// Only THO and above may see this
	func getTwitarrTeamHandler(_ req: Request) async throws -> View {
		var searchResults: [UserHeader]?
		var searchStr = ""
		if let str = req.query[String.self, at: "search"]?.percentEncodeFilePathEntry() {
			searchStr = str
			let searchResponse = try await apiQuery(req, endpoint: "/users/match/allnames/\(searchStr)")
			searchResults = try searchResponse.content.decode([UserHeader].self)
		}
		let response = try await apiQuery(req, endpoint: "/admin/twitarrteam")
		let currentMembers = try response.content.decode([UserHeader].self)
		var ctx = try ManageUserLevelViewContext(
			req,
			current: currentMembers,
			searchStr: searchStr,
			searchResults: searchResults
		)
		ctx.levelName = "TwitarrTeam"
		ctx.targetLevel = "twitarrteam"
		return try await req.view.render("admin/showModerators", ctx)
	}

	// GET /admin/tho
	//
	// Only THO and above may see this
	func getTHOHandler(_ req: Request) async throws -> View {
		var searchResults: [UserHeader]?
		var searchStr = ""
		if let str = req.query[String.self, at: "search"]?.percentEncodeFilePathEntry() {
			searchStr = str
			let searchResponse = try await apiQuery(req, endpoint: "/users/match/allnames/\(searchStr)")
			searchResults = try searchResponse.content.decode([UserHeader].self)
		}
		let response = try await apiQuery(req, endpoint: "/admin/tho")
		let currentMembers = try response.content.decode([UserHeader].self)
		var ctx = try ManageUserLevelViewContext(
			req,
			current: currentMembers,
			searchStr: searchStr,
			searchResults: searchResults
		)
		ctx.levelName = "THO"
		ctx.targetLevel = "tho"
		return try await req.view.render("admin/showModerators", ctx)
	}

	// POST /admin/user/:user_id/moderator/promote
	// POST /admin/user/:user_id/twitarrteam/promote
	// POST /admin/user/:user_id/tho/promote
	//
	func promoteUserLevel(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid user ID"
		}
		var targetLevel = "moderator"
		if let pathCount = req.route?.path.count, pathCount == 5, let urlLevel = req.route?.path[3].paramString {
			if urlLevel == "twitarrteam" || urlLevel == "tho" {
				targetLevel = urlLevel
			}
		}
		let response = try await apiQuery(req, endpoint: "/admin/\(targetLevel)/promote/\(userID)", method: .POST)
		return response.status
	}

	// POST /admin/user/:user_id/verified/demote
	//
	func demoteToVerified(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid user ID"
		}
		let response = try await apiQuery(req, endpoint: "/admin/user/demote/\(userID)", method: .POST)
		return response.status
	}

	// GET /admin/userroles
	// GET /admin/userroles/:user_role
	//
	func getUserRoleManagementHandler(_ req: Request) async throws -> View {
		var searchResults: [UserHeader]?
		var searchStr = ""
		if let str = req.query[String.self, at: "search"]?.percentEncodeFilePathEntry() {
			searchStr = str
			let searchResponse = try await apiQuery(req, endpoint: "/users/match/allnames/\(searchStr)")
			searchResults = try searchResponse.content.decode([UserHeader].self)
		}
		var currentMgrs = [UserHeader]()
		let userRoleStr = req.parameters.get(userRoleParam.paramString)?.percentEncodeFilePathEntry()
		if let userRoleStr = userRoleStr {
			let response = try await apiQuery(req, endpoint: "/admin/userroles/\(userRoleStr)")
			currentMgrs = try response.content.decode([UserHeader].self)
		}
		struct KaraokeManagersViewContext: Encodable {
			var trunk: TrunkContext
			var currentMgrs: [UserHeader]
			var userSearch: String
			var searchResults: [UserHeader]?
			var role: String?  // State of the "Choose Role To Manage" dropdown
			var rolename: String  // User-visible name for selected role, or "".

			init(
				_ req: Request,
				currentMgrs: [UserHeader],
				searchStr: String,
				searchResults: [UserHeader]?,
				role: String?
			) throws {
				trunk = .init(req, title: "Karaoke Managers", tab: .admin)
				self.currentMgrs = currentMgrs
				self.userSearch = searchStr
				self.searchResults = searchResults
				self.role = role
				self.rolename = UserRoleType(fromString: role)?.label ?? "User Roles"
			}
		}
		let ctx = try KaraokeManagersViewContext(
			req,
			currentMgrs: currentMgrs,
			searchStr: searchStr,
			searchResults: searchResults,
			role: userRoleStr
		)
		return try await req.view.render("admin/showUserRoles", ctx)
	}

	// POST /admin/user/:user_id/addrole/:user_role
	//
	func addRoleToUser(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid user ID"
		}
		guard let userRole = req.parameters.get(userRoleParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid user role"
		}
		let response = try await apiQuery(
			req,
			endpoint: "/admin/userroles/\(userRole)/addrole/\(userID)",
			method: .POST
		)
		return response.status
	}

	// POST /admin/user/:user_id/removerole/:user_role
	//
	func removeRoleFromUser(_ req: Request) async throws -> HTTPStatus {
		guard let userID = req.parameters.get(userIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid user ID"
		}
		guard let userRole = req.parameters.get(userRoleParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid user role"
		}
		let response = try await apiQuery(
			req,
			endpoint: "/admin/userroles/\(userRole)/removerole/\(userID)",
			method: .POST
		)
		return response.status
	}
}
