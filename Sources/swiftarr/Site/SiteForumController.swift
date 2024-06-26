import Crypto
import FluentSQL
import Vapor

// Used to encode a Sort menu item for Leaf. Each instance of this struct has the user-readable name of the
// sort order and the URL to go to a view using that sort.
struct ForumsSortOrder: Encodable {
	var name: String  // User-visible name of the sort order
	var url: String  // URL to go to that switches the current search to the given sort order
	var active: Bool  // True if this is the currently active sort order for the results page

	// Uses the urlStr to determine the current sort, if specified in the query. If one is specified,
	// compares against `value` to determine if this is the currently active sort. If no sort is specified in the URL,
	// this is the current sort iff `isDefault` is true.
	init(urlStr: String, name: String, value: String, isDefault: Bool = false) {
		var components = URLComponents(string: urlStr) ?? URLComponents()
		var queryItems: [URLQueryItem] = components.queryItems ?? []
		let currentSort = queryItems.first { $0.name == "sort" }?.value
		queryItems = queryItems.filter { $0.name != "sort" }
		queryItems.append(URLQueryItem(name: "sort", value: value))
		components.queryItems = queryItems
		url = components.string ?? ""
		self.name = name
		active = currentSort == nil ? isDefault : currentSort == value
	}
}

// Used to show a single forum on a page
struct ForumPageContext: Encodable {
	var trunk: TrunkContext
	var forum: ForumData
	var post: MessagePostContext
	var category: CategoryData
	var paginator: PaginatorContext
	var pinnedPosts: [PostData]

	init(_ req: Request, forum: ForumData, cat: [CategoryData], pinnedPosts: [PostData] = []) throws {
		trunk = .init(req, title: "\(forum.title) | Forum Thread", tab: .forums)
		self.forum = forum
		self.post = .init(forType: .forumPost(forum.forumID.uuidString))
		if cat.count > 0 {
			category = cat[0]
		}
		else {
			category = CategoryData(
				categoryID: UUID(),
				title: "Unknown Category",
				purpose: "",
				isRestricted: false,
				isEventCategory: false,
				numThreads: 0,
				forumThreads: nil
			)
		}
		paginator = PaginatorContext(forum.paginator) { pageIndex in
			"/forum/\(forum.forumID)?start=\(pageIndex * forum.paginator.limit)&limit=\(forum.paginator.limit)"
		}
		self.pinnedPosts = pinnedPosts
	}
}

// The data from the search form passed in via the URL query to search methods
struct SearchFormData: Content {
	var searchType: String
	var search: String?
	var creator: String?
	var creatorid: String?
	var category: UUID?
	var forum: UUID?
}

// Used for Forum Search, Favorite Forums, Recent Forums and Forums You Created pages.
struct ForumsSearchPageContext: Encodable {
	var trunk: TrunkContext
	var forums: ForumSearchData
	var paginator: PaginatorContext
	var filterDescription: String
	var searchType: SearchType
	var sortOrders: [ForumsSortOrder]
	var formData: SearchFormData?
	var categoryData: CategoryData?

	enum SearchType: String, Codable {
		case owned  // Created by this user
		case favorite  // Favorited by this user
		case recent  // Recently viewed by this user
		case textSearch  // Searches title for string
		case mute  // Muted forums by this user
		case unread // Unread forums by this user
	}

	init(_ req: Request, forums: ForumSearchData, searchType: SearchType, filterDesc: String, formData: SearchFormData? = nil) throws {
		var title: String
		switch searchType {
			case .owned: title = "Forums You Created"
			case .favorite: title = "Favorite Forums"
			case .recent: title = "Recently Viewed"
			case .textSearch: title = "Forum Search"
			case .mute: title = "Muted Forums"
			case .unread: title = "Unread Forums"
		}
		trunk = .init(req, title: title, tab: .forums)
		self.forums = forums
		self.searchType = searchType
		guard var paginatorBase = URLComponents(string: req.url.string) else {
			throw Abort(.internalServerError, reason: "Paginator couldn't parse URL")
		}
		paginator = .init(forums.paginator) { pageIndex in
			var queryItems = paginatorBase.queryItems ?? []
			queryItems.removeAll { $0.name == "start" || $0.name == "limit" }
			queryItems.append(URLQueryItem(name: "start", value: "\(pageIndex * forums.paginator.limit)"))
			queryItems.append(URLQueryItem(name: "limit", value: "\(forums.paginator.limit)"))
			paginatorBase.queryItems = queryItems
			return paginatorBase.string ?? ""
		}
		self.formData = formData
		filterDescription = filterDesc
		if searchType == .recent {
			sortOrders = []
		}
		else {
			sortOrders = [
				.init(
					urlStr: req.url.string,
					name: "Most Recent Post",
					value: "update",
					isDefault: [.favorite, .textSearch].contains(searchType)
				),
				.init(urlStr: req.url.string, name: "Creation Time", value: "create"),
				.init(urlStr: req.url.string, name: "Title", value: "title", isDefault: searchType == .owned),
			]
		}
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
	var creatorid: UUID?

	func buildQuery(baseURL: String, startOffset: Int?) -> String? {
		guard var components = URLComponents(string: baseURL) else {
			return nil
		}
		var elements = [URLQueryItem]()
		if let search = search { elements.append(URLQueryItem(name: "search", value: search)) }
		if let hashtag = hashtag { elements.append(URLQueryItem(name: "hashtag", value: hashtag)) }
		if let mentionname = mentionname { elements.append(URLQueryItem(name: "mentionname", value: mentionname)) }
		if let mentionid = mentionid { elements.append(URLQueryItem(name: "mentionid", value: mentionid.uuidString)) }
		if let creatorid = creatorid { elements.append(URLQueryItem(name: "creatorid", value: creatorid.uuidString)) }
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
struct PostSearchPageContext: Encodable {
	var trunk: TrunkContext
	var postSearch: PostSearchData
	var searchType: SearchType
	var paginator: PaginatorContext
	var filterDescription: String
	var formData: SearchFormData?
	var categoryData: CategoryData?		// For showing the breadcrumbs on searches constrained to a cat/forum
	var forumData: ForumData?

	enum SearchType: String, Codable {
		case userMentions
		case owned
		case favorite
		case textSearch
		case direct  // Request has all search params, see /api/v3/forum/post/search
	}

	init(_ req: Request, posts: PostSearchData, searchType: SearchType, formData: SearchFormData? = nil) throws {
		var title: String
		var paginatorClosure: (Int) -> String
		switch searchType {
		case .userMentions:
			title = "Posts Mentioning You"
			filterDescription = "\(posts.paginator.total) Posts Mentioning You"
			paginatorClosure = { pageIndex in
				"/forumpost/mentions?start=\(pageIndex * posts.paginator.limit)&limit=\(posts.paginator.limit)"
			}
		case .owned:
			title = "Your Forum Posts"
			filterDescription = "Your \(posts.paginator.total) Posts"
			paginatorClosure = { pageIndex in
				"/forumpost/owned?start=\(pageIndex * posts.paginator.limit)&limit=\(posts.paginator.limit)"
			}
		case .favorite:
			title = "Favorite Posts"
			filterDescription = "\(posts.paginator.total) Favorite Posts"
			paginatorClosure = { pageIndex in
				"/forumpost/favorite?start=\(pageIndex * posts.paginator.limit)&limit=\(posts.paginator.limit)"
			}
		case .textSearch:
			title = "Forum Post Search"
			filterDescription = "\(posts.paginator.total) Posts with \"\(formData?.search ?? "search text")\""
			paginatorClosure = { pageIndex in
				"/forum/search?search=\(formData?.search ?? "")&searchType=posts&start=\(pageIndex * posts.paginator.limit)&limit=\(posts.paginator.limit)"
			}
		case .direct:
			let searchParams = try req.query.decode(ForumPostSearchQueryOptions.self)
			filterDescription =
				searchParams.bookmarked != nil
				? "Bookmarked posts"
				: "Posts" + (searchParams.byself != nil ? " by you" : "")
					+ (searchParams.ownreacts != nil ? " you reacted to" : "")
					+ (searchParams.mentionself != nil ? " mentioning you" : "")
			if let name = searchParams.mentionname {
				filterDescription.append(" mentioning \"@\(name)\"")
			}
			if let tag = searchParams.hashtag {
				filterDescription.append(" with hashtag \"#\(tag)\"")
			}
			if let searchStr = searchParams.search {
				filterDescription.append(" containing \"\(searchStr)\"")
			}
			if let creatorid = searchParams.creatorid, let creatingUser = req.userCache.getUser(creatorid) {	
				filterDescription.append(" created by \"@\(creatingUser.username)\"")
			}
			title = "Forum Post Search"
			paginatorClosure = { pageIndex in
				let limit = searchParams.limit ?? 50
				return searchParams.buildQuery(baseURL: "/forumpost/search", startOffset: pageIndex * limit) ?? "/"
			}
		}
		trunk = .init(req, title: title, tab: .forums)
		self.postSearch = posts
		self.searchType = searchType
		self.formData = formData
		paginator = .init(posts.paginator, urlForPage: paginatorClosure)
	}
}

struct SiteForumController: SiteControllerUtils {

	func registerRoutes(_ app: Application) throws {
		// Routes that require login but are generally 'global' -- Two logged-in users could share this URL and both see the content
		// Not for Seamails, pages for posting new content, mod pages, etc. Logged-out users given one of these links should get
		// redirect-chained through /login and back.
		let globalRoutes = getGlobalRoutes(app).grouped(DisabledSiteSectionMiddleware(feature: .forums))
		globalRoutes.get("forums", use: forumCategoriesPageHandler).destination("the forums")
		globalRoutes.get("forums", categoryIDParam, use: forumPageHandler).destination("this forum")
		globalRoutes.get("forum", forumIDParam, use: forumThreadPageHandler).destination("this forum thread")
		globalRoutes.get("forum", "containingpost", postIDParam, use: forumThreadFromPostPageHandler).destination("this forum thread")

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
		privateRoutes.get("forum", "mutes", use: forumMutesPageHandler)
		privateRoutes.post("forum", "mute", forumIDParam, use: forumAddMutePostHandler)
		privateRoutes.delete("forum", "mute", forumIDParam, use: forumRemoveMutePostHandler)
		privateRoutes.get("forum", "owned", use: forumsByUserPageHandler)
		privateRoutes.get("forum", "recent", use: forumRecentsPageHandler)
		privateRoutes.get("forum", "unread", use: forumUnreadPageHandler)
		privateRoutes.post("forum", "pin", forumIDParam, use: forumAddPinPostHandler)
		privateRoutes.delete("forum", "pin", forumIDParam, use: forumRemovePinPostHandler)

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
		privateRoutes.post("forumpost", "pin", postIDParam, use: forumPostAddPinHandler)
		privateRoutes.delete("forumpost", "pin", postIDParam, use: forumPostRemovePinHandler)
	}

	// Note: These groupings are roughly based on what type of URL parameters each method takes to identify its target:
	// category/forum/post
	// MARK: - Categories

	// GET /forums
	//
	// Shows a list of forum categories
	func forumCategoriesPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/categories")
		let categories = try response.content.decode([CategoryData].self)
		struct ForumCatPageContext: Encodable {
			var trunk: TrunkContext
			var categories: [CategoryData]

			init(_ req: Request, cats: [CategoryData]) throws {
				trunk = .init(req, title: "Forum Categories", tab: .forums)
				self.categories = cats
			}
		}
		let ctx = try ForumCatPageContext(req, cats: categories)
		return try await req.view.render("Forums/forumCategories", ctx)
	}

	// GET /forums/:cat_ID
	//
	// Shows a page of forum threads in a category
	func forumPageHandler(_ req: Request) async throws -> View {
		guard let catID = req.parameters.get(categoryIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid forum category ID"
		}
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...200)

		let response = try await apiQuery(req, endpoint: "/forum/categories/\(catID)")
		let forums = try response.content.decode(CategoryData.self)

		struct ForumsPageContext: Encodable {
			var trunk: TrunkContext
			var forums: CategoryData
			var paginator: PaginatorContext
			var sortOrders: [ForumsSortOrder]

			init(_ req: Request, forums: CategoryData, start: Int, limit: Int) throws {
				trunk = .init(req, title: "\(forums.title) | Forum Threads", tab: .forums)
				self.forums = forums
				paginator = .init(start: start, total: Int(forums.numThreads), limit: limit) { pageIndex in
					"/forums/\(forums.categoryID)?start=\(pageIndex * limit)&limit=\(limit)"
				}

				sortOrders = [
					.init(
						urlStr: req.url.string,
						name: "Most Recent Post",
						value: "update",
						isDefault: !forums.isEventCategory
					),
					.init(urlStr: req.url.string, name: "Creation Time", value: "create"),
					.init(urlStr: req.url.string, name: "Title", value: "title"),
				]
				if forums.isEventCategory {
					sortOrders.insert(
						ForumsSortOrder(urlStr: req.url.string, name: "Event Time", value: "event", isDefault: true),
						at: 0
					)
				}
			}
		}
		let ctx = try ForumsPageContext(req, forums: forums, start: start, limit: limit)
		return try await req.view.render("Forums/forums", ctx)
	}

	// GET /forums/:cat_ID/createForum
	//
	// Shows the page for creating a new forum thread in a category.
	func forumCreateViewHandler(_ req: Request) async throws -> View {
		guard let catID = req.parameters.get(categoryIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid category ID"
		}
		let catResponse = try await apiQuery(req, endpoint: "/forum/categories?cat=\(catID)")
		let cats = try catResponse.content.decode([CategoryData].self)
		struct ForumCreateContext: Encodable {
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
					category = CategoryData(
						categoryID: UUID(),
						title: "Unknown Category",
						purpose: "",
						isRestricted: false,
						isEventCategory: false,
						numThreads: 0,
						forumThreads: nil
					)
				}
			}
		}
		let ctx = try ForumCreateContext(req, catID: catID, cat: cats)
		return try await req.view.render("Forums/forumCreate", ctx)
	}

	// POST /forums/:cat_ID/createForum
	//
	// POST handler for creating a new forum in a category.
	func forumCreateForumPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let catID = req.parameters.get(categoryIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid category ID"
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		guard let forumTitle = postStruct.forumTitle else {
			throw "Forum must have a ttile"
		}
		let postContent = postStruct.buildPostContentData()
		let forumContent = ForumCreateData(title: forumTitle, firstPost: postContent)
		// https://github.com/jocosocial/swiftarr/issues/168
		// This marks the brand new forum as read for the user that created it.
		// It was considered by some to be "undesirable" for the forum that you just made to already
		// show up with a "1 post, 1 new" badge in the UI. I thought about doing this in the API
		// but I think it should stick to just creating the forum. By calling the /forum/:forumID
		// endpoint immediately afterward (with start and limits clamped down hard)
		// that will automatically generate a ForumReader pivot under the hood and mark the forum as read
		// before the users browser sends them back to the category forum list.
		// If we elect to do this in the API it would be trivial to generate and save the pivot there
		// instead.
		let newForumResponse = try await apiQuery(
			req,
			endpoint: "/forum/categories/\(catID)/create",
			method: .POST,
			encodeContent: forumContent
		)
		let newForum = try newForumResponse.content.decode(ForumData.self)
		try await apiQuery(req, endpoint: "/forum/\(newForum.forumID)?start=0&limit=1", passThroughQuery: false)
		return .created
	}

	// MARK: - Forums

	//	GET /forum/:forum_ID
	//
	// Shows an individual forum thread
	func forumThreadPageHandler(_ req: Request) async throws -> View {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid forum category ID"
		}
		let response = try await apiQuery(req, endpoint: "/forum/\(forumID)")
		let forum = try response.content.decode(ForumData.self)
		let catResponse = try await apiQuery(req, endpoint: "/forum/categories?cat=\(forum.categoryID)", passThroughQuery: false)
		let cats = try catResponse.content.decode([CategoryData].self)

		let pinnedPostsResponse = try await apiQuery(req, endpoint: "/forum/\(forum.forumID)/pinnedposts")
		let pinnedPosts = try pinnedPostsResponse.content.decode([PostData].self)

		let ctx = try ForumPageContext(req, forum: forum, cat: cats, pinnedPosts: pinnedPosts)
		return try await req.view.render("Forums/forum", ctx)
	}

	//	GET /forum/containingpost/:post_ID
	//
	// Shows an individual forum thread, referenced by a post *in* that thread.
	func forumThreadFromPostPageHandler(_ req: Request) async throws -> View {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid post ID"
		}
		let response = try await apiQuery(req, endpoint: "/forum/post/\(postID)/forum")
		let forum = try response.content.decode(ForumData.self)
		let catResponse = try await apiQuery(
			req,
			endpoint: "/forum/categories?cat=\(forum.categoryID)",
			passThroughQuery: false
		)
		let cats = try catResponse.content.decode([CategoryData].self)

		let pinnedPostsResponse = try await apiQuery(req, endpoint: "/forum/\(forum.forumID)/pinnedposts")
		let pinnedPosts = try pinnedPostsResponse.content.decode([PostData].self)

		let ctx = try ForumPageContext(req, forum: forum, cat: cats, pinnedPosts: pinnedPosts)
		return try await req.view.render("Forums/forum", ctx)
	}

	// GET /forum/:forum_ID/edit
	//
	// Returns a view with a form for editing a forum's title.
	func forumEditViewHandler(_ req: Request) async throws -> View {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid forum ID"
		}
		let response = try await apiQuery(req, endpoint: "/forum/\(forumID)")
		let forum = try response.content.decode(ForumData.self)
		struct ForumEditPageContext: Encodable {
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
		return try await req.view.render("Forums/forumEdit", ctx)
	}

	// POST /forum/:forum_ID/edit
	//
	// Handles the POST that edits a forum's title.
	func forumEditTitlePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "While editing forum title: Invalid forum ID"
		}
		let formStruct = try req.content.decode(MessagePostFormContent.self)
		guard let newForumTitle = formStruct.forumTitle,
			let urlPathSafeForumTitle = newForumTitle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
		else {
			throw "While editing forum title, no new forum title specified."
		}
		try await apiQuery(req, endpoint: "/forum/\(forumID)/rename/\(urlPathSafeForumTitle)", method: .POST)
		return .created
	}

	// POST /forum/:forum_ID/delete
	//
	// Handles a delete request for a forum.
	func forumDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "While deleting forum: Invalid forum ID"
		}
		let response = try await apiQuery(req, endpoint: "/forum/\(forumID)", method: .DELETE)
		return response.status
	}

	// POST /forum/:forum_ID/create
	//
	// POST handler for creating a new forum post.
	func forumPostPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw "Invalid forum ID"
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let postContent = postStruct.buildPostContentData()
		try await apiQuery(req, endpoint: "/forum/\(forumID)/create", method: .POST, encodeContent: postContent)
		return .created
	}

	// GET /forum/report/:forum_ID
	//
	// Shows a page that lets a user file a report against a Forum (NOT a forum's posts, the forum itself,
	// which should mean the forum's title, but users will likely assume means 'the whole forum is bad'.
	func forumReportPageHandler(_ req: Request) async throws -> View {
		guard let forumID = req.parameters.get(forumIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing forum_id parameter.")
		}
		let ctx = try ReportPageContext(req, forumID: forumID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /forum/report/:forum_ID
	//
	// Handles the POST of a report on a forum.
	func forumReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum_id parameter.")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/forum/\(forumID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}

	// POST /forum/favorite/:forum_ID
	//
	// Adds a forum to the user's favorites list.
	func forumAddFavoritePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/\(forumID)/favorite", method: .POST)
		return .created
	}

	// DELETE /forum/favorite/:forum_ID
	//
	// Removes a forum from the user's favorites list.
	func forumRemoveFavoritePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/\(forumID)/favorite/remove", method: .POST)
		return .noContent
	}

	// POST /forum/mute/:forum_ID
	//
	// Adds a forum to the user's mute list.
	func forumAddMutePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/\(forumID)/mute", method: .POST)
		return .created
	}

	// DELETE /forum/mute/:forum_ID
	//
	// Removes a forum from the user's mute list.
	func forumRemoveMutePostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/\(forumID)/mute/remove", method: .POST)
		return .noContent
	}

	// POST /forum/pin/:forum_ID
	//
	// Pin the forum to the category.
	func forumAddPinPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/\(forumID)/pin", method: .POST)
		return .created
	}

	// DELETE /forum/pin/:forum_ID
	//
	// Unpin the forum from the category.
	func forumRemovePinPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let forumID = req.parameters.get(forumIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing forum_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/\(forumID)/pin/remove", method: .POST)
		return .noContent
	}

	// MARK: - Posts

	// POST /forumpost/:forumpost_ID/like and friends
	func forumPostLikeActionHandler(_ req: Request) async throws -> PostData {
		return try await forumPostPostReactionHandler(req, reactionType: "like")
	}
	func forumPostLaughActionHandler(_ req: Request) async throws -> PostData {
		return try await forumPostPostReactionHandler(req, reactionType: "laugh")
	}
	func forumPostLoveActionHandler(_ req: Request) async throws -> PostData {
		return try await forumPostPostReactionHandler(req, reactionType: "love")
	}
	func forumPostUnreactActionHandler(_ req: Request) async throws -> PostData {
		return try await forumPostPostReactionHandler(req, reactionType: "unreact")
	}

	func forumPostPostReactionHandler(_ req: Request, reactionType: String) async throws -> PostData {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/forum/post/\(postID)/\(reactionType)", method: .POST)
		let forumPost = try response.content.decode(PostData.self)
		return forumPost
	}

	// GET /forumpost/edit/:forumpost_ID
	//
	// Shows the page for editing a post.
	func forumPostEditPageHandler(_ req: Request) async throws -> View {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter--we can't tell which post you want to edit.")
		}
		let response = try await apiQuery(req, endpoint: "/forum/post/\(postID)")
		let post = try response.content.decode(PostDetailData.self)
		struct ForumPostEditPageContext: Encodable {
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
		return try await req.view.render("Forums/forumPostEdit", ctx)
	}

	// POST /forumpost/edit/:forumpost_ID
	//
	// ?? Yeah. Reading the fn name right to left:
	//	--> "The handler that gets called when you POST the results of an edit to an existing post in a forum"
	func forumPostEditPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let postStruct = try req.content.decode(MessagePostFormContent.self)
		let images: [ImageUploadData] = [
			ImageUploadData(postStruct.serverPhoto1, postStruct.localPhoto1),
			ImageUploadData(postStruct.serverPhoto2, postStruct.localPhoto2),
			ImageUploadData(postStruct.serverPhoto3, postStruct.localPhoto3),
			ImageUploadData(postStruct.serverPhoto4, postStruct.localPhoto4),
		]
		.compactMap { $0 }
		let postContent = PostContentData(text: postStruct.postText ?? "", images: images)
		try await apiQuery(req, endpoint: "/forum/post/\(postID)/update", method: .POST, encodeContent: postContent)
		return .created
	}

	// POST /forumpost/:forumpost_ID/delete
	//
	// Handles the POST of a delete request for a forum post.
	func forumPostDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/forum/post/\(postID)", method: .DELETE)
		return response.status
	}

	// GET /forumpost/report/:forumpost_ID
	//
	// Shows a page that lets a user file a report against a forum post.
	func forumPostReportPageHandler(_ req: Request) async throws -> View {
		guard let postID = req.parameters.get(postIDParam.paramString) else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let ctx = try ReportPageContext(req, postID: postID)
		return try await req.view.render("reportCreate", ctx)
	}

	// POST /forumpost/report/:forumpost_ID
	//
	// Handles the POST of a report on a forum post.
	func forumPostReportPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let postStruct = try req.content.decode(ReportData.self)
		try await apiQuery(req, endpoint: "/forum/post/\(postID)/report", method: .POST, encodeContent: postStruct)
		return .created
	}

	// GET /forumpost/:forumpost_ID
	//
	// Returns a `PostDetailData` on a specific post. This struct gives more detail on like counts.
	func forumGetPostDetails(_ req: Request) async throws -> PostDetailData {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		let response = try await apiQuery(req, endpoint: "/forum/post/\(postID)")
		let detailData = try response.content.decode(PostDetailData.self)
		return detailData
	}

	// GET /forumpost/mentions
	//
	// Gets forum posts that @mention the current user.
	func userMentionsViewHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/post/search?mentionself=true")
		let postData = try response.content.decode(PostSearchData.self)
		let ctx = try PostSearchPageContext(req, posts: postData, searchType: .userMentions)
		return try await req.view.render("Forums/forumPostsList", ctx)
	}

	// GET /forumpost/favorite
	//
	// Gets forum posts that the user has favorited (aka bookmarked).
	func favoritePostsViewHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/post/search?bookmarked=true")
		let postData = try response.content.decode(PostSearchData.self)
		let ctx = try PostSearchPageContext(req, posts: postData, searchType: .favorite)
		return try await req.view.render("Forums/forumPostsList", ctx)
	}

	// GET /forumpost/owned
	//
	// Gets forum posts that the user authored.
	func forumPostsByUserViewHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/post/search?byself=true")
		let postData = try response.content.decode(PostSearchData.self)
		let ctx = try PostSearchPageContext(req, posts: postData, searchType: .owned)
		return try await req.view.render("Forums/forumPostsList", ctx)
	}

	// POST /forumpost/favorite/:forumpost_ID
	//
	// The Web UI calls this 'favoriting' a post, but with the API nomenclature, you 'favorite' forums and 'bookmark' posts.
	// Anyway, the UI calls it favoriting because users might get confused with the difference between favoriting and bookmarking.
	func forumPostAddBookmarkPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/post/\(postID)/bookmark", method: .POST)
		return .ok
	}

	// DELETE /forumpost/favorite/:forumpost_ID
	//
	// The Web UI calls this 'favoriting' a post, but with the API nomenclature, you 'favorite' forums and 'bookmark' posts.
	// Anyway, the UI calls it favoriting because users might get confused with the difference between favoriting and bookmarking.
	func forumPostRemoveBookmarkPostHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/post/\(postID)/bookmark/remove", method: .POST)
		return .ok
	}

	// POST /forumpost/pin/:forum_ID
	//
	// Pin the forum to the category.
	func forumPostAddPinHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/post/\(postID)/pin", method: .POST)
		return .created
	}

	// DELETE /forumpost/pin/:forum_ID
	//
	// Unpin the forum from the category.
	func forumPostRemovePinHandler(_ req: Request) async throws -> HTTPStatus {
		guard let postID = req.parameters.get(postIDParam.paramString)?.percentEncodeFilePathEntry() else {
			throw Abort(.badRequest, reason: "Missing post_id parameter.")
		}
		try await apiQuery(req, endpoint: "/forum/post/\(postID)/pin/remove", method: .POST)
		return .noContent
	}

	// MARK: - Search

	// GET /forum/search
	//
	// Shows results of forum or post searches from the header search bar.
	func forumSearchPageHandler(_ req: Request) async throws -> View {
		let formData = try req.query.decode(SearchFormData.self)
		if formData.searchType == "forums" {
			let response = try await apiQuery(req, endpoint: "/forum/search", passThroughQuery: true)
			let responseData = try response.content.decode(ForumSearchData.self)
			var filterDesc = "\(responseData.paginator.total) \(responseData.paginator.total == 1 ? "Forum" : "Forums")"
			if let creator = formData.creator {
				filterDesc.append(contentsOf: " by \(creator)")
			}
			if let _ = formData.creatorid, !responseData.forumThreads.isEmpty {
				filterDesc.append(contentsOf: " by \(responseData.forumThreads[0].creator.username)")
			}
			if let searchStr = formData.search {
				filterDesc.append(contentsOf: " with \"\(searchStr)\"")
			}
			var ctx = try ForumsSearchPageContext(req, forums: responseData, searchType: .textSearch, filterDesc: filterDesc, formData: formData)
			if let categoryID = formData.category {
				let catResponse = try await apiQuery(req, endpoint: "/forum/categories", query: [URLQueryItem(name: "cat", value: categoryID.uuidString)])
				let catInfo = try catResponse.content.decode([CategoryData].self)
				ctx.categoryData = catInfo.first
			}
			return try await req.view.render("Forums/forumsList", ctx)
		}
		else {
			// search for posts
			let response = try await apiQuery(req, endpoint: "/forum/post/search", passThroughQuery: true)
			let responseData = try response.content.decode(PostSearchData.self)
			var ctx = try PostSearchPageContext(req, posts: responseData, searchType: .textSearch, formData: formData)
			if let forumID = formData.forum {
				let forumResponse = try await apiQuery(req, endpoint: "/forum/\(forumID)", query: [URLQueryItem(name: "limit", value: "0")])
				ctx.forumData = try forumResponse.content.decode(ForumData.self)
			}
			if let categoryID = ctx.forumData?.categoryID ?? formData.category {
				let catResponse = try await apiQuery(req, endpoint: "/forum/categories", query: [URLQueryItem(name: "cat", value: categoryID.uuidString)])
				let catInfo = try catResponse.content.decode([CategoryData].self)
				ctx.categoryData = catInfo.first
			}
			return try await req.view.render("Forums/forumPostsList", ctx)
		}
	}

	// GET /forum/owned
	//
	// Shows the forums the current user has created.
	func forumsByUserPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/owner")
		let forums = try response.content.decode(ForumSearchData.self)
		let ctx = try ForumsSearchPageContext(
			req,
			forums: forums,
			searchType: .owned,
			filterDesc: "Your \(forums.paginator.total) Forums"
		)
		return try await req.view.render("Forums/forumsList", ctx)
	}

	// GET /forum/recent
	//
	// Shows the forums the user has viewed recently
	func forumRecentsPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/recent")
		let forums = try response.content.decode(ForumSearchData.self)
		let ctx = try ForumsSearchPageContext(req, forums: forums, searchType: .recent, filterDesc: "Recent Forums")
		return try await req.view.render("Forums/forumsList", ctx)
	}

	// GET /forum/favorites
	//
	// Displays a list of the user's favorited forums.
	// URL QueryParameters start, limit are passed through.
	func forumFavoritesPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/favorites")
		let forums = try response.content.decode(ForumSearchData.self)
		let ctx = try ForumsSearchPageContext(
			req,
			forums: forums,
			searchType: .favorite,
			filterDesc: "\(forums.paginator.total) Favorites"
		)
		return try await req.view.render("Forums/forumsList", ctx)
	}

	// GET /forum/unread
	//
	// Displays a list of the user's favorited forums.
	// URL QueryParameters start, limit are passed through.
	func forumUnreadPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/unread")
		let forums = try response.content.decode(ForumSearchData.self)
		let ctx = try ForumsSearchPageContext(
			req,
			forums: forums,
			searchType: .unread,
			filterDesc: "\(forums.paginator.total) Unread Forums"
		)
		return try await req.view.render("Forums/forumsList", ctx)
	}

	// GET /forum/mutes
	//
	// Displays a list of the user's mutes forums.
	// URL QueryParameters start, limit are passed through.
	func forumMutesPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/mutes")
		let forums = try response.content.decode(ForumSearchData.self)
		let ctx = try ForumsSearchPageContext(
			req,
			forums: forums,
			searchType: .mute,
			filterDesc: "\(forums.paginator.total) Muted Forums"
		)
		return try await req.view.render("Forums/forumsList", ctx)
	}

	// GET /forumpost/search
	//
	// Shows results of searches for forum posts. Passes query parameters through to /api/v3/forum/post/search.
	func forumPostSearchPageHandler(_ req: Request) async throws -> View {
		let response = try await apiQuery(req, endpoint: "/forum/post/search")
		let responseData = try response.content.decode(PostSearchData.self)
		let ctx = try PostSearchPageContext(req, posts: responseData, searchType: .direct)
		return try await req.view.render("Forums/forumPostsList", ctx)
	}
}
