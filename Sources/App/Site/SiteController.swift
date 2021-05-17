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
	var messageText: String
	var photoFilenames: [String] 			// Must have 4 values to make Leaf templating work. Use "" as placeholder.
	var formAction: String
	var postSuccessURL: String
	
	// For creating a new tweet
	init() {
		messageText = ""
		photoFilenames = ["", "", "", ""]
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
}

// POST data structure returned by the form in messagePostForm.leaf
struct MessagePostFormContent : Codable {
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

struct SiteController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that the user does not need to be logged in to access.
		let openRoutes = getOpenRoutes(app)
        openRoutes.get(use: rootPageHandler)
        openRoutes.get("events", use: eventsPageHandler)

		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app)
        globalRoutes.get("tweets", use: tweetsPageHandler)
        globalRoutes.get("forums", use: forumCategoriesPageHandler)
        globalRoutes.get("forums", categoryIDParam, use: forumPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app)
        privateRoutes.post("tweets", twarrtIDParam, "like", use: tweetLikeActionHandler)
        privateRoutes.post("tweets", twarrtIDParam, "laugh", use: tweetLaughActionHandler)
        privateRoutes.post("tweets", twarrtIDParam, "love", use: tweetLoveActionHandler)
        privateRoutes.post("tweets", twarrtIDParam, "unreact", use: tweetUnreactActionHandler)
        privateRoutes.post("tweets", twarrtIDParam, "delete", use: tweetPostDeleteHandler)
        privateRoutes.get("tweets", "reply", twarrtIDParam, use: tweetReplyPageHandler)
		privateRoutes.post("tweets", "reply", twarrtIDParam, use: tweetReplyPostHandler)
		privateRoutes.get("tweets", "edit", twarrtIDParam, use: tweetEditPageHandler)
        privateRoutes.post("tweets", "edit", twarrtIDParam, use: tweetEditPostHandler)
        privateRoutes.post("tweets", "create", use: tweetCreatePostHandler)
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
    
// MARK: - Twarrts
    func tweetsPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	return apiQuery(req, endpoint: "/twitarr").throwingFlatMap { response in
 			let tweets = try response.content.decode([TwarrtData].self)
     		struct TweetPageContext : Encodable {
				var trunk: TrunkContext
				var post: MessagePostContext
    			var tweets: [TwarrtData]
    			var filterDesc: String
    			var earlierPostsUrl: String?
    			var laterPostsUrl: String?
    			
    			init(_ req: Request, tweets: [TwarrtData]) throws {
    				trunk = .init(req, title: "Tweets")
    				post = .init()
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
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/\(reactionType)", method: .POST).flatMapThrowing { response in
 			let tweet = try response.content.decode(TwarrtData.self)
    		return tweet
    	}
    }
    
    // Although this looks like it just redirects the call, middleware plays an important part here. 
    // Javascript POSTs the delete request, middleware for this route validates via the session cookia.
    // We then call the Swiftarr API, using the token (pulled out of our session data) to validate.
    func tweetPostDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
    	}
    	return apiQuery(req, endpoint: "/twitarr/\(twarrtID)", method: .DELETE).map { response in
    		return response.status
    	}
    }
    
    func tweetCreatePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText, images: images)
		return apiQuery(req, endpoint: "/twitarr/create", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			if response.status.code < 300 {
//				let tweet = try response.content.decode(TwarrtData.self)
//				return req.redirect(to: "/tweets")
				return Response(status: .created)
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
    }
    
	struct TweetEditPageContext : Encodable {
		var trunk: TrunkContext
		var replyToTweet: TwarrtDetailData?
		var post: MessagePostContext
		
		// For editing
		init(_ req: Request, editTweet: TwarrtDetailData) throws {
			trunk = .init(req, title: "Edit Twarrt")
			self.post = .init(with: editTweet)
		}
		
		// For replys
		init(_ req: Request, replyToTweet: TwarrtDetailData) {
			trunk = .init(req, title: "Reply to Twarrt")
			self.replyToTweet = replyToTweet
			post = .init()
		}
	}
	
    func tweetReplyPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/twitarr/\(twarrtID)").throwingFlatMap { response in
 			let tweet = try response.content.decode(TwarrtDetailData.self)
    		var ctx = TweetEditPageContext(req, replyToTweet: tweet)
    		ctx.post.formAction = "/tweets/reply/\(twarrtID)"
			return req.view.render("tweetReply", ctx)
    	}
    }
    
    func tweetReplyPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText, images: images)
 		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/reply", method: .POST, beforeSend: { req throws in
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
    
    func tweetEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/twitarr/\(twarrtID)").throwingFlatMap { response in
 			let tweet = try response.content.decode(TwarrtDetailData.self)
     		struct TweetEditPageContext : Encodable {
				var trunk: TrunkContext
    			var post: MessagePostContext
    			
    			init(_ req: Request, tweet: TwarrtDetailData) throws {
    				trunk = .init(req, title: "Edit Twarrt")
    				self.post = .init(with: tweet)
    			}
    		}
    		let ctx = try TweetEditPageContext(req, tweet: tweet)
			return req.view.render("tweetEdit", ctx)
    	}
    }
    
    func tweetEditPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText, images: images)
 		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/update", method: .POST, beforeSend: { req throws in
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
}

    
// MARK: - Utilities

protocol SiteControllerUtils {
    var categoryIDParam: PathComponent { get }
    var twarrtIDParam: PathComponent { get }
    var forumIDParam: PathComponent { get }
    var postIDParam: PathComponent { get }

	func apiQuery(_ req: Request, endpoint: String, method: HTTPMethod, defaultHeaders: HTTPHeaders?,
			beforeSend: (inout ClientRequest) throws -> ()) -> EventLoopFuture<ClientResponse>
}

extension SiteControllerUtils {

    var categoryIDParam: PathComponent { PathComponent(":category_id") }
    var twarrtIDParam: PathComponent { PathComponent(":twarrt_id") }
    var forumIDParam: PathComponent { PathComponent(":forum_id") }
    var postIDParam: PathComponent { PathComponent(":post_id") }

	func apiQuery(_ req: Request, endpoint: String, method: HTTPMethod = .GET, defaultHeaders: HTTPHeaders? = nil,
			beforeSend: (inout ClientRequest) throws -> () = { _ in }) -> EventLoopFuture<ClientResponse> {
    	var headers = defaultHeaders ?? HTTPHeaders()
    	if let token = req.session.data["token"], !headers.contains(name: "Authorization") {
   			headers.add(name: "Authorization", value: "Bearer \(token)")
    	}
    	var urlStr = "http://localhost:8081/api/v3" + endpoint
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


