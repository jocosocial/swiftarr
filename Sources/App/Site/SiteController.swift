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
struct MessagePostFormContent: Encodable {
	var messageText: String
	var photoFilename: String?
	
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

struct SiteController: RouteCollection {
	weak var app: Application?

    let categoryIDParam = PathComponent(":category_id")
    let forumIDParam = PathComponent(":forum_id")
    let postIDParam = PathComponent(":post_id")

	init(_ app: Application) {
		self.app = app
	}

	func boot(routes: RoutesBuilder) throws {
		guard let app = app else { return }

		// Routes that the user does not need to be logged in to access.
		let openRoutes: RoutesBuilder = routes.grouped( [
				app.sessions.middleware, 
				User.sessionAuthenticator(),
				Token.authenticator()
		])
        openRoutes.get(use: rootPageHandler)
        openRoutes.get("login", use: loginPageHandler)
        openRoutes.post("login", use: loginPageLoginHandler)
        openRoutes.get("createAccount", use: createAccountPageHandler)

        openRoutes.get("events", use: eventsPageHandler)

		// This middleware redirects to "/login" when accessing a global page that requires auth while not logged in.
		// It saves the page the user was attempting to view in the session, so we can return there post-login.
		let redirectMiddleware = User.redirectMiddleware { (req) -> String in
			req.session.data["returnAfterLogin"] = req.url.string
			return "/login"
		}
		
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.
		let globalRoutes: RoutesBuilder = routes.grouped( [
				app.sessions.middleware, 
				User.sessionAuthenticator(),
				Token.authenticator(),
				redirectMiddleware
		])
		
        globalRoutes.get("tweets", use: tweetsPageHandler)
        globalRoutes.get("forums", use: forumCategoriesPageHandler)
        globalRoutes.get("forums", categoryIDParam, use: forumPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = routes.grouped( [ 
				app.sessions.middleware, 
				User.sessionAuthenticator(),
				Token.authenticator(),
				User.guardMiddleware()
		])
		
        privateRoutes.get("logout", use: loginPageHandler)
        privateRoutes.post("logout", use: loginPageLogoutHandler)
        privateRoutes.post("tweets", ":twarrt_id", "like", use: tweetLikeActionHandler)
        privateRoutes.post("tweets", ":twarrt_id", "laugh", use: tweetLaughActionHandler)
        privateRoutes.post("tweets", ":twarrt_id", "love", use: tweetLoveActionHandler)
        privateRoutes.post("tweets", ":twarrt_id", "unreact", use: tweetUnreactActionHandler)
        privateRoutes.get("tweets", "edit", ":twarrt_id", use: tweetEditPageHandler)
	}
	
    func rootPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
	    return req.view.render("login", ["name": "Leaf"])
    }
    

// MARK: - Login
	struct LoginPageContext : Encodable {
		var trunk: TrunkContext
		var loginError: String?
		var operationSuccess: Bool
		var operationName: String
		
		init(_ req: Request) {
			trunk = .init(req, title: "Login")
			operationSuccess = false
			operationName = "Login"
		}
	}

    func loginPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return req.view.render("login", LoginPageContext(req))
	}
	    
    func loginPageLoginHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	struct PostStruct : Codable {
    		var username: String
    		var password: String
    	}
		let postStruct = try req.content.decode(PostStruct.self)
		let credentials = "\(postStruct.username):\(postStruct.password)".data(using: .utf8)!.base64EncodedString()
		let headers = HTTPHeaders([("Authorization", "Basic \(credentials)")])
    	return req.client.post("http://localhost:8081/api/v3/auth/login", headers: headers)
    		.throwingFlatMap { apiResponse in
    			if apiResponse.status.code < 300 {
					let tokenResponse = try apiResponse.content.decode(TokenStringData.self)
					return User.query(on: req.db).filter(\.$id == tokenResponse.userID).first().flatMap { user in
						var loginContext = LoginPageContext(req)
						guard let user = user else {
							loginContext.loginError = "User not found"
							return req.view.render("login", loginContext)
						}
						req.auth.login(user)
						req.session.data["token"] = tokenResponse.token				
						loginContext.trunk.metaRedirectURL = req.session.data["returnAfterLogin"] ?? "/tweets"
						loginContext.operationSuccess = true
						return req.view.render("login", loginContext)
					}
				}
				else {
					let errorResponse = try apiResponse.content.decode(ErrorResponse.self)
					var loginContext = LoginPageContext(req)
					loginContext.loginError = errorResponse.reason
					return req.view.render("login", loginContext) 
				}
			}
			.flatMapError { error in 
				var loginContext = LoginPageContext(req)
				loginContext.loginError = error.localizedDescription
				return req.view.render("login", loginContext)
			}
	}
	    
    func loginPageLogoutHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	req.session.destroy()
    	req.auth.logout(User.self)
    	req.auth.logout(Token.self)
    	var loginContext = LoginPageContext(req)
		loginContext.trunk.metaRedirectURL = "/login"
		loginContext.operationSuccess = true
		loginContext.operationName = "Logout"
		return req.view.render("login", loginContext)
    }
    
    func createAccountPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return req.view.render("createAccount", LoginPageContext(req))
    }

// MARK: - Events
    func eventsPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	return req.client.get("http://localhost:8081/api/v3/events").throwingFlatMap { response in
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
    
// MARK: - Twarrts
    func tweetsPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	return apiQuery(req, endpoint: "/twitarr").throwingFlatMap { response in
 			let tweets = try response.content.decode([TwarrtData].self)
     		struct TweetPageContext : Encodable {
				var trunk: TrunkContext
    			var tweets: [TwarrtData]
    			var filterDesc: String
    			var earlierPostsUrl: String?
    			var laterPostsUrl: String?
    			
    			init(_ req: Request, tweets: [TwarrtData]) throws {
    				trunk = .init(req, title: "Tweets")
    				self.tweets = tweets
    				filterDesc = "Tweets"
    				if tweets.count > 0 {
    					let queryStruct = try req.query.decode(TwarrtQuery.self)
						if queryStruct.directionIsNewer() {
							laterPostsUrl = queryStruct.buildQuery(baseURL: "/tweets", startOffset: tweets.count)
							earlierPostsUrl = queryStruct.buildQuery(baseURL: "/tweets", startOffset: 0 - queryStruct.computedLimit())
						}
						else {
							laterPostsUrl = queryStruct.buildQuery(baseURL: "/tweets", startOffset: 0 - queryStruct.computedLimit())
							if let last = tweets.last, last.twarrtID != 1 {
								earlierPostsUrl = queryStruct.buildQuery(baseURL: "/tweets", startOffset: tweets.count)
	    					}
						}
					}
    			}
    		}
    		let ctx = try TweetPageContext(req, tweets: tweets)
			return req.view.render("tweets", ctx)
    	}
    }
    
    func tweetLikeActionHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
		return try tweetPostReactionHandler(req, reactionType: "like")
    }
    func tweetLaughActionHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
		return try tweetPostReactionHandler(req, reactionType: "laugh")
    }
    func tweetLoveActionHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
		return try tweetPostReactionHandler(req, reactionType: "love")
    }
    func tweetUnreactActionHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
		return try tweetPostReactionHandler(req, reactionType: "unreact")
    }
    
    func tweetPostReactionHandler(_ req: Request, reactionType: String) throws -> EventLoopFuture<TwarrtData> {
    	guard let twarrtID = req.parameters.get("twarrt_id") else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/\(reactionType)", method: .POST).flatMapThrowing { response in
 			let tweet = try response.content.decode(TwarrtData.self)
    		return tweet
    	}
    }
    
    func tweetEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let twarrtID = req.parameters.get("twarrt_id") else {
            throw Abort(.badRequest, reason: "Missing twarr_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/twitarr/\(twarrtID)").throwingFlatMap { response in
 			let tweet = try response.content.decode(TwarrtDetailData.self)
     		struct TweetEditPageContext : Encodable {
				var trunk: TrunkContext
    			var tweet: TwarrtDetailData
    			
    			init(_ req: Request, tweet: TwarrtDetailData) throws {
    				trunk = .init(req, title: "Edit Twarrt")
    				self.tweet = tweet
    			}
    		}
    		let ctx = try TweetEditPageContext(req, tweet: tweet)
			return req.view.render("tweetEdit", ctx)
    	}
    }

// MARK: - Forums
    func forumCategoriesPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/categories").throwingFlatMap { response in
 			let categories = try response.content.decode([CategoryData].self)
     		struct ForumCatPageContext : Encodable {
				var trunk: TrunkContext
    			var categories: [CategoryData]
    			
    			init(_ req: Request, cats: [CategoryData]) throws {
    				trunk = .init(req, title: "Forum Categories")
    				self.categories = cats
    			}
    		}
    		let ctx = try ForumCatPageContext(req, cats: categories)
			return req.view.render("forumCategories", ctx)
    	}
    }
    
    func forumPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let catID = req.parameters.get(categoryIDParam.paramString) else {
    		throw "Invalid forum category ID"
    	}
    	
		return apiQuery(req, endpoint: "/forum/categories/\(catID)").throwingFlatMap { response in
 			let forums = try response.content.decode([ForumListData].self)
     		struct ForumPageContext : Encodable {
				var trunk: TrunkContext
    			var forums: [ForumListData]
    			
    			init(_ req: Request, forums: [ForumListData]) throws {
    				trunk = .init(req, title: "Forum Threads")
    				self.forums = forums
    			}
    		}
    		let ctx = try ForumPageContext(req, forums: forums)
			return req.view.render("forums", ctx)
    	}
    }
    
// MARK: Utilities

	func apiQuery(_ req: Request, endpoint: String, method: HTTPMethod = .GET) -> EventLoopFuture<ClientResponse> {
    	var headers = HTTPHeaders()
    	if let token = req.session.data["token"] {
   			headers.add(name: "Authorization", value: "Bearer \(token)")
    	}
    	var urlStr = "http://localhost:8081/api/v3" + endpoint
    	if let queryStr = req.url.query {
    		urlStr.append("?\(queryStr)")
    	}
    	return req.client.send(method, headers: headers, to: URI(string: urlStr))
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
