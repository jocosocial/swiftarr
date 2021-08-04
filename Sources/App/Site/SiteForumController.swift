import Vapor
import Crypto
import FluentSQL

struct SiteForumController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app)
		globalRoutes.get("forums", use: forumCategoriesPageHandler)
		globalRoutes.get("forums", categoryIDParam, use: forumPageHandler)
		globalRoutes.get("forum", forumIDParam, use: forumThreadPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app)
		privateRoutes.post("forumpost", postIDParam, "like", use: forumPostLikeActionHandler)
		privateRoutes.post("forumpost", postIDParam, "laugh", use: forumPostLaughActionHandler)
		privateRoutes.post("forumpost", postIDParam, "love", use: forumPostLoveActionHandler)
		privateRoutes.post("forumpost", postIDParam, "unreact", use: forumPostUnreactActionHandler)

		privateRoutes.get("forums", categoryIDParam, "createForum", use: forumCreateViewHandler)
		privateRoutes.post("forums", categoryIDParam, "createForum", use: forumCreateForumPostHandler)

		privateRoutes.post("forum", forumIDParam, "create", use: forumPostPostHandler)
		privateRoutes.get("forum", forumIDParam, "edit", use: forumEditViewHandler)
		privateRoutes.post("forum", forumIDParam, "edit", use: forumEditTitlePostHandler)
		privateRoutes.post("forum", forumIDParam, "delete", use: forumDeleteHandler)
		privateRoutes.get("forum", "report", forumIDParam, use: forumReportPageHandler)
		privateRoutes.post("forum", "report", forumIDParam, use: forumReportPostHandler)

		privateRoutes.get("forumpost", "edit", postIDParam, use: forumPostEditPageHandler)
		privateRoutes.post("forumpost", "edit", postIDParam, use: forumPostEditPostHandler)
		privateRoutes.post("forumpost", postIDParam, "delete", use: forumPostDeleteHandler)
		privateRoutes.get("forumpost", "report", postIDParam, use: forumPostReportPageHandler)
		privateRoutes.post("forumpost", "report", postIDParam, use: forumPostReportPostHandler)
		privateRoutes.get("forumpost", postIDParam, use: forumGetPostDetails)
		privateRoutes.get("forumpost", "mentions", use: forumGetUserMentions)
	}

// Note: These groupings are roughly based on what type of URL parameters each method takes to identify its target:
// category/forum/post
// MARK: - Categories

	// Shows a list of forum categories
    func forumCategoriesPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/categories").throwingFlatMap { response in
 			let categories = try response.content.decode([CategoryData].self)
     		struct ForumCatPageContext : Encodable {
				var trunk: TrunkContext
    			var categories: [CategoryData]
    			
    			init(_ req: Request, cats: [CategoryData]) throws {
    				trunk = .init(req, title: "Forum Categories", tab: .forums)
    				self.categories = cats
    			}
    		}
    		let ctx = try ForumCatPageContext(req, cats: categories)
			return req.view.render("Forums/forumCategories", ctx)
    	}
    }
    
    // Shows a page of forum threads in a category
    func forumPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let catID = req.parameters.get(categoryIDParam.paramString) else {
    		throw "Invalid forum category ID"
    	}
        let start = (req.query[Int.self, at: "start"] ?? 0)
        let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...200)
    	
		return apiQuery(req, endpoint: "/forum/categories/\(catID)").throwingFlatMap { response in
 			let forums = try response.content.decode(CategoryData.self)
     		struct ForumsPageContext : Encodable {
				var trunk: TrunkContext
    			var forums: CategoryData
				var paginator: PaginatorContext
    			
    			init(_ req: Request, forums: CategoryData, start: Int, limit: Int) throws {
    				trunk = .init(req, title: "Forum Threads", tab: .forums)
    				self.forums = forums
					paginator = .init(currentPage: start / limit, totalPages: (Int(forums.numThreads) + limit - 1) / limit) { pageIndex in
						"/forums/\(forums.categoryID)?start=\(pageIndex * limit)&limit=\(limit)"
					}
    			}
    		}
    		let ctx = try ForumsPageContext(req, forums: forums, start: start, limit: limit)
			return req.view.render("Forums/forums", ctx)
    	}
    }
    
    // Shows the page for creating a new forum thread in a category.
    func forumCreateViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let catID = req.parameters.get(categoryIDParam.paramString) else {
    		throw "Invalid category ID"
    	}
		return apiQuery(req, endpoint: "/forum/categories?cat=\(catID)").throwingFlatMap { catResponse in
			let cats = try catResponse.content.decode([CategoryData].self)
			struct ForumCreateContext : Encodable {
				var trunk: TrunkContext
				var categoryID: String
				var post: MessagePostContext
				var category: CategoryData
				
				init(_ req: Request, catID: String, cat: [CategoryData]) throws {
					trunk = .init(req, title: "Create New Forum", tab: .forums)
					self.categoryID = catID
					self.post = .init(forType: .forum(catID))
					if cat.count > 0 {
						category = cat[0]
					}
					else {
						category = CategoryData(categoryID: UUID(), title: "Unknown Category", 
								isRestricted: false, numThreads: 0, forumThreads: nil)
					}
				}
			}
			let ctx = try ForumCreateContext(req, catID: catID, cat: cats)
			return req.view.render("Forums/forumCreate", ctx)
		}
    }
    
	// POST handler for creating a new forum in a category.
    func forumCreateForumPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let catID = req.parameters.get(categoryIDParam.paramString) else {
    		throw "Invalid category ID"
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		guard let forumTitle = postStruct.forumTitle else {
			throw "Forum must have a ttile"
		}
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images)
		let forumContent = ForumCreateData(title: forumTitle, firstPost: postContent)
		return apiQuery(req, endpoint: "/forum/categories/\(catID)/create", method: .POST, beforeSend: { req throws in
			try req.content.encode(forumContent)
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

    // Shows an individual forum thread
    func forumThreadPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
    		throw "Invalid forum category ID"
    	}
		return apiQuery(req, endpoint: "/forum/\(forumID)").throwingFlatMap { response in
 			let forum = try response.content.decode(ForumData.self)
 			return apiQuery(req, endpoint: "/forum/categories?cat=\(forum.categoryID)", 
 					passThroughQuery: false).throwingFlatMap { catResponse in
 				let cats = try catResponse.content.decode([CategoryData].self)
				struct ForumPageContext : Encodable {
					var trunk: TrunkContext
					var forum: ForumData
					var post: MessagePostContext
					var category: CategoryData
					var paginator: PaginatorContext
					
					init(_ req: Request, forum: ForumData, cat: [CategoryData]) throws {
						trunk = .init(req, title: "Forum Thread", tab: .forums)
						self.forum = forum
						self.post = .init(forType: .forumPost(forum.forumID.uuidString))
						if cat.count > 0 {
							category = cat[0]
						}
						else {
							category = CategoryData(categoryID: UUID(), title: "Unknown Category", 
									isRestricted: false, numThreads: 0, forumThreads: nil)
						}
						paginator = .init(currentPage: forum.start / forum.limit, 
								totalPages: (forum.totalPosts + forum.limit - 1) / forum.limit) { pageIndex in
							"/forum/\(forum.forumID)?start=\(pageIndex * forum.limit)&limit=\(forum.limit)"
						}
					}
				}
				let ctx = try ForumPageContext(req, forum: forum, cat: cats)
				return req.view.render("Forums/forum", ctx)
			}
		}
    }
    
    /// Returns a view with a form for editing a forum's title.
    func forumEditViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
    		throw "Invalid forum ID"
    	}
		return apiQuery(req, endpoint: "/forum/\(forumID)").throwingFlatMap { response in
 			let forum = try response.content.decode(ForumData.self)
			struct ForumEditPageContext : Encodable {
				var trunk: TrunkContext
				var forum: ForumData
				var post: MessagePostContext
				
				init(_ req: Request, forum: ForumData) throws {
					trunk = .init(req, title: "Edit Forum Thread", tab: .forums)
					self.forum = forum
					self.post = .init(forType: .forumEdit(forum))
				}
			}
			var ctx = try ForumEditPageContext(req, forum: forum)
    		if ctx.trunk.userID != forum.creator.userID {
    			ctx.post.authorName = forum.creator.username
    		}
			return req.view.render("Forums/forumEdit", ctx)
		}
    }
    
    /// Handles the POST that edits a forum's title.
    func forumEditTitlePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
    		throw "While editing forum title: Invalid forum ID"
    	}
		let formStruct = try req.content.decode(MessagePostFormContent.self)
		guard let newForumTitle = formStruct.forumTitle,
				let urlPathSafeForumTitle = newForumTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
			throw "While editing forum title, no new forum title specified."
		}
 		return apiQuery(req, endpoint: "/forum/\(forumID)/rename/\(urlPathSafeForumTitle)", method: .POST).flatMapThrowing { response in
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

	/// Handles the POST of a delete request for a forum.
    func forumDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
    		throw "While deleting forum: Invalid forum ID"
    	}
    	return apiQuery(req, endpoint: "/forum/\(forumID)", method: .DELETE).map { response in
    		return response.status
    	}
    }
    
	// POST handler for creating a new forum post.
    func forumPostPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
    		throw "Invalid forum ID"
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images)
		return apiQuery(req, endpoint: "/forum/\(forumID)/create", method: .POST, beforeSend: { req throws in
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
    
    /// Shows a page that lets a user file a report against a Forum (NOT a forum's posts, the forum itself, which should mean the forum's title,
    /// but users will likely assume means 'the whole forum is bad'.
	func forumReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing forum_id parameter.")
    	}
		let ctx = try ReportPageContext(req, forumID: forumID)
    	return req.view.render("reportCreate", ctx)
    }
    
    /// Handles the POST of a report on a forum
	func forumReportPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing forum_id parameter.")
    	}
		let postStruct = try req.content.decode(ReportData.self)
 		return apiQuery(req, endpoint: "/forum/\(forumID)/report", method: .POST, beforeSend: { req throws in
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

// MARK: - Posts

    func forumPostLikeActionHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
		return try forumPostPostReactionHandler(req, reactionType: "like")
    }
    func forumPostLaughActionHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
		return try forumPostPostReactionHandler(req, reactionType: "laugh")
    }
    func forumPostLoveActionHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
		return try forumPostPostReactionHandler(req, reactionType: "love")
    }
    func forumPostUnreactActionHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
		return try forumPostPostReactionHandler(req, reactionType: "unreact")
    }
    
    func forumPostPostReactionHandler(_ req: Request, reactionType: String) throws -> EventLoopFuture<PostData> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)/\(reactionType)", method: .POST).flatMapThrowing { response in
 			let forumPost = try response.content.decode(PostData.self)
    		return forumPost
    	}
    }

    // Shows the page for editing a post.
	func forumPostEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter--we can't tell which post you want to edit.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)").throwingFlatMap { response in
 			let post = try response.content.decode(PostDetailData.self)
     		struct ForumPostEditPageContext : Encodable {
				var trunk: TrunkContext
    			var post: MessagePostContext
    			
    			init(_ req: Request, post: PostDetailData) throws {
    				trunk = .init(req, title: "Edit Forum Post", tab: .forums)
    				self.post = .init(forType: .forumPostEdit(post))
    			}
    		}
    		var ctx = try ForumPostEditPageContext(req, post: post)
    		if ctx.trunk.userID != post.author.userID {
    			ctx.post.authorName = post.author.username
    		}
			return req.view.render("Forums/forumPostEdit", ctx)
    	}
    }
    
    // ?? Yeah. Reading the fn name right to left:
    //	--> "The handler that gets called when you POST the results of an edit to an existing post in a forum"
    func forumPostEditPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
				ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
				ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
				ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4)].compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images)
 		return apiQuery(req, endpoint: "/forum/post/\(postID)/update", method: .POST, beforeSend: { req throws in
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
    
	/// Handles the POST of a delete request for a forum post.
    func forumPostDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)", method: .DELETE).map { response in
    		return response.status
    	}
    }
    
	/// Shows a page that lets a user file a report against a forum post.
	func forumPostReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
		let ctx = try ReportPageContext(req, postID: postID)
    	return req.view.render("reportCreate", ctx)
    }
    
    /// Handles the POST of a report on a forum post.
	func forumPostReportPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
		let postStruct = try req.content.decode(ReportData.self)
 		return apiQuery(req, endpoint: "/forum/post/\(postID)/report", method: .POST, beforeSend: { req throws in
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
    
    /// Returns a `PostDetailData` on a specific post. This struct gives more detail on like counts.
    func forumGetPostDetails(_ req: Request) throws -> EventLoopFuture<PostDetailData> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
 		return apiQuery(req, endpoint: "/forum/post/\(postID)").flatMapThrowing { response in
			if response.status.code < 300 {
 				let detailData = try response.content.decode(PostDetailData.self)
				return detailData
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
    }

	func forumGetUserMentions(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/post/search?mentionself=true").throwingFlatMap { response in
			let postData = try response.content.decode(PostSearchData.self)
     		struct ForumUserMentionPageContext : Encodable {
				var trunk: TrunkContext
    			var postSearch: PostSearchData
				var paginator: PaginatorContext
    			
    			init(_ req: Request, posts: PostSearchData) throws {
    				trunk = .init(req, title: "User Mentions", tab: .forums)
    				self.postSearch = posts
    				let userID = trunk.userID
					paginator = .init(currentPage: posts.start / posts.limit, 
							totalPages: (Int(posts.totalPosts) + posts.limit - 1) / posts.limit) { pageIndex in
						"/forum/post/search?mentionid=\(userID)&start=\(pageIndex * posts.limit)&limit=\(posts.limit)"
					}
    			}
    		}
    		let ctx = try ForumUserMentionPageContext(req, posts: postData)
			return req.view.render("Forums/forumMentions", ctx)
		}
	}

}

    

