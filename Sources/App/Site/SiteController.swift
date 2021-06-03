import Vapor
import Crypto
import FluentSQL

// Leaf data used by all views. Mostly this is stuff in the navbar.
struct TrunkContext : Encodable {
	var title: String
	var metaRedirectURL: String?
	
	// current nav item
	
	var userIsLoggedIn: Bool
	var userIsMod: Bool
	var username: String
	var userID: UUID
	
	
	init(_ req: Request, title: String) {
		if let user = req.auth.get(User.self) {
			userIsLoggedIn = true
			userIsMod = user.accessLevel.hasAccess(.moderator)
			username = user.username
			userID = user.id!
		}
		else {
			userIsLoggedIn = false
			userIsMod = false
			username = ""
			userID = UUID(uuid: UUID_NULL)
		}
		self.title = title
	}
}

// Leaf data used by the messagePostForm.
struct MessagePostContext: Encodable {
	var messageText: String = ""
	var photoFilenames: [String] = ["", "", "", ""]	// Must have 4 values to make Leaf templating work. Use "" as placeholder.
	var formAction: String
	var postSuccessURL: String
	var authorName: String?							// Nil if current user is also author. Non-nil therefore implies mod edit.
	var showForumTitle: Bool = false
	
	// For creating a new tweet
	init() {
		formAction = "/tweets/create"
		postSuccessURL = "/tweets"
	}
	
	// For editing a tweet
	init(with tweet: TwarrtDetailData) {
		messageText = tweet.text
		photoFilenames = tweet.images ?? []
		while photoFilenames.count < 4 {
			photoFilenames.append("")
		}
		formAction = "/tweets/edit/\(tweet.postID)"
		postSuccessURL = "/tweets"
	}
	
	// For creating a new forum in a category
	init(withCategoryID catID: String) {
		formAction = "/forums/\(catID)/createForum"
		postSuccessURL = "/forums/\(catID)"
		showForumTitle = true
	}
	
	// For creating a new post in a forum
	init(withForumID forumID: String) {
		formAction = "/forum/\(forumID)/create"
		postSuccessURL = "/forum/\(forumID)"
	}
	
	// For editing a post in a forum
	init(withForumPost: PostDetailData) {
		messageText = withForumPost.text
		photoFilenames = withForumPost.images ?? []
		while photoFilenames.count < 4 {
			photoFilenames.append("")
		}
		formAction = "/forumpost/edit/\(withForumPost.postID)"
		postSuccessURL = "/forum/\(withForumPost.forumID)"
	}
	
	// For creating a new Seamail thread--parameter is not used
	init(forNewSeamail: Bool) {
		formAction = "/seamail/create"
		postSuccessURL = "/seamail"
	}
	
	// For posting in an existing Seamail thread
	init(forSeamail: FezData) {
		formAction = "/seamail/\(forSeamail.fezID)/post"
		postSuccessURL = "/seamail/\(forSeamail.fezID)"
	}
}

// POST data structure returned by the form in messagePostForm.leaf
// This form and data structure are used for creating and editing twarrts, forum posts, and fez messages.
struct MessagePostFormContent : Codable {
	let forumTitle: String?					// Only used when creating new forums
	let postText: String
	let localPhoto1: Data?
	let serverPhoto1: String?
	let localPhoto2: Data?
	let serverPhoto2: String?
	let localPhoto3: Data?
	let serverPhoto3: String?
	let localPhoto4: Data?
	let serverPhoto4: String?
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
	
	// TRUE if the 'next' tweets in this query are going to be newer or older than the current ones.
	// For instance, by default the 'anchor' is the most recent tweet and the direction is towards older tweets.
	func directionIsNewer() -> Bool {
		return (after != nil) || (afterdate != nil)  || (from == "first")
	}
	
	func computedLimit() -> Int {
		return limit ?? 50
	}
	
	func buildQuery(baseURL: String, startOffset: Int) -> String? {
		
		guard startOffset >= 0 || (self.start ?? 0) > 0 else {
			return nil
		}
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
		trunk = .init(req, title: "Report Twarrt")
		reportTitle = "Report a Twarrt"
		reportFormAction = "/tweets/report/\(twarrtID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/tweets"
	}
	
	// For reporting a forum post
	init(_ req: Request, postID: String) throws {
		trunk = .init(req, title: "Report Forum Post")
		reportTitle = "Report a Forum Post"
		reportFormAction = "/forumpost/report/\(postID)"
		reportSuccessURL = req.headers.first(name: "Referer") ?? "/forums"
	}
}
    


struct SiteController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app)
        openRoutes.get(use: rootPageHandler)
        openRoutes.get("events", use: eventsPageHandler)

		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
//		let globalRoutes = getGlobalRoutes(app)

		// Routes for non-shareable content. If you're not logged in we failscreen.
//		let privateRoutes = getPrivateRoutes(app)
	}
	
    func rootPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
	    return req.view.render("login", ["name": "Leaf"])
    }
    
// MARK: - Events
    func eventsPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/events").throwingFlatMap { response in
 			let events = try response.content.decode([EventData].self)
     		struct EventPageContext : Encodable {
				var trunk: TrunkContext
    			var events: [EventData]
    			
    			init(_ req: Request, events: [EventData]) {
    				self.events = events
    				trunk = .init(req, title: "Events")
    			}
    		}
    		var eventContext = EventPageContext(req, events: events)
    		eventContext.events[0].title = "<script>alert('Hello Bob!')</script>"
			return req.view.render("events", eventContext)
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

	func apiQuery(_ req: Request, endpoint: String, method: HTTPMethod, defaultHeaders: HTTPHeaders?,
			beforeSend: (inout ClientRequest) throws -> ()) -> EventLoopFuture<ClientResponse>
}

extension SiteControllerUtils {

    var categoryIDParam: PathComponent { PathComponent(":category_id") }
    var twarrtIDParam: PathComponent { PathComponent(":twarrt_id") }
    var forumIDParam: PathComponent { PathComponent(":forum_id") }
    var postIDParam: PathComponent { PathComponent(":post_id") }
    var fezIDParam: PathComponent { PathComponent(":fez_id") }
    var userIDParam: PathComponent { PathComponent(":user_id") }

	func apiQuery(_ req: Request, endpoint: String, method: HTTPMethod = .GET, defaultHeaders: HTTPHeaders? = nil,
			beforeSend: (inout ClientRequest) throws -> () = { _ in }) -> EventLoopFuture<ClientResponse> {
    	var headers = defaultHeaders ?? HTTPHeaders()
    	if let token = req.session.data["token"], !headers.contains(name: "Authorization") {
   			headers.add(name: "Authorization", value: "Bearer \(token)")
    	}
//    	var urlStr = "http://localhost:8081/api/v3" + endpoint
		let hostname = req.application.http.server.configuration.hostname
		let port = req.application.http.server.configuration.port
    	var urlStr = "http://\(hostname):\(port)/api/v3" + endpoint
    	if let queryStr = req.url.query {
    		urlStr.append("?\(queryStr)")
    	}
    	return req.client.send(method, headers: headers, to: URI(string: urlStr), beforeSend: beforeSend)
	}
	
	// Routes that the user does not need to be logged in to access.
	func getOpenRoutes(_ app: Application) -> RoutesBuilder {
		return app.grouped( [
				app.sessions.middleware, 
				User.sessionAuthenticator(),
				Token.authenticator()
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
}


/*	Navbar reqs
		User logged in?
		User is mod?
		Username
		Current page, for highlighting 
		Title
		Search target?
	

*/


