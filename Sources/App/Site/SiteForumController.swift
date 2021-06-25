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
		privateRoutes.get("forumpost", "edit", postIDParam, use: forumPostEditPageHandler)
		privateRoutes.post("forumpost", "edit", postIDParam, use: forumPostEditPostHandler)
		privateRoutes.post("forumpost", postIDParam, "delete", use: forumPostDeleteHandler)
        privateRoutes.get("forumpost", "report", postIDParam, use: forumPostReportPageHandler)
        privateRoutes.post("forumpost", "report", postIDParam, use: forumPostReportPostHandler)
        privateRoutes.get("forumpost", postIDParam, use: forumGetPostDetails)
	}

// MARK: - Forums
	// Shows a list of forum categories
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
    				trunk = .init(req, title: "Forum Threads")
    				self.forums = forums
					paginator = .init(currentPage: start / limit, totalPages: (Int(forums.numThreads) + limit - 1) / limit) { pageIndex in
						"/forums/\(forums.categoryID)?start=\(pageIndex * limit)&limit=\(limit)"
					}
    			}
    		}
    		let ctx = try ForumsPageContext(req, forums: forums, start: start, limit: limit)
			return req.view.render("forums", ctx)
    	}
    }
    
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
						trunk = .init(req, title: "Forum Thread")
						self.forum = forum
						self.post = .init(withForumID: forum.forumID.uuidString)
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
				return req.view.render("forum", ctx)
			}
		}
    }
    
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
					trunk = .init(req, title: "Create New Forum")
					self.categoryID = catID
					self.post = .init(withCategoryID: catID)
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
			return req.view.render("forumCreate", ctx)
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
		let postContent = PostContentData(text: postStruct.postText, images: images)
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
		let postContent = PostContentData(text: postStruct.postText, images: images)
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
    				trunk = .init(req, title: "Edit Forum Post")
    				self.post = .init(withForumPost: post)
    			}
    		}
    		let ctx = try ForumPostEditPageContext(req, post: post)
			return req.view.render("forumPostEdit", ctx)
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
		let postContent = PostContentData(text: postStruct.postText, images: images)
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

    func forumPostDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)", method: .DELETE).map { response in
    		return response.status
    	}
    }
    
	func forumPostReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
		let ctx = try ReportPageContext(req, postID: postID)
    	return req.view.render("reportCreate", ctx)
    }
    
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
    
    func forumGetPostDetails(_ req: Request) throws -> EventLoopFuture<PostDetailData> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
 		return apiQuery(req, endpoint: "/forum/post/\(postID)").flatMapThrowing { response in
 			let detailData = try response.content.decode(PostDetailData.self)
			if response.status.code < 300 {
				return detailData
			}
			else {
				// This is that thing where we decode an error response from the API and then make it into an exception.
				let error = try response.content.decode(ErrorResponse.self)
				throw error
			}
		}
    }

}

    

