import Vapor
import Crypto
import FluentSQL

// Leaf data used by all views. Mostly this is stuff in the navbar.
struct TrunkContext: Encodable {
	var title: String
	var metaRedirectURL: String?
	
	// current nav item
	enum Tab: String, Codable {
		case twitarr
		case twarrts
		case forums
		case seamail
		case events
		case none
	}
	var tab: Tab
	
	var userIsLoggedIn: Bool
	var userIsMod: Bool
	var userIsTHO: Bool
	var username: String
	var userID: UUID
	
	var alertCounts: UserNotificationData
	var eventStartingSoon: Bool
	
	init(_ req: Request, title: String, tab: Tab) {
		if let user = req.auth.get(User.self) {
			userIsLoggedIn = true
			userIsMod = user.accessLevel.hasAccess(.moderator)
			userIsTHO = user.accessLevel.hasAccess(.tho)
			username = user.username
			userID = user.id!
		}
		else {
			userIsLoggedIn = false
			userIsMod = false
			userIsTHO = false
			username = ""
			userID = UUID()
		}
		eventStartingSoon = false
		if req.route != nil, let alertsStr = req.session.data["alertCounts"], let alertData = alertsStr.data(using: .utf8) {
			let alerts = try? JSONDecoder().decode(UserNotificationData.self, from: alertData)
			alertCounts = alerts ?? UserNotificationData()
			
			// If we have a nextEventTime, and that event starts between 15 mins in the past -> 30 mins in the future,
			// mark that we have an event starting soon
			if let nextEventInterval = alerts?.nextFollowedEventTime?.timeIntervalSinceNow
				//	((-15 * 60.0)...(30 * 60.0)).contains(nextEventInterval) 
					{
				eventStartingSoon = true	
			}
		}
		else {
			alertCounts = UserNotificationData()
		}
		
		self.title = title
		self.tab = tab
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
	/// - currentPage: A 0-based index indicating the 'active' page in the paginator control.
	/// - totalPages: The total number of pages the paginator 'controls'. The UI may not create a button for every page.
	/// - urlForPage: A closure that takes a page index and returns a relative URL that will load that page.
	init(currentPage: Int, totalPages: Int, urlForPage: (Int) -> String) {
		pageURLs = []
		var minPage = max(currentPage - 3, 0)
		var maxPage = min(minPage + 6, totalPages - 1)
		minPage = max(maxPage - 6, 0)
		maxPage = max(maxPage, 0)
		
		for pageIndex in minPage...maxPage {
			pageURLs.append(PageInfo(index: pageIndex + 1, active: pageIndex == currentPage, link: urlForPage(pageIndex)))
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
}

// Leaf data used by the messagePostForm.
struct MessagePostContext: Encodable {
	var forumTitle: String = ""
	var forumTitlePlaceholder: String = "Forum Title"
	var messageText: String = ""
	var messageTextPlaceholder: String = "Post Text"
	var photoFilenames: [String] = ["", "", "", ""]	// Must have 4 values to make Leaf templating work. Use "" as placeholder.
	var allowedImageTypes: String
	var displayUntil: String = ""					// Used by announcements.

	var formAction: String
	var postSuccessURL: String
	var authorName: String?							// Nil if current user is also author. Non-nil therefore implies mod edit.
	var showForumTitle: Bool = false
	var onlyShowForumTitle: Bool = false
	var showModPostOptions: Bool = false
	var showCruiseDaySelector: Bool = false
	var isEdit: Bool = false

	// Used as an parameter to the initializer	
	enum InitType {
		case tweet
		case tweetReply(Int)					// replyGroup ID, or TwarrtID
		case tweetEdit(TwarrtDetailData)
		case forum(String)						// Category ID
		case forumEdit(ForumData)
		case forumPost(String)					// Forum ID
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
		// For posting in an existing Seamail thread
		case .seamailPost(let forSeamail):
			formAction = "/seamail/\(forSeamail.fezID)/post"
			postSuccessURL = "/seamail/\(forSeamail.fezID)"
		// For posting in an existing Fez thread
		case .fezPost(let forFez):
			formAction = "/fez/\(forFez.fezID)/post"
			postSuccessURL = "/fez/\(forFez.fezID)"
		// For creating an announcement
		case .announcement:
			formAction = "/admin/announcement/create"
			postSuccessURL = "/admin/announcements"
		// For editing an announcement
		case .announcementEdit(let announcementData):
			messageText = announcementData.text
			let dateFormatter = DateFormatter()
			dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
			displayUntil = dateFormatter.string(from: announcementData.displayUntil)
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
struct MessagePostFormContent : Codable {
	let forumTitle: String?					// Only used when creating new forums
	let postText: String?
	let localPhoto1: Data?
	let serverPhoto1: String?
	let localPhoto2: Data?
	let serverPhoto2: String?
	let localPhoto3: Data?
	let serverPhoto3: String?
	let localPhoto4: Data?
	let serverPhoto4: String?
	let displayUntil: String? 				// Used for announcements
	let cruiseDay: Int32? 					// Used for Daily Themes
}

// Used to build an URL query string.
struct TwarrtQuery: Content {
	var search: String?
	var hashtag: String?
	var mentions: String?
	var byuser: String?
	var inbarrel: String?
	var after: String?
	var before: String?
	var afterdate: String?
	var beforedate: String?
	var from: String?
	var start: Int?
	var limit: Int?
	var replyGroup: Int?
	
	// TRUE if the 'next' tweets in this query are going to be newer or older than the current ones.
	// For instance, by default the 'anchor' is the most recent tweet and the direction is towards older tweets.
	func directionIsNewer() -> Bool {
		return (after != nil) || (afterdate != nil)  || (from == "first") || (replyGroup != nil)
	}
	
	func computedLimit() -> Int {
		return limit ?? 50
	}
	
	func buildQuery(baseURL: String, startOffset: Int) -> String? {
		
		guard var components = URLComponents(string: baseURL) else {
			return nil
		}
	
		var elements = [URLQueryItem]()
		if let search = search { elements.append(URLQueryItem(name: "search", value: search)) }
		if let hashtag = hashtag { elements.append(URLQueryItem(name: "hashtag", value: hashtag)) }
		if let mentions = mentions { elements.append(URLQueryItem(name: "mentions", value: mentions)) }
		if let byuser = byuser { elements.append(URLQueryItem(name: "byuser", value: byuser)) }
		if let inbarrel = inbarrel { elements.append(URLQueryItem(name: "inbarrel", value: inbarrel)) }
		if let after = after { elements.append(URLQueryItem(name: "after", value: after)) }
		if let before = before { elements.append(URLQueryItem(name: "before", value: before)) }
		if let afterdate = afterdate { elements.append(URLQueryItem(name: "afterdate", value: afterdate)) }
		if let beforedate = beforedate { elements.append(URLQueryItem(name: "beforedate", value: beforedate)) }
		if let from = from { elements.append(URLQueryItem(name: "from", value: from)) }
		let newOffset = max(start ?? 0 + startOffset, 0)
		if newOffset != 0 { elements.append(URLQueryItem(name: "start", value: String(newOffset))) }
		if let limit = limit { elements.append(URLQueryItem(name: "limit", value: String(limit))) }
		if let replyGroup = replyGroup { elements.append(URLQueryItem(name: "replyGroup", value: String(replyGroup))) }

		components.queryItems = elements
		return components.string
	}
}

struct ReportPageContext : Encodable {
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
	init(_ req: Request, fezID: String) throws {
		trunk = .init(req, title: "Report Friendly Fez", tab: .none)
		reportTitle = "Report a Friendly Fez"
		reportFormAction = "/fez/report/\(fezID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/fez"
	}
	
	// For reporting a user profile 
	init(_ req: Request, userID: String) throws {
		trunk = .init(req, title: "Report User Profile", tab: .none)
		reportTitle = "Report a User's Profile"
		reportFormAction = "/profile/report/\(userID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/user/\(userID)"
	}
	
}
    


struct SiteController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app)
        openRoutes.get(use: rootPageHandler)
	}
	
    func rootPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/notification/announcements").throwingFlatMap { response in
 			let announcements = try response.content.decode([AnnouncementData].self)
			return apiQuery(req, endpoint: "/notification/dailythemes").throwingFlatMap { themeResponse in
 				let themes = try themeResponse.content.decode([DailyThemeData].self)
 				let cal = Calendar.autoupdatingCurrent
				let components = cal.dateComponents([.day], from: cal.startOfDay(for: Settings.shared.cruiseStartDate), 
						to: cal.startOfDay(for: Date()))
				let cruiseDay = Int32(components.day ?? 0)
				var backupTheme: DailyThemeData
				if cruiseDay < 0 {
					backupTheme = DailyThemeData(themeID: UUID(), title: "\(0 - cruiseDay) Days before Boat", info: "Soon™", 
							image: nil, cruiseDay: cruiseDay)
				}
				else if cruiseDay < Settings.shared.cruiseLengthInDays {
					backupTheme = DailyThemeData(themeID: UUID(), title: "Cruise Day \(cruiseDay + 1): No Theme Day", info: 
							"A wise man once said, \"A day without a theme is like a guitar ever-so-slightly out of tune. " +
							"You can play it however you want, and it will be great, but someone out there will know " +
							"that if only there was a theme, everything would be in tune.\"", 
							image: nil, cruiseDay: cruiseDay)
				} else {
					backupTheme = DailyThemeData(themeID: UUID(), title: "\(cruiseDay + 1 - Int32(Settings.shared.cruiseLengthInDays)) Days after Boat", 
							info: "JoCo Cruise has ended. Hope you're enjoying being back in the real world.", image: nil, cruiseDay: cruiseDay)
				}
				let dailyTheme: DailyThemeData = themes.first { $0.cruiseDay == cruiseDay } ?? backupTheme
				struct HomePageContext : Encodable {
					var trunk: TrunkContext
					var announcements: [AnnouncementData]
					var dailyTheme: DailyThemeData?
					
					init(_ req: Request, announcements: [AnnouncementData], theme: DailyThemeData) throws {
						trunk = .init(req, title: "Twitarr", tab: .twitarr)
						self.announcements = announcements
						self.dailyTheme = theme
					}
				}
				let ctx = try HomePageContext(req, announcements: announcements, theme: dailyTheme)
				return req.view.render("home", ctx)
			}
		}
    }
    
}
    
// MARK: - Utilities

protocol SiteControllerUtils {
    var categoryIDParam: PathComponent { get }
    var twarrtIDParam: PathComponent { get }
    var forumIDParam: PathComponent { get }
    var postIDParam: PathComponent { get }
    var fezIDParam: PathComponent { get }
    var userIDParam: PathComponent { get }
    var eventIDParam: PathComponent { get }
    var reportIDParam: PathComponent { get }
    var modStateParam: PathComponent { get }
    var announcementIDParam: PathComponent { get }

	func registerRoutes(_ app: Application) throws
	func apiQuery(_ req: Request, endpoint: String, method: HTTPMethod, defaultHeaders: HTTPHeaders?, passThroughQuery: Bool,
			beforeSend: (inout ClientRequest) throws -> ()) -> EventLoopFuture<ClientResponse>
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

	/// Call the Swiftarr API. This method pulls a user's token from their session data and adds it to the API call. By default it also forwards URL query parameters
	/// from the Site-level request to the API-level request. 
	/// Previously, this method used the hostname and port from `application.http.server.configuration` to set the hostname and port to call.
	/// However, if Swiftarr is launched with command line overrides for the host and port, the HTTPServer startup code uses those overrides instead of the 
	/// values in the publicly accessible configuration, but does not update the values in the configuration. So, instead, we attempt to use the site-level Request's
	/// `Host` header to get these values.
	func apiQuery(_ req: Request, endpoint: String, method: HTTPMethod = .GET, defaultHeaders: HTTPHeaders? = nil,
			passThroughQuery: Bool = true,
			beforeSend: (inout ClientRequest) throws -> () = { _ in }) -> EventLoopFuture<ClientResponse> {
    	var headers = defaultHeaders ?? HTTPHeaders()
    	if let token = req.session.data["token"], !headers.contains(name: "Authorization") {
   			headers.add(name: "Authorization", value: "Bearer \(token)")
    	}
		let hostname = req.application.http.server.configuration.hostname
		let port = req.application.http.server.configuration.port
		let host: String = req.headers.first(name: "Host") ?? "\(hostname):\(port)"
    	var urlStr = "http://\(host)/api/v3" + endpoint
    	if passThroughQuery, let queryStr = req.url.query {
    		// FIXME: Chintzy. Should convert to URLComponents and back.
    		if urlStr.contains("?") {
	    		urlStr.append("&\(queryStr)")
    		}
    		else {
	    		urlStr.append("?\(queryStr)")
			}
    	}
    	return req.client.send(method, headers: headers, to: URI(string: urlStr), beforeSend: beforeSend).flatMapThrowing { response in
			guard response.status.code < 300 else {
				if let errorResponse = try? response.content.decode(ErrorResponse.self) {
					throw errorResponse
				}
				throw Abort(response.status)
			}
			return response
    	}
	}
	
	// Routes that the user does not need to be logged in to access.
	func getOpenRoutes(_ app: Application) -> RoutesBuilder {
		return app.grouped( [
				app.sessions.middleware, 
				User.sessionAuthenticator(),
				Token.authenticator(),
				NotificationsMiddleware()
		])
	}

	// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
	// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
	// redirect-chained through /login and back.
	func getGlobalRoutes(_ app: Application) -> RoutesBuilder {
		// This middleware redirects to "/login" when accessing a global page that requires auth while not logged in.
		// It saves the page the user was attempting to view in the session, so we can return there post-login.
		let redirectMiddleware = User.redirectMiddleware { (req) -> String in
			req.session.data["returnAfterLogin"] = req.url.string
			return "/login"
		}
		
		return app.grouped( [
				app.sessions.middleware, 
				User.sessionAuthenticator(),
				Token.authenticator(),
				NotificationsMiddleware(),
				redirectMiddleware
		])
	}
		
	// Routes for non-shareable content. If you're not logged in we failscreen. Most POST actions go here.
	func getPrivateRoutes(_ app: Application) -> RoutesBuilder {
		return app.grouped( [ 
				app.sessions.middleware, 
				User.sessionAuthenticator(),
				Token.authenticator(),
				User.guardMiddleware()
		])
	}
	
	// Convert a date string submitted by a client into a Date. Usually this comes from a form input field.
	// https://www.w3.org/TR/NOTE-datetime specifies a subset of what the ISO 8601 spec allows for date formats.
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

