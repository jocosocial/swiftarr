import FluentSQL
import Vapor

// Leaf data used by all views. Mostly this is stuff in the navbar.
struct TrunkContext: Encodable {
	var title: String
	var metaRedirectURL: String?

	// current nav item
	enum Tab: String, Codable {
		case twarrts
		case forums
		case seamail
		case events

		// Under the Twitarr title
		case home
		case lfg
		case games
		case karaoke
		case moderator
		case admin
		case time
		case map

		case none
	}
	var tab: Tab
	var inTwitarrSubmenu: Bool

	var userIsLoggedIn: Bool
	var userIsMod: Bool
	var userIsTwitarrTeam: Bool
	var userIsTHO: Bool
	var userRoles: [String]  // Use "contains(trunk.userRoles, "shutternautmanager")" or similar to check
	var minAccessLevel: String?  // Minimum access required to view Twitarr pages; Value from Settings.
	var preregistrationMode: Bool  // Mirrors the value in Settings.
	var preregistrationApplies: Bool  // TRUE if the current user is subject to Pre-Reg restrictions.
	var pageIsForDisabledFeature: SwiftarrFeature?  // Middleware marked this request disabled for normal users but we're showing it to THO/admin

	var username: String
	var userID: UUID

	var alertCounts: UserNotificationData
	var eventStartingSoon: Bool
	var newTweetAlertwords: Bool
	var newForumAlertwords: Bool

	init(_ req: Request, title: String, tab: Tab) {
		var userAccessLevel: UserAccessLevel = .banned  // Not logged in is equivalent to can't log in, for our purposes here
		if let user = req.auth.get(UserCacheData.self) {
			userAccessLevel = UserAccessLevel(rawValue: req.session.data["accessLevel"] ?? "banned") ?? .banned
			userIsLoggedIn = true
			userIsMod = userAccessLevel.hasAccess(.moderator)
			userIsTwitarrTeam = userAccessLevel.hasAccess(.twitarrteam)
			userIsTHO = userAccessLevel.hasAccess(.tho)
			username = user.username
			userID = user.userID
			userRoles = user.userRoles.map { $0.rawValue }
		}
		else {
			userIsLoggedIn = false
			userIsMod = false
			userIsTwitarrTeam = false
			userIsTHO = false
			username = ""
			userID = UUID()
			userRoles = []
		}
		let minAccess = Settings.shared.minAccessLevel
		minAccessLevel = minAccess == .banned || Settings.shared.enablePreregistration ? nil : minAccess.visibleName()
		preregistrationMode = Settings.shared.enablePreregistration
		preregistrationApplies = Settings.shared.enablePreregistration && userAccessLevel < minAccess
		pageIsForDisabledFeature = req.storage.get(FeatureDisableOverrideStorageKey.self)
		eventStartingSoon = false
		if req.route != nil, let alertsStr = req.session.data["alertCounts"],
			let alertData = alertsStr.data(using: .utf8)
		{
			let alerts = try? JSONDecoder().decode(UserNotificationData.self, from: alertData)
			alertCounts = alerts ?? UserNotificationData()

			// If we have a nextEventTime, and that event starts within the configured notification time bounds,
			// mark that we have an event starting soon.
			if let nextEventInterval = alerts?.nextFollowedEventTime?
				.timeIntervalSince(Settings.shared.getDateInCruiseWeek()),
				(Settings.shared.upcomingEventPastSeconds...Settings.shared.upcomingEventNotificationSeconds)
					.contains(nextEventInterval)
			{
				eventStartingSoon = true
			}
			// We don't do the same thing with LFG since that'd be confusing with the chat notifications.
		}
		else {
			alertCounts = UserNotificationData()
		}

		self.title = title
		self.tab = tab
		self.inTwitarrSubmenu = [.home, .lfg, .games, .karaoke, .moderator, .admin].contains(tab)

		newTweetAlertwords = alertCounts.alertWords.contains { $0.newTwarrtMentionCount > 0 }
		newForumAlertwords = alertCounts.alertWords.contains { $0.newForumMentionCount > 0 }
	}
}

/// Context required for a paginator control. A page may include "paginator.leaf" multiple times to place multiples of the same paginator, but
/// the context is set up to only allow one paginator per page, at a path of "/paginator" from the context root. I could enforce this with a protocol, but ... meh.
struct PaginatorContext: Codable {
	struct PageInfo: Codable {
		var index: Int
		var active: Bool
		var link: String
	}

	var prevPageURL: String?
	var nextPageURL: String?
	var lastPageURL: String?
	var pageURLs: [PageInfo]

	/// Works with "paginator.leaf". Builds a paginator control allowing navigation to different pages in a N-page array.
	///
	/// Parameters:
	/// - start: A 0-based index indicating the first piece of content to show. This is generally the topmost item displayed on the current page.
	/// - total: The total number of items in the list. The paginator will break this up into N pages. The UI may not create a button for every page.
	/// - limit: The maximum number of items to show per page. If the 'item' size is a page, set this to 1.
	/// - urlForPage: A closure that takes a page index and returns a relative URL that will load that page.
	init(start: Int, total: Int, limit: Int, urlForPage: (Int) -> String) {
		pageURLs = []
		let localLimit = max(limit, 1)
		let currentPage = (start + localLimit - 1) / localLimit
		let totalPages = (start + localLimit - 1) / localLimit + (total - start + localLimit - 1) / localLimit

		var minPage = max(currentPage - 3, 0)
		var maxPage = min(minPage + 6, totalPages - 1)
		minPage = max(maxPage - 6, 0)
		maxPage = max(maxPage, 0)

		for pageIndex in minPage...maxPage {
			pageURLs.append(
				PageInfo(index: pageIndex + 1, active: pageIndex == currentPage, link: urlForPage(pageIndex))
			)
		}
		if currentPage > 0 {
			prevPageURL = urlForPage(currentPage - 1)
		}
		if currentPage < totalPages - 1 {
			nextPageURL = urlForPage(currentPage + 1)
		}
		if maxPage < totalPages - 1 {
			lastPageURL = urlForPage(totalPages - 1)
		}
	}

	init(_ paginator: Paginator, urlForPage: (Int) -> String) {
		self.init(start: paginator.start, total: paginator.total, limit: paginator.limit, urlForPage: urlForPage)
	}
}

// Leaf data used by the messagePostForm.
struct MessagePostContext: Encodable {
	var forumTitle: String = ""
	var forumTitlePlaceholder: String = "Forum Title"
	var messageText: String = ""
	var messageTextPlaceholder: String = "Post Text"
	var photoFilenames: [String] = ["", "", "", ""]  // Must have 4 values to make Leaf templating work. Use "" as placeholder.
	var allowedImageTypes: String
	var displayUntil: String = ""  // Used by announcements.
	var postErrorString: String = ""  // Prepopulates the error alert. Useful for partial successes.

	var formAction: String
	var postSuccessURL: String
	var authorName: String?  // Nil if current user is also author. Non-nil therefore implies mod edit.
	var showForumTitle: Bool = false
	var onlyShowForumTitle: Bool = false
	var showModPostOptions: Bool = false
	var showCruiseDaySelector: Bool = false
	var isEdit: Bool = false

	// Used as an parameter to the initializer
	enum InitType {
		case tweet
		case tweetReply(Int)  // replyGroup ID, or TwarrtID
		case tweetEdit(TwarrtDetailData)
		case forum(String)  // Category ID
		case forumEdit(ForumData)
		case forumPost(String)  // Forum ID
		case forumPostEdit(PostDetailData)
		case seamail
		case seamailPost(FezData)
		case fezPost(FezData)
		case announcement
		case announcementEdit(AnnouncementData)
		case theme
		case themeEdit(DailyThemeData)
	}

	init(forType: InitType) {
		allowedImageTypes = Settings.shared.validImageInputTypes.joined(separator: ", ")
		switch forType {
		// For creating a new tweet
		case .tweet:
			formAction = "/tweets/create"
			postSuccessURL = "/tweets"
			showModPostOptions = true
		// For replying to a tweet
		case .tweetReply(let replyGroup):
			formAction = "/tweets/reply/\(replyGroup)"
			postSuccessURL = "/tweets?replyGroup=\(replyGroup)"
			showModPostOptions = true
		// For editing a tweet
		case .tweetEdit(let tweet):
			messageText = tweet.text
			photoFilenames = tweet.images ?? []
			while photoFilenames.count < 4 {
				photoFilenames.append("")
			}
			formAction = "/tweets/edit/\(tweet.postID)"
			postSuccessURL = "/tweets"
			isEdit = true
		// For creating a new forum in a category
		case .forum(let catID):
			formAction = "/forums/\(catID)/createForum"
			postSuccessURL = "/forums/\(catID)"
			showForumTitle = true
			showModPostOptions = true
		// For editing a forum title
		case .forumEdit(let forum):
			forumTitle = forum.title
			formAction = "/forum/\(forum.forumID)/edit"
			postSuccessURL = "/forum/\(forum.forumID)"
			showForumTitle = true
			onlyShowForumTitle = true
			isEdit = true
		// For creating a new post in a forum
		case .forumPost(let forumID):
			formAction = "/forum/\(forumID)/create"
			postSuccessURL = "/forum/\(forumID)"
			showModPostOptions = true
		// For editing a post in a forum
		case .forumPostEdit(let withForumPost):
			messageText = withForumPost.text
			photoFilenames = withForumPost.images ?? []
			while photoFilenames.count < 4 {
				photoFilenames.append("")
			}
			formAction = "/forumpost/edit/\(withForumPost.postID)"
			postSuccessURL = "/forum/\(withForumPost.forumID)"
			isEdit = true
		// For creating a new Seamail thread
		case .seamail:
			formAction = "/seamail/create"
			postSuccessURL = "/seamail"
			photoFilenames = []
		// For posting in an existing Seamail thread
		case .seamailPost(let forSeamail):
			formAction = "/seamail/\(forSeamail.fezID)/post"
			postSuccessURL = "/seamail/\(forSeamail.fezID)#afterposts"
			photoFilenames = []
		// For posting in an existing Fez thread
		case .fezPost(let forFez):
			formAction = "/lfg/\(forFez.fezID)/post"
			postSuccessURL = "/lfg/\(forFez.fezID)"
			messageTextPlaceholder = "Send a message"
			photoFilenames = [""]
		// For creating an announcement
		case .announcement:
			formAction = "/admin/announcement/create"
			postSuccessURL = "/admin/announcements"
		// For editing an announcement
		case .announcementEdit(let announcementData):
			messageText = announcementData.text
			// @TODO this is a hack to get around us storing displayUntil as a String.
			// I don't have the energy to re-work all uses of it to be a proper Double/Date
			// with the new leafs that can render the appropriate local time string.
			displayUntil = String(announcementData.displayUntil.timeIntervalSince1970)
			formAction = "/admin/announcement/\(announcementData.id)/edit"
			postSuccessURL = "/admin/announcements"
			isEdit = true
		// For creating a daily theme
		case .theme:
			formAction = "/admin/dailytheme/create"
			postSuccessURL = "/admin/dailythemes"
			photoFilenames = [""]
			showForumTitle = true
			showCruiseDaySelector = true
			forumTitlePlaceholder = "Daily Theme Title"
			messageTextPlaceholder = "Info about Daily Theme"
		// For editing a daily theme
		case .themeEdit(let theme):
			formAction = "/admin/dailytheme/\(theme.themeID)/edit"
			postSuccessURL = "/admin/dailythemes"
			forumTitle = theme.title
			messageText = theme.info
			photoFilenames = theme.image != nil ? [theme.image!] : [""]
			displayUntil = String(theme.cruiseDay)
			showForumTitle = true
			showCruiseDaySelector = true
			forumTitlePlaceholder = "Daily Theme Title"
			messageTextPlaceholder = "Info about Daily Theme"
		}
	}
}

// POST data structure returned by the form in messagePostForm.leaf
// This form and data structure are used for creating and editing twarrts, forum posts, and fez messages.
struct MessagePostFormContent: Codable {
	let forumTitle: String?  // Only used when creating new forums
	let postText: String?
	let localPhoto1: Data?
	let serverPhoto1: String?
	let localPhoto2: Data?
	let serverPhoto2: String?
	let localPhoto3: Data?
	let serverPhoto3: String?
	let localPhoto4: Data?
	let serverPhoto4: String?
	let displayUntil: String?  // Used for announcements
	let cruiseDay: Int32?  // Used for Daily Themes
	let postAsTwitarrTeam: String?
	let postAsModerator: String?
}

extension MessagePostFormContent {
	// Builds a PostContentData from the form's contents. Doesn't validate, as we expect the PostContentData
	// to be sent to an API route which will do that.
	// I usually prefer struct conversion functions being set up as initialization of the dest type, but am
	// making an exception here.
	func buildPostContentData() -> PostContentData {
		let images: [ImageUploadData] = [
			ImageUploadData(serverPhoto1, localPhoto1),
			ImageUploadData(serverPhoto2, localPhoto2),
			ImageUploadData(serverPhoto3, localPhoto3),
			ImageUploadData(serverPhoto4, localPhoto4),
		]
		.compactMap { $0 }
		let postContent = PostContentData(
			text: postText ?? "",
			images: images,
			postAsModerator: postAsModerator != nil,
			postAsTwitarrTeam: postAsTwitarrTeam != nil
		)
		return postContent
	}
}

struct ReportPageContext: Encodable {
	var trunk: TrunkContext
	var reportTitle: String
	var reportFormAction: String
	var reportSuccessURL: String

	// For reporting a twarrt
	init(_ req: Request, twarrtID: String) throws {
		trunk = .init(req, title: "Report Twarrt", tab: .twarrts)
		reportTitle = "Report a Twarrt"
		reportFormAction = "/tweets/report/\(twarrtID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/tweets"
	}

	// For reporting a forum post
	init(_ req: Request, postID: String) throws {
		trunk = .init(req, title: "Report Forum Post", tab: .forums)
		reportTitle = "Report a Forum Post"
		reportFormAction = "/forumpost/report/\(postID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/forums"
	}

	// For reporting a forum title
	init(_ req: Request, forumID: String) throws {
		trunk = .init(req, title: "Report Forum Title", tab: .forums)
		reportTitle = "Report a Forum Title"
		reportFormAction = "/forum/report/\(forumID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/forums"
	}

	// For reporting a fez (The fez itself: title, info, location)
	init(_ req: Request, fezID: String, type: FezType) throws {
		trunk = .init(req, title: "Report \(type.lfgLabel) Content", tab: .lfg)
		reportTitle = "Report \(type.lfgLabel) Content"
		reportFormAction = "/lfg/report/\(fezID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/lfg"
	}

	// For reporting a fez post
	init(_ req: Request, fezPostID: String) throws {
		trunk = .init(req, title: "Report LFG Post", tab: .lfg)
		reportTitle = "Report LFG Post"
		reportFormAction = "/lfg/post/report/\(fezPostID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/lfg"
	}

	// For reporting a user profile
	init(_ req: Request, userID: String) throws {
		trunk = .init(req, title: "Report User Profile", tab: .none)
		reportTitle = "Report a User's Profile"
		reportFormAction = "/profile/report/\(userID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/user/\(userID)"
	}

	// For reporting a photostream photo
	init(_ req: Request, photostreamID: Int) throws {
		trunk = .init(req, title: "Report Photostream Photo", tab: .none)
		reportTitle = "Report a Photostream Photo"
		reportFormAction = "/photostream/report/\(photostreamID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/photostream)"
	}
}

/// Route gorup that only manages one route: the root route "/".
struct SiteController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app)
		openRoutes.get(use: rootPageHandler).destination("the Today page")
		openRoutes.get("about", use: aboutTwitarrViewHandler).destination("the About page")
		openRoutes.get("time", use: timePageHandler).destination("the server Time page")
		openRoutes.get("map", use: mapPageHandler).destination("the boat map")
	}

	/// GET /
	///
	/// Root page. This has a surprising number of queries. Because this page now has all the menu links, it's important the page not fail if sub-calls fail.
	func rootPageHandler(_ req: Request) async throws -> View {
		async let announcementResponse = try apiQuery(req, endpoint: "/notification/announcements")
		async let themeResponse = try apiQuery(req, endpoint: "/notification/dailythemes")
		async let photostreamResponse = try apiQuery(req, endpoint: "/photostream")
		let announcements = (try? await announcementResponse.content.decode([AnnouncementData].self)) ?? []
		let themes = (try? await themeResponse.content.decode([DailyThemeData].self)) ?? []

		var photostream: PhotostreamListData?
		var photostreamError: ErrorResponse?
		do {
			photostream = try await photostreamResponse.content.decode(PhotostreamListData.self)
		}
		catch {
			photostreamError = error as? ErrorResponse
		}

		let cal = Settings.shared.getPortCalendar()
		let components = cal.dateComponents(
			[.day],
			from: cal.startOfDay(for: Settings.shared.cruiseStartDate()),
			to: cal.startOfDay(for: Date())
		)
		let cruiseDay = Int32(components.day ?? 0)
		var backupTheme: DailyThemeData
		if cruiseDay < 0 {
			backupTheme = DailyThemeData(
				themeID: UUID(),
				title: "\(0 - cruiseDay) Days before Boat",
				info: "Soon™",
				image: nil,
				cruiseDay: cruiseDay
			)
		}
		else if cruiseDay < Settings.shared.cruiseLengthInDays {
			backupTheme = DailyThemeData(
				themeID: UUID(),
				title: "Cruise Day \(cruiseDay + 1): No Theme Day",
				info:
					"A wise man once said, \"A day without a theme is like a guitar ever-so-slightly out of tune. "
					+ "You can play it however you want, and it will be great, but someone out there will know "
					+ "that if only there was a theme, everything would be in tune.\"",
				image: nil,
				cruiseDay: cruiseDay
			)
		}
		else {
			backupTheme = DailyThemeData(
				themeID: UUID(),
				title: "\(cruiseDay + 1 - Int32(Settings.shared.cruiseLengthInDays)) Days after Boat",
				info: "JoCo Cruise has ended. Hope you're enjoying being back in the real world.",
				image: nil,
				cruiseDay: cruiseDay
			)
		}
		let dailyTheme: DailyThemeData = themes.first { $0.cruiseDay == cruiseDay } ?? backupTheme
		struct HomePageContext: Encodable {
			var trunk: TrunkContext
			var dailyTheme: DailyThemeData?
			var announcements: [AnnouncementData]
			var twoGroup: [[PhotostreamImageData]]
			var threeGroup: [[PhotostreamImageData]]
			var photostreamError: String?
			var showPhotostream: Bool

			init(
				_ req: Request,
				theme: DailyThemeData,
				announcements: [AnnouncementData],
				photostream: PhotostreamListData?,
				photostreamError: ErrorResponse?
			) throws {
				trunk = .init(req, title: "Twitarr", tab: .home)
				self.announcements = announcements
				self.dailyTheme = theme
				twoGroup = []
				threeGroup = []
				if let photos = photostream?.photos {
					for index in stride(from: 0, to: photos.count, by: 2) {
						var newArray = [PhotostreamImageData]()
						newArray.append(photos[index])
						if index + 1 < photos.count {
							newArray.append(photos[index + 1])
						}
						twoGroup.append(newArray)
					}
					for index in stride(from: 0, to: photos.count, by: 3) {
						var newArray = [PhotostreamImageData]()
						newArray.append(photos[index])
						if index + 1 < photos.count {
							newArray.append(photos[index + 1])
						}
						if index + 2 < photos.count {
							newArray.append(photos[index + 2])
						}
						threeGroup.append(newArray)
					}
				}
				self.photostreamError = photostreamError?.reason ?? "No Photostream Photos yet."
				let features = Settings.shared.disabledFeatures.value
				showPhotostream =
					!((features[.all] ?? Set()).union(features[.swiftarr] ?? Set()).contains(.photostream))
			}
		}
		let ctx = try HomePageContext(
			req,
			theme: dailyTheme,
			announcements: announcements,
			photostream: photostream,
			photostreamError: photostreamError
		)
		return try await req.view.render("home", ctx)
	}

	/// GET /about
	///
	///
	func aboutTwitarrViewHandler(_ req: Request) async throws -> View {
		var urlComponents = Settings.shared.apiUrlComponents
		urlComponents.path = "/public/twitarrhelptext.md"
		guard let apiURLString = urlComponents.string else {
			throw Abort(.internalServerError, reason: "Unable to build URL to API endpoint.")
		}
		let response = try await req.client.send(.GET, to: URI(string: apiURLString))
		let decoder = PlaintextDecoder()
		let document = try response.content.decode(String.self, using: decoder)
		struct AboutPageContext: Encodable {
			var trunk: TrunkContext
			var aboutContent: String

			init(_ req: Request, content: String) throws {
				trunk = .init(req, title: "About Twitarr", tab: .home)
				self.aboutContent = content
			}
		}
		let ctx = try AboutPageContext(req, content: document)
		return try await req.view.render("aboutTwitarr", ctx)
	}

	/// GET /time
	///
	/// Timezone information page.
	func timePageHandler(_ req: Request) async throws -> View {
		struct TimePageContext: Encodable {
			var trunk: TrunkContext
			var displayTime: String  // The time on the Boat's clocks, with the current TZ
			var serverTime: String  // The current time on the server box, including the box's timezone
			var portTime: String  // The time in the port we embarked from

			init(_ req: Request) throws {
				trunk = .init(req, title: "Time Zone Check", tab: .time)

				let dateFormatTemplate = "MMMM dd hh:mm a zzzz"
				// We split into two formatters to prevent accidental contamination of either.
				let serverDateFormatter = DateFormatter()
				serverDateFormatter.timeZone = TimeZone.current
				serverDateFormatter.setLocalizedDateFormatFromTemplate(dateFormatTemplate)

				let displayDateFormatter = DateFormatter()
				// This could use the GMToffset stuff but then it renders a different time zone
				// name leading to inconsistencies. For eaxmple, if the setting is "AST" then
				// this would render "GMT-04:00" which is the same thing in effect but more
				// confusing for people to read.
				displayDateFormatter.timeZone = Settings.shared.timeZoneChanges.tzAtTime()
				displayDateFormatter.setLocalizedDateFormatFromTemplate(dateFormatTemplate)

				let portDateFormatter = DateFormatter()
				portDateFormatter.timeZone = Settings.shared.portTimeZone
				portDateFormatter.setLocalizedDateFormatFromTemplate(dateFormatTemplate)
				// serverDate is a Date() that is a precise moment in time represented as an ISO8601 string in UTC.
				// There is no useful timezone information contained there (this date being UTC doesn't mean the server is set to UTC).
				let serverDate = ISO8601DateFormatter().date(from: trunk.alertCounts.serverTime) ?? Date()

				self.serverTime = serverDateFormatter.string(from: serverDate)
				self.displayTime = displayDateFormatter.string(from: serverDate)
				self.portTime = portDateFormatter.string(from: serverDate)
			}
		}

		let ctx = try TimePageContext(req)
		return try await req.view.render("time", ctx)
	}

	/// GET /map
	///
	/// Ship map
	func mapPageHandler(_ req: Request) async throws -> View {
		let deckNumber = req.query[String.self, at: "deck"]

		struct MapContext: Encodable {
			var trunk: TrunkContext
			var deckNumber: String?
			var decks = [Int](1...12)
			init(_ req: Request, deckNumber: String?) throws {
				trunk = .init(req, title: "Ship Map", tab: .map)
				self.deckNumber = deckNumber
			}
		}

		let ctx = try MapContext(req, deckNumber: deckNumber)
		return try await req.view.render("map", ctx)
	}
}

// MARK: - Utilities

protocol SiteControllerUtils {
	func registerRoutes(_ app: Application) throws
}

extension SiteControllerUtils {

	var categoryIDParam: PathComponent { PathComponent(":category_id") }
	var twarrtIDParam: PathComponent { PathComponent(":twarrt_id") }
	var forumIDParam: PathComponent { PathComponent(":forum_id") }
	var postIDParam: PathComponent { PathComponent(":post_id") }
	var fezIDParam: PathComponent { PathComponent(":fez_id") }
	var userIDParam: PathComponent { PathComponent(":user_id") }
	var eventIDParam: PathComponent { PathComponent(":event_id") }
	var reportIDParam: PathComponent { PathComponent(":report_id") }
	var modStateParam: PathComponent { PathComponent(":mod_state") }
	var announcementIDParam: PathComponent { PathComponent(":announcement_id") }
	var imageIDParam: PathComponent { PathComponent(":image_id") }
	var accessLevelParam: PathComponent { PathComponent(":access_level") }
	var alertWordParam: PathComponent { PathComponent(":alert_word") }
	var muteWordParam: PathComponent { PathComponent(":mute_word") }
	var boardgameIDParam: PathComponent { PathComponent(":boardgame_id") }
	var songIDParam: PathComponent { PathComponent(":karaoke_song_id") }
	var mkSongIDParam: PathComponent { PathComponent(":micro_karaoke_song_id") }
	var mkSnippetIDParam: PathComponent { PathComponent(":micro_karaoke_snippet_id") }
	var streamPhotoParam: PathComponent { PathComponent(":stream_photo_id") }
	var usernameParam: PathComponent { PathComponent(":user_name") }
	var scheduleLogIDParam: PathComponent { PathComponent(":schedule_log_id") }
	var performerIDParam: PathComponent { PathComponent(":performer_id") }
	var personalEventIDParam: PathComponent { PathComponent(":personal_event_id") }

	@discardableResult func apiQuery<EncodableContent: Encodable>(
		_ req: Request,
		endpoint: String,
		query: [URLQueryItem]? = nil,
		method: HTTPMethod = .GET,
		defaultHeaders: HTTPHeaders? = nil,
		passThroughQuery: Bool = true,
		encodeContent: EncodableContent,
		beforeSend: (inout ClientRequest) throws -> Void = { _ in }
	) async throws -> ClientResponse {
		let encodeBeforeSend: (inout ClientRequest) throws -> Void = { req in
			try req.content.encode(encodeContent, as: .json)
			try beforeSend(&req)
		}
		return try await apiQuery(
			req,
			endpoint: endpoint,
			query: query,
			method: method,
			defaultHeaders: defaultHeaders,
			passThroughQuery: passThroughQuery,
			beforeSend: encodeBeforeSend
		)
	}

	/// Call the Swiftarr API. This method pulls a user's token from their session data and adds it to the API call.
	/// By default it also forwards URL query parameters from the Site-level request to the API-level request.
	///
	/// We used to calculate the API URL from the request Host headers. But this proved untenable prior to boat 2022
	/// due to NATing, DNS, and multi-layer networking. It was decided to explicitly make this a setting instead.
	///
	@discardableResult func apiQuery(
		_ req: Request,
		endpoint: String,
		query: [URLQueryItem]? = nil,
		method: HTTPMethod = .GET,
		defaultHeaders: HTTPHeaders? = nil,
		passThroughQuery: Bool = true,
		beforeSend: (inout ClientRequest) throws -> Void = { _ in }
	) async throws -> ClientResponse {
		// Step 1: Make sure we add the Token Auth header to the API request. The user's auth token is saved in their
		// session data.
		var headers = defaultHeaders ?? HTTPHeaders()
		if let token = req.session.data["token"], !headers.contains(name: "Authorization") {
			headers.add(name: "Authorization", value: "Bearer \(token)")
			headers.add(name: "X-Swiftarr-User", value: req.session.data["userID"] ?? "UNKNOWN")
		}
		headers.add(name: "X-Swiftarr-Client", value: "swiftarr")

		// Step 2: Generate URLComponents, extract a 'clean' path, append the 'clean' path for the endpoint.
		var urlComponents = Settings.shared.apiUrlComponents
		guard let apiPathURL = URL(string: urlComponents.path),
			let endpointComponents = URLComponents(string: endpoint)
		else {
			throw Abort(.internalServerError, reason: "Unable to decode API URL components.")
		}
		urlComponents.path = apiPathURL.appendingPathComponent(endpointComponents.path).absoluteString

		// Step 3: Combine all sources of query items, producing an array of URLQueryItem
		var combinedQueryItems =
			(urlComponents.queryItems ?? []) + (endpointComponents.queryItems ?? []) + (query ?? [])
		if passThroughQuery, let requestQueryItems = URLComponents(string: req.url.string)?.queryItems {
			combinedQueryItems.append(contentsOf: requestQueryItems)
		}
		urlComponents.queryItems = combinedQueryItems.count > 0 ? combinedQueryItems : nil

		// Step 4: Build an URL string from the components, call the API with it.
		guard let apiURLString = urlComponents.string else {
			throw Abort(.internalServerError, reason: "Unable to build URL to API endpoint.")
		}
		let response = try await req.client.send(
			method,
			headers: headers,
			to: URI(string: apiURLString),
			beforeSend: beforeSend
		)
		guard response.status.code < 300 else {
			if let errorResponse = try? response.content.decode(ErrorResponse.self) {
				throw errorResponse
			}
			throw Abort(response.status)
		}
		return response
	}

	// Routes that the user does not need to be logged in to access.
	func getOpenRoutes(_ app: Application, feature: SwiftarrFeature? = nil, path: PathComponent...) -> RoutesBuilder {
		return app.grouped([
			app.sessions.middleware,
			SiteErrorMiddleware(environment: app.environment),
			UserCacheData.SessionAuth(),
			Token.authenticator(),  // For apps that want to sometimes open web pages
			NotificationsMiddleware(),
			SiteMinUserAccessLevelMiddleware(requireAuth: false),
		])
	}

	// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
	// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
	// redirect-chained through /login and back.
	func getGlobalRoutes(_ app: Application, feature: SwiftarrFeature? = nil, minAccess: UserAccessLevel = .banned,
			path: PathComponent...) -> RoutesBuilder {
		var builder = app.grouped(path).grouped([
				app.sessions.middleware,
				SiteErrorMiddleware(environment: app.environment),
				UserCacheData.SessionAuth(),
				Token.authenticator(),  // For apps that want to sometimes open web pages
				NotificationsMiddleware(),
//				UserCacheData.guardMiddleware(throwing: Abort(.unauthorized, reason: "User not authenticated.")),
				SiteMinUserAccessLevelMiddleware(requireAuth: true, requireAccessLevel: minAccess),
		])
		if let feature = feature {
			builder = builder.grouped(DisabledSiteSectionMiddleware(feature: feature))
		}
		return builder
	}

	// Routes for non-shareable content. If you're not logged in we failscreen. Most POST actions go here.
	//
	// Private site routes should not allow token auth. Token auth is for apps that want to open a webpage with their
	// token. They can initiate a web flow with a token, get a session back, and use that to complete the flow. However,
	// we don't want apps to be able to jump to private web pages.
	func getPrivateRoutes(_ app: Application, feature: SwiftarrFeature? = nil, minAccess: UserAccessLevel = .banned,
			path: PathComponent..., overrideMinUserAccessLevel: Bool = false) -> RoutesBuilder {
		var builder = app.grouped(path).grouped([
				app.sessions.middleware,
				SiteErrorMiddleware(environment: app.environment),
				UserCacheData.SessionAuth(),
			])
		if overrideMinUserAccessLevel {
			builder = builder.grouped(UserCacheData.guardMiddleware(throwing: Abort(.unauthorized, reason: "User not authenticated.")))
		}
		else {
			builder = builder.grouped(SiteMinUserAccessLevelMiddleware(requireAuth: true, requireAccessLevel: minAccess))
		}
		if let feature = feature {
			builder = builder.grouped(DisabledSiteSectionMiddleware(feature: feature))
		}
		return builder
	}

	// Convert a date string submitted by a client into a Date. Usually this comes from a form input field.
	// https://www.w3.org/TR/NOTE-datetime specifies a subset of what the ISO 8601 spec allows for date formats.
	//
	// Date objects that get stored in the db are stored in the ship's portTimeZone, and the API layer converts them
	// to the ship's current tz when retrieved. This fn returns Dates matching the indicated ISO8601 'floating' time
	// in the ship's port time zone for that reason.
	//
	// In Swift's libs, both DateFormatter and ISO8601DateFormatter require specific formatting options be set that match
	// the format of the input string--generally, they assume you know what a specific string is going to look like before
	// conversion. We don't know this, as the browser formats the string and there's a bunch of possibiliites.
	//
	// We could pre-parse the string and normalize it, but isn't it more fun to just complain about how Apple doesn't
	// include a general-purpose ISO 8601 string-to-date converter that accepts any valid ISO 8601 date string?
	// (at least with the 2019 version of the spec; IIRC previous versions had ambiguities preventing general-case parsing).
	func dateFromW3DatetimeString(_ dateStr: String) -> Date? {
		let dateFormatter = DateFormatter()
		dateFormatter.timeZone = Settings.shared.portTimeZone
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
		if let date = dateFormatter.date(from: dateStr) {
			return date
		}
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
		if let date = dateFormatter.date(from: dateStr) {
			return date
		}
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
		if let date = dateFormatter.date(from: dateStr) {
			return date
		}
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
		if let date = dateFormatter.date(from: dateStr) {
			return date
		}
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
		if let date = dateFormatter.date(from: dateStr) {
			return date
		}
		dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
		if let date = dateFormatter.date(from: dateStr) {
			return date
		}
		return nil
	}
}

extension String {

	// Utility to perform URL percent encoding on a string that is to be placed in an URL path. The string
	// is percent encoded for all non-url-path chars, plus "/", as the string must be a *single* path component.
	func percentEncodeFilePathEntry() -> String? {
		var pathEntryChars = CharacterSet.urlPathAllowed
		pathEntryChars.remove("/")
		return self.addingPercentEncoding(withAllowedCharacters: pathEntryChars)
	}

	// Utility to perform URL percent encoding on a string that is to be placed in an URL Query value. NOT a full
	// query string, the value in a '?key=value' clause.
	func percentEncodeQueryValue() -> String? {
		var allowedChars = CharacterSet.urlQueryAllowed
		allowedChars.remove(charactersIn: "/=?&")
		return self.addingPercentEncoding(withAllowedCharacters: allowedChars)
	}
}
