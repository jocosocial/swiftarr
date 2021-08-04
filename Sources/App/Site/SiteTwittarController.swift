import Vapor
import Crypto
import FluentSQL

struct SiteTwitarrController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app)
        globalRoutes.get("tweets", use: tweetsPageHandler)
        globalRoutes.get("tweets", twarrtIDParam, use: tweetGetDetailHandler)

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
        privateRoutes.get("tweets", "report", twarrtIDParam, use: tweetReportPageHandler)
        privateRoutes.post("tweets", "report", twarrtIDParam, use: tweetReportPostHandler)
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
    				trunk = .init(req, title: "Tweets", tab: .twarrts)
					post = .init(forType: .tweet)
    				self.tweets = tweets
    				filterDesc = "Tweets"
					let queryStruct = try req.query.decode(TwarrtQuery.self)
					if let mention = queryStruct.mentions {
						filterDesc =  mention == trunk.username ? "Your Mentions" : "'\(mention)' Mentions"
					}
					else if let hashtag = queryStruct.hashtag {
						filterDesc = "#\(hashtag)"
					}
					else if let byuser = queryStruct.byuser {
						filterDesc = "Tweets by '\(byuser)'"
					}
					else if let search = queryStruct.search {
						filterDesc = "Search: '\(search)'"
					}
    				if tweets.count > 0 {
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
			return req.view.render("Tweets/tweets", ctx)
    	}
    }
        
    // This is a passthrough for /api/v3/twitarr/ID, returning a TwarrtDetailData
	func tweetGetDetailHandler(_ req: Request) throws -> EventLoopFuture<TwarrtDetailData> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/twitarr/\(twarrtID)").flatMapThrowing { response in
 			let tweetDetail = try response.content.decode(TwarrtDetailData.self)
 			if response.status.code < 300 {
				return tweetDetail
			}
			else {
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
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
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images)
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
			trunk = .init(req, title: "Edit Twarrt", tab: .twarrts)
			self.post = .init(forType: .tweetEdit(editTweet))
		}
		
		// For replys
		init(_ req: Request, replyToTweet: TwarrtDetailData) {
			trunk = .init(req, title: "Reply to Twarrt", tab: .twarrts)
			self.replyToTweet = replyToTweet
			post = .init(forType: .tweet)
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
			return req.view.render("Tweets/tweetReply", ctx)
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
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images)
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
    
    func tweetEditPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images)
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
    
    func tweetReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
		let ctx = try ReportPageContext(req, twarrtID: twarrtID)
    	return req.view.render("reportCreate", ctx)
    }
    
	func tweetReportPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let twarrtID = req.parameters.get(twarrtIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing twarrt_id parameter.")
    	}
		let postStruct = try req.content.decode(ReportData.self)
 		return apiQuery(req, endpoint: "/twitarr/\(twarrtID)/report", method: .POST, beforeSend: { req throws in
			try req.content.encode(postStruct)
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
}

