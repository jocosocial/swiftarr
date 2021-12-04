import Vapor
import Crypto
import FluentSQL

struct TweetPageContext: Encodable {
	enum FilterType: String, Encodable {
		case all
		case byUser
		case mentions
		case favorites
		case liked
	}

	var trunk: TrunkContext
	var post: MessagePostContext
	var tweets: [TwarrtData]
	var filterDesc: String
	var topMorePostsURL: String?
	var topMorePostsLabel: String?
	var bottomMorePostsURL: String?
	var bottomMorePostsLabel: String?
	var isReplyGroup: Bool = false
	var filterType: FilterType

	init(_ req: Request, tweets: [TwarrtData]) throws {
		trunk = .init(req, title: "Tweets", tab: .twarrts, search: "Search Tweets")
		self.tweets = tweets
		let queryStruct = try req.query.decode(TwarrtQueryOptions.self)
		if let rg = queryStruct.replyGroup {
			filterDesc = "Reply Thread"
			if tweets.count == 1, tweets[0].replyGroupID == nil {
				filterDesc = "In reply to this post:"
			}
			isReplyGroup = true
			post = .init(forType: .tweetReply(rg))
		} else {
			post = .init(forType: .tweet)
			filterDesc = "Tweets"
		}
		
		var filters: [String] = []
		filterType = .all
		if let mention = queryStruct.mentions {
			filters.append(mention == trunk.username ? " mentioning you" : " that mention '\(mention)'")
			filterType = .mentions
		}
		if let mentionSelf = queryStruct.mentionSelf, mentionSelf == true {
			filters.append(" mentioning you")
			filterType = .mentions
		}
		if let hashtag = queryStruct.hashtag {
			filters.append(" with #\(hashtag)")
		}
		if let byUser = queryStruct.byUser {
			if byUser == trunk.userID {
				filters.append(" by you")
				filterType = .byUser
			}
			else {
				// Sucks, as it'll append the UUID not the username
				filters.append(" by '\(byUser)'")
			}
		}
		if let byUsername = queryStruct.byUsername {
			if byUsername == trunk.username {
				filters.append(" by you")
				filterType = .byUser
			}
			else {
				filters.append(" by '\(byUsername)'")
			}
		}
		if let liked = queryStruct.likeType {
			switch liked {
				case "like" : filters.append(" that you liked")
				case "laugh" : filters.append(" that made you laugh")
				case "love" : filters.append(" that you loved")
				default: filters.append(" that you liked")
			}
			filterType = .liked
		}
		if let bookmarked = queryStruct.bookmarked, bookmarked == true {
			filters.append(" you favorited")
			filterType = .favorites
		}
		if let search = queryStruct.search {
			filters.append(" containing '\(search)'")
		}
		filterDesc.append(filters.joined(separator: ","))
		
		if tweets.count > 0 {
			if queryStruct.directionIsNewer() {
				// Down the page => newer tweets. 
				var showTopButton = true
				if let firstTweet = tweets.first {
					if let replyGroup = queryStruct.replyGroup, replyGroup == firstTweet.twarrtID {
						showTopButton = false
					}
					if let after = queryStruct.after, after == firstTweet.twarrtID {
						showTopButton = false
					}
					if firstTweet.twarrtID == 1 {		// Not sure this can happen, but if it does, I mean, we can't go any older.
						showTopButton = false
					}
				}
				if showTopButton {
					topMorePostsURL = queryStruct.buildQuery(baseURL: "/tweets", startOffset: 0 - queryStruct.computedLimit())
					topMorePostsLabel = "Older"
				}
				bottomMorePostsURL = queryStruct.buildQuery(baseURL: "/tweets", startOffset: tweets.count)
				bottomMorePostsLabel = "Newer"
			}
			else {
				// Down the page => older tweets. Normal Twitter post order. In most cases we show the top "Newer" button
				// because even if we were at the newest tweet when we loaded, even newer ones may appear.
				var showTopButton = true
				if let firstTweet = tweets.first {
					if let before = queryStruct.before, before == firstTweet.twarrtID {
						showTopButton = false
					}
				}
				if showTopButton {
					topMorePostsURL = queryStruct.buildQuery(baseURL: "/tweets", startOffset: 0 - queryStruct.computedLimit())
					topMorePostsLabel = "Newer"
				}
				if let last = tweets.last, last.twarrtID != 1 {
					bottomMorePostsURL = queryStruct.buildQuery(baseURL: "/tweets", startOffset: tweets.count)
					bottomMorePostsLabel = "Older"
				}
			}
		}
	}
}

struct TweetEditPageContext : Encodable {
	var trunk: TrunkContext
	var replyToTweet: TwarrtDetailData?
	var post: MessagePostContext
	
	// For editing
	init(_ req: Request, editTweet: TwarrtDetailData) throws {
		trunk = .init(req, title: "Edit Twarrt", tab: .twarrts)
		self.post = .init(forType: .tweetEdit(editTweet))
	}
	
	// For replys
	init(_ req: Request, replyToTweet: TwarrtDetailData) {
		trunk = .init(req, title: "Reply to Twarrt", tab: .twarrts)
		self.replyToTweet = replyToTweet
		post = .init(forType: .tweetReply(replyToTweet.replyGroupID ?? replyToTweet.postID))
	}
}
	

struct SiteTwitarrController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .tweets))
		globalRoutes.get("tweets", use: tweetsPageHandler)
		globalRoutes.get("tweets", twarrtIDParam, use: tweetGetDetailHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .tweets))
		privateRoutes.post("tweets", twarrtIDParam, "like", use: tweetLikeActionHandler)
		privateRoutes.post("tweets", twarrtIDParam, "laugh", use: tweetLaughActionHandler)
		privateRoutes.post("tweets", twarrtIDParam, "love", use: tweetLoveActionHandler)
		privateRoutes.delete("tweets", twarrtIDParam, "like", use: tweetUnreactActionHandler)
		privateRoutes.delete("tweets", twarrtIDParam, "laugh", use: tweetUnreactActionHandler)
		privateRoutes.delete("tweets", twarrtIDParam, "love", use: tweetUnreactActionHandler)
		privateRoutes.post("tweets", twarrtIDParam, "unreact", use: tweetUnreactActionHandler)
		privateRoutes.post("tweets", twarrtIDParam, "bookmark", use: tweetBookmarkActionHandler)
		privateRoutes.delete("tweets", twarrtIDParam, "bookmark", use: tweetUnBookmarkActionHandler)
		privateRoutes.post("tweets", twarrtIDParam, "delete", use: tweetPostDeleteHandler)
		privateRoutes.get("tweets", "edit", twarrtIDParam, use: tweetEditPageHandler)
		privateRoutes.post("tweets", "edit", twarrtIDParam, use: tweetEditPostHandler)
		privateRoutes.post("tweets", "create", use: tweetCreatePostHandler)
		privateRoutes.post("tweets", "reply", twarrtIDParam, use: tweetReplyPostHandler)
		
		privateRoutes.get("tweets", "report", twarrtIDParam, use: tweetReportPageHandler)
		privateRoutes.post("tweets", "report", twarrtIDParam, use: tweetReportPostHandler)
	}
	
// MARK: - Twarrts
	/// `GET /tweets`
	///
	/// Returns a page of twarrts. Passes URL options through, including "?search=" option.
	func tweetsPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/twitarr").throwingFlatMap { response in
 			let tweets = try response.content.decode([TwarrtData].self)
			let ctx = try TweetPageContext(req, tweets: tweets)
			return req.view.render("Tweets/tweets", ctx)
		}
	}
	   
	// GET /tweets/ID
	// This is a passthrough for /api/v3/twitarr/ID, returning a TwarrtDetailData
	func tweetGetDetailHandler(_ req: Request) throws -> EventLoopFuture<TwarrtDetailData> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
		}
		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)").flatMapThrowing { response in
 			let tweetDetail = try response.content.decode(TwarrtDetailData.self)
			return tweetDetail
		}
	}

	// POST /tweets/ID/like and friends
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
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/\(reactionType)", method: .POST).flatMapThrowing { response in
 			let tweet = try response.content.decode(TwarrtData.self)
			return tweet
		}
	}
	
	// POST /tweets/ID/bookmark
	//
	// Bookmarks a tweet.
	func tweetBookmarkActionHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/bookmark", method: .POST).flatMapThrowing { response in
 			return response.status
		}
	}
	
	// DELETE /tweets/ID/bookmark
	//
	// Un-bookmarks a tweet.
	func tweetUnBookmarkActionHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/bookmark/remove", method: .POST).flatMapThrowing { response in
 			return response.status
		}
	}
	
	// POST /tweets/ID/delete
	// Although this looks like it just redirects the call, middleware plays an important part here. 
	// Javascript POSTs the delete request, middleware for this route validates via the session cookia.
	// We then call the Swiftarr API, using the token (pulled out of our session data) to validate.
	func tweetPostDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)", method: .DELETE).map { response in
			return response.status
		}
	}
	
	// POST /tweets/create
	func tweetCreatePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = postStruct.buildPostContentData()
		return apiQuery(req, endpoint: "/twitarr/create", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
//			let tweet = try response.content.decode(TwarrtData.self)
			return .created
		}
	}
		
    // POST /tweets/reply/ID
    //
    // When posting a twarrt reply, the ID should usually be the twarrt you're replying to. 
    func tweetReplyPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images, 
				postAsModerator: postStruct.postAsModerator != nil)
 		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/reply", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).map { response in
			return .created
		}
    }
    
	// GET /tweets/edit/ID
	func tweetEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
		}
		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)").throwingFlatMap { response in
 			let tweet = try response.content.decode(TwarrtDetailData.self)
	 		struct TweetEditPageContext : Encodable {
				var trunk: TrunkContext
				var post: MessagePostContext
				
				init(_ req: Request, tweet: TwarrtDetailData) throws {
					trunk = .init(req, title: "Edit Twarrt", tab: .twarrts)
					self.post = .init(forType: .tweetEdit(tweet))
				}
			}
			var ctx = try TweetEditPageContext(req, tweet: tweet)
			if ctx.trunk.userID != tweet.author.userID {
				ctx.post.authorName = ctx.trunk.username
			}
			return req.view.render("Tweets/tweetEdit", ctx)
		}
	}
	
	// POST /tweets/edit/ID
	func tweetEditPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images, 
				postAsModerator: postStruct.postAsModerator != nil)
 		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/update", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			return Response(status: .created)
		}
	}
	
	// GET /tweets/report
	//
	// Shows the report page.
	func tweetReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
		}
		let ctx = try ReportPageContext(req, twarrtID: twarrtID)
		return req.view.render("reportCreate", ctx)
	}
	
	// POST /tweets/report
	//
	// Submits a completed report.
	func tweetReportPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
		guard let twarrtID = req.parameters.get(twarrtIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
		}
		let postStruct = try req.content.decode(ReportData.self)
 		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/report", method: .POST, beforeSend: { req throws in
			try req.content.encode(postStruct)
		}).flatMapThrowing { response in
			return .created
		}
	}
}

