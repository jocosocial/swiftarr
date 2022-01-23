import Vapor
import Crypto
import FluentSQL

// Used to show a single forum on a page
struct ForumPageContext : Encodable {
	var trunk: TrunkContext
	var forum: ForumData
	var post: MessagePostContext
	var category: CategoryData
	var paginator: PaginatorContext
	
	init(_ req: Request, forum: ForumData, cat: [CategoryData]) throws {
		trunk = .init(req, title: "Forum Thread", tab: .forums, search: "Search")
		self.forum = forum
		self.post = .init(forType: .forumPost(forum.forumID.uuidString))
		if cat.count > 0 {
			category = cat[0]
		}
		else {
			category = CategoryData(categoryID: UUID(), title: "Unknown Category", 
					isRestricted: false, numThreads: 0, forumThreads: nil)
		}
		paginator = PaginatorContext(forum.paginator) { pageIndex in
			"/forum/\(forum.forumID)?start=\(pageIndex * forum.paginator.limit)&limit=\(forum.paginator.limit)"
		}
	}
}

// Used for Forum Search, Favorite Forums, and Forums You Created pages.
struct ForumsSearchPageContext : Encodable {
	var trunk: TrunkContext
	var forums: ForumSearchData
	var paginator: PaginatorContext
	var filterDescription: String
	var searchType: SearchType
	
	enum SearchType: String, Codable {
		case owned
		case favorite
		case textSearch
	}
	
	init(_ req: Request, forums: ForumSearchData, searchType: SearchType, filterDesc: String) throws {
		var title: String
		switch searchType {
			case .owned: title = "Forums You Created"
			case .favorite: title = "Favorite Forums"
			case .textSearch: title = "Forum Search"
		}
		trunk = .init(req, title: title, tab: .forums, search: "Search")
		self.forums = forums
		self.searchType = searchType
		paginator = .init(forums.paginator) { pageIndex in
			"/forum/favorites?start=\(pageIndex * forums.paginator.limit)&limit=\(forums.paginator.limit)"
		}
		filterDescription = filterDesc
	}
}

// Matches the URL Query options for `/api/v3/forum/post/search`
struct ForumPostSearchQueryOptions: Content {
	var search: String?
	var hashtag: String?
	var mentionname: String?
	var mentionid: UUID?
	var mentionself: Bool?
	var ownreacts: Bool?
	var byself: Bool?
	var bookmarked: Bool?
	var forum: UUID?
	var category: UUID?
	var start: Int?
	var limit: Int?
	
	func buildQuery(baseURL: String, startOffset: Int?) -> String? {
		guard var components = URLComponents(string: baseURL) else {
			return nil
		}
		var elements = [URLQueryItem]()
		if let search = search { elements.append(URLQueryItem(name: "search", value: search)) }
		if let hashtag = hashtag { elements.append(URLQueryItem(name: "hashtag", value: hashtag)) }
		if let mentionname = mentionname { elements.append(URLQueryItem(name: "mentionname", value: mentionname)) }
		if let mentionid = mentionid { elements.append(URLQueryItem(name: "mentionid", value: mentionid.uuidString)) }
		if let _ = mentionself { elements.append(URLQueryItem(name: "mentionself", value: "true")) }
		if let _ = ownreacts { elements.append(URLQueryItem(name: "ownreacts", value: "true")) }
		if let _ = byself { elements.append(URLQueryItem(name: "byself", value: "true")) }
		if let _ = bookmarked { elements.append(URLQueryItem(name: "bookmarked", value: "true")) }
		if let forum = forum { elements.append(URLQueryItem(name: "forum", value: forum.uuidString)) }
		if let category = category { elements.append(URLQueryItem(name: "category", value: category.uuidString)) }
		let newOffset = max(startOffset ?? start ?? 0, 0)
		if newOffset != 0 { elements.append(URLQueryItem(name: "start", value: String(newOffset))) }
		if let limit = limit { elements.append(URLQueryItem(name: "limit", value: String(limit))) }

		components.queryItems = elements
		return components.string
	}
}

// Used for Post Search, BookmaredPosts, and Posts Mentioning You pages.
struct PostSearchPageContext : Encodable {
	var trunk: TrunkContext
	var postSearch: PostSearchData
	var searchType: SearchType
	var paginator: PaginatorContext
	var filterDescription: String
	
	enum SearchType: String, Codable {
		case userMentions
		case owned
		case favorite
		case textSearch
		case direct				// Request has all search params, see /api/v3/forum/post/search
	}
	
	init(_ req: Request, posts: PostSearchData, searchType: SearchType, searchString: String = "") throws {
		var title: String
		var paginatorClosure: (Int) -> String
		switch searchType {
			case .userMentions:
				title = "Posts Mentioning You"
				filterDescription = "\(posts.totalPosts) Posts Mentioning You"
				paginatorClosure = { pageIndex in
					"/forumpost/mentions?start=\(pageIndex * posts.limit)&limit=\(posts.limit)"
				}
			case .owned:
				title = "Your Forum Posts"
				filterDescription = "Your \(posts.totalPosts) Posts"
				paginatorClosure = { pageIndex in
					"/forumpost/owned?start=\(pageIndex * posts.limit)&limit=\(posts.limit)"
				}
			case .favorite:
				title = "Favorite Posts"
				filterDescription = "\(posts.totalPosts) Favorite Posts"
				paginatorClosure = { pageIndex in
					"/forumpost/favorite?start=\(pageIndex * posts.limit)&limit=\(posts.limit)"
				}
			case .textSearch:
				title = "Forum Post Search"
				filterDescription = "\(posts.totalPosts) Posts with \"\(searchString)\""
				paginatorClosure = { pageIndex in
					"/forum/search?search=\(searchString)&searchType=posts&start=\(pageIndex * posts.limit)&limit=\(posts.limit)"
				}
			case .direct:
				let searchParams = try req.query.decode(ForumPostSearchQueryOptions.self)
				filterDescription = searchParams.bookmarked != nil ? "Bookmarked posts" : "Posts" +
						(searchParams.byself != nil ? " by you" : "") +
						(searchParams.ownreacts != nil ? " you reacted to" : "") +
						(searchParams.mentionself != nil ? " mentioning you" : "")
				if let name = searchParams.mentionname {
					filterDescription.append(" mentioning \"@\(name)\"")
				}
				if let tag = searchParams.hashtag {
					filterDescription.append(" with hashtag \"#\(tag)\"")
				}
				if let searchStr = searchParams.search {
					filterDescription.append(" containing \"\(searchStr)\"")
				}
				title = "Forum Post Search"
				paginatorClosure = { pageIndex in
					let limit = searchParams.limit ?? 50
					return searchParams.buildQuery(baseURL: "/forumpost/search", startOffset: pageIndex * limit) ?? "/"
				}
		}
		trunk = .init(req, title: title, tab: .forums, search: "Search")
		self.postSearch = posts
		self.searchType = searchType
		paginator = .init(start: posts.start, total: Int(posts.totalPosts), limit: posts.limit, urlForPage: paginatorClosure)
	}
}

struct SiteForumController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.		
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .forums))
		globalRoutes.get("forums", use: forumCategoriesPageHandler)
		globalRoutes.get("forums", categoryIDParam, use: forumPageHandler)
		globalRoutes.get("forum", forumIDParam, use: forumThreadPageHandler)
		globalRoutes.get("forum", "containingpost", postIDParam, use: forumThreadFromPostPageHandler)

		// Routes for non-shareable content. If you're not logged in we failscreen.
		let privateRoutes = getPrivateRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .forums))
		privateRoutes.post("forumpost", postIDParam, "like", use: forumPostLikeActionHandler)
		privateRoutes.post("forumpost", postIDParam, "laugh", use: forumPostLaughActionHandler)
		privateRoutes.post("forumpost", postIDParam, "love", use: forumPostLoveActionHandler)
		privateRoutes.post("forumpost", postIDParam, "unreact", use: forumPostUnreactActionHandler)
		privateRoutes.delete("forumpost", postIDParam, "like", use: forumPostUnreactActionHandler)
		privateRoutes.delete("forumpost", postIDParam, "laugh", use: forumPostUnreactActionHandler)
		privateRoutes.delete("forumpost", postIDParam, "love", use: forumPostUnreactActionHandler)

		privateRoutes.get("forums", categoryIDParam, "createForum", use: forumCreateViewHandler)
		privateRoutes.post("forums", categoryIDParam, "createForum", use: forumCreateForumPostHandler)

		privateRoutes.post("forum", forumIDParam, "create", use: forumPostPostHandler)
		privateRoutes.get("forum", forumIDParam, "edit", use: forumEditViewHandler)
		privateRoutes.post("forum", forumIDParam, "edit", use: forumEditTitlePostHandler)
		privateRoutes.post("forum", forumIDParam, "delete", use: forumDeleteHandler)
		
		privateRoutes.get("forum", "report", forumIDParam, use: forumReportPageHandler)
		privateRoutes.post("forum", "report", forumIDParam, use: forumReportPostHandler)
		
		privateRoutes.get("forum", "search", use: forumSearchPageHandler)
		privateRoutes.get("forum", "favorites", use: forumFavoritesPageHandler)
		privateRoutes.post("forum", "favorite", forumIDParam, use: forumAddFavoritePostHandler)
		privateRoutes.delete("forum", "favorite", forumIDParam, use: forumRemoveFavoritePostHandler)
		privateRoutes.get("forum", "owned", use: forumsByUserPageHandler)

		privateRoutes.get("forumpost", "edit", postIDParam, use: forumPostEditPageHandler)
		privateRoutes.post("forumpost", "edit", postIDParam, use: forumPostEditPostHandler)
		privateRoutes.post("forumpost", postIDParam, "delete", use: forumPostDeleteHandler)
		privateRoutes.get("forumpost", "report", postIDParam, use: forumPostReportPageHandler)
		privateRoutes.post("forumpost", "report", postIDParam, use: forumPostReportPostHandler)
		privateRoutes.get("forumpost", postIDParam, "details", use: forumGetPostDetails)
		privateRoutes.get("forumpost", "mentions", use: userMentionsViewHandler)
		privateRoutes.get("forumpost", "favorite", use: favoritePostsViewHandler)
		privateRoutes.get("forumpost", "owned", use: forumPostsByUserViewHandler)
		privateRoutes.post("forumpost", "favorite", postIDParam, use: forumPostAddBookmarkPostHandler)
		privateRoutes.delete("forumpost", "favorite", postIDParam, use: forumPostRemoveBookmarkPostHandler)
		privateRoutes.get("forumpost", "search", use: forumPostSearchPageHandler)
	}

// Note: These groupings are roughly based on what type of URL parameters each method takes to identify its target:
// category/forum/post
// MARK: - Categories

	// GET /forums
	//
	// Shows a list of forum categories
    func forumCategoriesPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/categories").throwingFlatMap { response in
 			let categories = try response.content.decode([CategoryData].self)
     		struct ForumCatPageContext : Encodable {
				var trunk: TrunkContext
    			var categories: [CategoryData]
    			
    			init(_ req: Request, cats: [CategoryData]) throws {
    				trunk = .init(req, title: "Forum Categories", tab: .forums, search: "Search")
    				self.categories = cats
    			}
    		}
    		let ctx = try ForumCatPageContext(req, cats: categories)
			return req.view.render("Forums/forumCategories", ctx)
    	}
    }
    
    // GET /forums/:cat_ID
    // 
    // Shows a page of forum threads in a category
    func forumPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let catID = req.parameters.get(categoryIDParam.paramString)?.percentEncodeFilePathEntry() else {
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
    				trunk = .init(req, title: "Forum Threads", tab: .forums, search: "Search")
    				self.forums = forums
					paginator = .init(start: start, total: Int(forums.numThreads), limit: limit) { pageIndex in
						"/forums/\(forums.categoryID)?start=\(pageIndex * limit)&limit=\(limit)"
					}
    			}
    		}
    		let ctx = try ForumsPageContext(req, forums: forums, start: start, limit: limit)
			return req.view.render("Forums/forums", ctx)
    	}
    }
    
    // GET /forums/:cat_ID/createForum
    //
    // Shows the page for creating a new forum thread in a category.
    func forumCreateViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let catID = req.parameters.get(categoryIDParam.paramString)?.percentEncodeFilePathEntry() else {
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
					trunk = .init(req, title: "Create New Forum", tab: .forums, search: "Search")
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
    
	// POST /forums/:cat_ID/createForum
    //
    // POST handler for creating a new forum in a category.
    func forumCreateForumPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let catID = req.parameters.get(categoryIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid category ID"
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		guard let forumTitle = postStruct.forumTitle else {
			throw "Forum must have a ttile"
		}
		let postContent = postStruct.buildPostContentData()
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

	//	GET /forum/:forum_ID
	//
    // Shows an individual forum thread
    func forumThreadPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid forum category ID"
    	}
		return apiQuery(req, endpoint: "/forum/\(forumID)").throwingFlatMap { response in
 			let forum = try response.content.decode(ForumData.self)
 			return apiQuery(req, endpoint: "/forum/categories?cat=\(forum.categoryID)", 
 					passThroughQuery: false).throwingFlatMap { catResponse in
 				let cats = try catResponse.content.decode([CategoryData].self)
				let ctx = try ForumPageContext(req, forum: forum, cat: cats)
				return req.view.render("Forums/forum", ctx)
			}
		}
    }
    
	//	GET /forum/containingpost/:post_ID
	//
    // Shows an individual forum thread, referenced by a post *in* that thread.
    func forumThreadFromPostPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid post ID"
    	}
		return apiQuery(req, endpoint: "/forum/post/\(postID)/forum").throwingFlatMap { response in
 			let forum = try response.content.decode(ForumData.self)
 			return apiQuery(req, endpoint: "/forum/categories?cat=\(forum.categoryID)", 
 					passThroughQuery: false).throwingFlatMap { catResponse in
 				let cats = try catResponse.content.decode([CategoryData].self)
				let ctx = try ForumPageContext(req, forum: forum, cat: cats)
				return req.view.render("Forums/forum", ctx)
			}
		}
    }    
    
    // GET /forum/:forum_ID/edit 
    // 
    // Returns a view with a form for editing a forum's title.
    func forumEditViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid forum ID"
    	}
		return apiQuery(req, endpoint: "/forum/\(forumID)").throwingFlatMap { response in
 			let forum = try response.content.decode(ForumData.self)
			struct ForumEditPageContext : Encodable {
				var trunk: TrunkContext
				var forum: ForumData
				var post: MessagePostContext
				
				init(_ req: Request, forum: ForumData) throws {
					trunk = .init(req, title: "Edit Forum Thread", tab: .forums, search: "Search")
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
    
    // POST /forum/:forum_ID/edit
    // 
    // Handles the POST that edits a forum's title.
    func forumEditTitlePostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
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

	// POST /forum/:forum_ID/delete
	//
	// Handles a delete request for a forum.
    func forumDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "While deleting forum: Invalid forum ID"
    	}
    	return apiQuery(req, endpoint: "/forum/\(forumID)", method: .DELETE).map { response in
    		return response.status
    	}
    }
    
    // POST /forum/:forum_ID/create
    // 
	// POST handler for creating a new forum post.
    func forumPostPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
    		throw "Invalid forum ID"
    	}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = postStruct.buildPostContentData()
		return apiQuery(req, endpoint: "/forum/\(forumID)/create", method: .POST, beforeSend: { req throws in
			try req.content.encode(postContent)
		}).flatMapThrowing { response in
			return Response(status: .created)
		}
    }
    
    // GET /forum/report/:forum_ID
    //
    // Shows a page that lets a user file a report against a Forum (NOT a forum's posts, the forum itself, 
    // which should mean the forum's title, but users will likely assume means 'the whole forum is bad'.
	func forumReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing forum_id parameter.")
    	}
		let ctx = try ReportPageContext(req, forumID: forumID)
    	return req.view.render("reportCreate", ctx)
    }
    
    // POST /forum/report/:forum_ID
    //
    // Handles the POST of a report on a forum.
	func forumReportPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing forum_id parameter.")
    	}
		let postStruct = try req.content.decode(ReportData.self)
 		return apiQuery(req, endpoint: "/forum/\(forumID)/report", method: .POST, beforeSend: { req throws in
			try req.content.encode(postStruct)
		}).flatMapThrowing { response in
			return Response(status: .created)
		}
    }
    
    // GET /forum/favorites
    //
    // Displays a list of the user's favorited forums.
    // URL QueryParameters start, limit are passed through.
	func forumFavoritesPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/favorites").throwingFlatMap { response in
 			let forums = try response.content.decode(ForumSearchData.self)    	
    		let ctx = try ForumsSearchPageContext(req, forums: forums, searchType: .favorite, filterDesc: "\(forums.paginator.total) Favorites")
			return req.view.render("Forums/forumsList", ctx)
    	}
	}
	
    // POST /forum/favorite/:forum_ID
    //
    // Adds a forum to the user's favorites list.
	func forumAddFavoritePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing forum_id parameter.")
    	}
		return apiQuery(req, endpoint: "/forum/\(forumID)/favorite", method: .POST).flatMapThrowing { response in
			return .created
		}
	}
	
    // DELETE /forum/favorite/:forum_ID
    //
    // Removes a forum from the user's favorites list.
	func forumRemoveFavoritePostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing forum_id parameter.")
    	}
		return apiQuery(req, endpoint: "/forum/\(forumID)/favorite/remove", method: .POST).flatMapThrowing { response in
			return .noContent
		}
	}
	
    // GET /forum/owned
    //
    // Shows the forums the current user has created.
	func forumsByUserPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/owner").throwingFlatMap { response in
 			let forums = try response.content.decode(ForumSearchData.self)    	
    		let ctx = try ForumsSearchPageContext(req, forums: forums, searchType: .owned, filterDesc: "Your \(forums.paginator.total) Forums")
			return req.view.render("Forums/forumsList", ctx)
    	}
	}

// MARK: - Posts

	// POST /forumpost/:forumpost_ID/like and friends
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
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)/\(reactionType)", method: .POST).flatMapThrowing { response in
 			let forumPost = try response.content.decode(PostData.self)
    		return forumPost
    	}
    }

	// GET /forumpost/edit/:forumpost_ID
	// 
    // Shows the page for editing a post.
	func forumPostEditPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing post_id parameter--we can't tell which post you want to edit.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)").throwingFlatMap { response in
 			let post = try response.content.decode(PostDetailData.self)
     		struct ForumPostEditPageContext : Encodable {
				var trunk: TrunkContext
    			var post: MessagePostContext
    			
    			init(_ req: Request, post: PostDetailData) throws {
    				trunk = .init(req, title: "Edit Forum Post", tab: .forums, search: "Search")
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
    
	// POST /forumpost/edit/:forumpost_ID
	// 
    // ?? Yeah. Reading the fn name right to left:
    //	--> "The handler that gets called when you POST the results of an edit to an existing post in a forum"
    func forumPostEditPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
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
    
	// POST /forumpost/:forumpost_ID/delete
	// 
	// Handles the POST of a delete request for a forum post.
    func forumPostDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)", method: .DELETE).map { response in
    		return response.status
    	}
    }
    
    // GET /forumpost/report/:forumpost_ID
    //
	// Shows a page that lets a user file a report against a forum post.
	func forumPostReportPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
    	guard let postID = req.parameters.get(postIDParam.paramString) else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
		let ctx = try ReportPageContext(req, postID: postID)
    	return req.view.render("reportCreate", ctx)
    }
    
    // POST /forumpost/report/:forumpost_ID
    //
    // Handles the POST of a report on a forum post.
	func forumPostReportPostHandler(_ req: Request) throws -> EventLoopFuture<Response> {
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
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
    
    // GET /forumpost/:forumpost_ID
    //
    // Returns a `PostDetailData` on a specific post. This struct gives more detail on like counts.
    func forumGetPostDetails(_ req: Request) throws -> EventLoopFuture<PostDetailData> {
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
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

    // GET /forumpost/mentions
    //
    // Gets forum posts that @mention the current user.
	func userMentionsViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/post/search?mentionself=true").throwingFlatMap { response in
			let postData = try response.content.decode(PostSearchData.self)
    		let ctx = try PostSearchPageContext(req, posts: postData, searchType: .userMentions)
			return req.view.render("Forums/forumPostsList", ctx)
		}
	}
	
    // GET /forumpost/favorite
    //
    // Gets forum posts that the user has favorited (aka bookmarked).
	func favoritePostsViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/post/search?bookmarked=true").throwingFlatMap { response in
			let postData = try response.content.decode(PostSearchData.self)
    		let ctx = try PostSearchPageContext(req, posts: postData, searchType: .favorite)
			return req.view.render("Forums/forumPostsList", ctx)
		}
	}
	
    // GET /forumpost/owned
    //
    // Gets forum posts that the user authored.
	func forumPostsByUserViewHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/post/search?byself=true").throwingFlatMap { response in
			let postData = try response.content.decode(PostSearchData.self)
    		let ctx = try PostSearchPageContext(req, posts: postData, searchType: .owned)
			return req.view.render("Forums/forumPostsList", ctx)
		}
	}
	
	
	
    // POST /forumpost/favorite/:forumpost_ID
    //
    // The Web UI calls this 'favoriting' a post, but with the API nomenclature, you 'favorite' forums and 'bookmark' posts.
    // Anyway, the UI calls it favoriting because users might get confused with the difference between favoriting and bookmarking.
	func forumPostAddBookmarkPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)/bookmark", method: .POST).map { response in
    		return .ok
    	}
    }

    // DELETE /forumpost/favorite/:forumpost_ID
    //
    // The Web UI calls this 'favoriting' a post, but with the API nomenclature, you 'favorite' forums and 'bookmark' posts.
    // Anyway, the UI calls it favoriting because users might get confused with the difference between favoriting and bookmarking.
	func forumPostRemoveBookmarkPostHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
    	guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
            throw Abort(.badRequest, reason: "Missing post_id parameter.")
    	}
    	return apiQuery(req, endpoint: "/forum/post/\(postID)/bookmark/remove", method: .POST).map { response in
    		return .ok
    	}
    }

	
// MARK: - Search

    // GET /forum/search
    //
    // Shows results of forum or post searches from the header search bar.
	func forumSearchPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		struct FormData : Content {
			var search: String
			var searchType: String
		}
		let formData = try req.query.decode(FormData.self)
		if formData.searchType == "forums" {
			guard let pathSearch = formData.search.percentEncodeFilePathEntry() else {
				throw Abort(.badRequest, reason: "Invalid search string.")
			}
			return apiQuery(req, endpoint: "/forum/match/\(pathSearch)", passThroughQuery: false).throwingFlatMap { response in
				let responseData = try response.content.decode(ForumSearchData.self)
    			let ctx = try ForumsSearchPageContext(req, forums: responseData, searchType: .textSearch,
    					filterDesc: "\(responseData.paginator.total) Forums with \"\(formData.search)\"")
				return req.view.render("Forums/forumsList", ctx)
			}
		}
		else {
			// search for posts
			guard let querySearch = formData.search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
				throw Abort(.badRequest, reason: "Invalid search string.")
			}
			return apiQuery(req, endpoint: "/forum/post/search?search=\(querySearch)").throwingFlatMap { response in
				let responseData = try response.content.decode(PostSearchData.self)
    			let ctx = try PostSearchPageContext(req, posts: responseData, searchType: .textSearch, searchString: formData.search)
				return req.view.render("Forums/forumPostsList", ctx)
			}
		}
	}
	
    // GET /forumpost/search
    //
    // Shows results of searches for forum posts. Passes query parameters through to /api/v3/forum/post/search.
	func forumPostSearchPageHandler(_ req: Request) throws -> EventLoopFuture<View> {
		return apiQuery(req, endpoint: "/forum/post/search").throwingFlatMap { response in
			let responseData = try response.content.decode(PostSearchData.self)
			let ctx = try PostSearchPageContext(req, posts: responseData, searchType: .direct)
			return req.view.render("Forums/forumPostsList", ctx)
		}
	}

}


