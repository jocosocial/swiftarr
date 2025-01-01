import Fluent
import FluentSQL
import Vapor

/// The collection of `/api/v3/forum/*` route endpoints and handler functions related
/// to forums.

struct ForumController: APIRouteCollection {

	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {

		// convenience route group for all /api/v3/forum endpoints
		let forumRoutes = app.grouped("api", "v3", "forum")

		// Flex access endpoints
		let flexAuthGroup = forumRoutes.flexRoutes(feature: .forums)
		flexAuthGroup.get("categories", use: categoriesHandler)

		// Forum Route Group, requires token
		let tokenAuthGroup = forumRoutes.tokenRoutes(feature: .forums)

		// Categories
		tokenAuthGroup.get("categories", categoryIDParam, use: categoryForumsHandler)

		// Forums - CRUD first, then actions on forums
		tokenAuthGroup.on(.POST, "categories", categoryIDParam, "create", body: .collect(maxSize: "30mb"), use: forumCreateHandler)
		tokenAuthGroup.get(forumIDParam, use: forumThreadHandler)  // Returns a forum thread by ID
		tokenAuthGroup.get("post", postIDParam, "forum", use: postForumThreadHandler)  // Returns the forum a post is in.
		tokenAuthGroup.get("forevent", ":event_id", use: eventForumThreadHandler)  // Returns the forum for an event
		tokenAuthGroup.post(forumIDParam, "rename", ":new_name", use: forumRenameHandler)
		tokenAuthGroup.post(forumIDParam, "delete", use: forumDeleteHandler)
		tokenAuthGroup.delete(forumIDParam, use: forumDeleteHandler)
		tokenAuthGroup.post(forumIDParam, "report", use: forumReportHandler)

		// 'Favorite' applies to forums, while 'Bookmark' is for posts
		tokenAuthGroup.get("favorites", use: favoritesHandler)
		tokenAuthGroup.post(forumIDParam, "favorite", use: favoriteAddHandler)
		tokenAuthGroup.post(forumIDParam, "favorite", "remove", use: favoriteRemoveHandler)
		tokenAuthGroup.delete(forumIDParam, "favorite", use: favoriteRemoveHandler)

		// Muted
		tokenAuthGroup.get("mutes", use: mutesHandler)
		tokenAuthGroup.post(forumIDParam, "mute", use: muteAddHandler)
		tokenAuthGroup.post(forumIDParam, "mute", "remove", use: muteRemoveHandler)
		tokenAuthGroup.delete(forumIDParam, "mute", use: muteRemoveHandler)

		// Pins
		tokenAuthGroup.post(forumIDParam, "pin", use: forumPinAddHandler)
		tokenAuthGroup.post(forumIDParam, "pin", "remove", use: forumPinRemoveHandler)
		tokenAuthGroup.delete(forumIDParam, "pin", use: forumPinRemoveHandler)
		tokenAuthGroup.get(forumIDParam, "pinnedposts", use: forumPinnedPostsHandler)

		tokenAuthGroup.get("search", use: forumSearchHandler)
		tokenAuthGroup.get("owner", use: ownerHandler)
		tokenAuthGroup.get("recent", use: recentsHandler)
		tokenAuthGroup.get("unread", use: unreadHandler)

		// Posts - CRUD first, then actions on posts
		tokenAuthGroup.on(.POST, forumIDParam, "create", body: .collect(maxSize: "30mb"), use: postCreateHandler)
		tokenAuthGroup.get("post", postIDParam, use: postHandler)
		tokenAuthGroup.on(.POST, "post", postIDParam, "update", body: .collect(maxSize: "30mb"), use: postUpdateHandler)
		tokenAuthGroup.post("post", postIDParam, "delete", use: postDeleteHandler)
		tokenAuthGroup.delete("post", postIDParam, use: postDeleteHandler)

		tokenAuthGroup.post("post", postIDParam, "laugh", use: postLaughHandler)
		tokenAuthGroup.post("post", postIDParam, "like", use: postLikeHandler)
		tokenAuthGroup.post("post", postIDParam, "love", use: postLoveHandler)
		tokenAuthGroup.post("post", postIDParam, "unreact", use: postUnreactHandler)
		tokenAuthGroup.delete("post", postIDParam, "laugh", use: postUnreactHandler)
		tokenAuthGroup.delete("post", postIDParam, "like", use: postUnreactHandler)
		tokenAuthGroup.delete("post", postIDParam, "love", use: postUnreactHandler)
		tokenAuthGroup.post("post", postIDParam, "report", use: postReportHandler)

		// Pins
		tokenAuthGroup.post("post", postIDParam, "pin", use: forumPostPinAddHandler)
		tokenAuthGroup.post("post", postIDParam, "pin", "remove", use: forumPostPinRemoveHandler)
		tokenAuthGroup.delete("post", postIDParam, "pin", use: forumPostPinRemoveHandler)

		// 'Favorite' applies to forums, while 'Bookmark' is for posts
		tokenAuthGroup.post("post", postIDParam, "bookmark", use: bookmarkAddHandler)
		tokenAuthGroup.post("post", postIDParam, "bookmark", "remove", use: bookmarkRemoveHandler)
		tokenAuthGroup.delete("post", postIDParam, "bookmark", use: bookmarkRemoveHandler)

		// ForumPost search. Takes a bunch of options.
		tokenAuthGroup.get("post", "search", use: postSearchHandler)
	}

	// MARK: - Open Access Handlers

	/// `GET /api/v3/forum/categories`
	///
	/// Retrieve a list of  forum `Category`s, sorted by access level and title. Access to certain categories is restricted to users of an appropriate
	/// access level, which implies those categories won't be shown if you don't provide a login token. Without a token, the 'accessible to anyone' categories
	/// are returned. You'll still need to be logged in to see the contents of the categories, or post, or do much anything else.
	///
	/// **URL Query Parameters:**
	/// - `?cat=UUID` Only return information about the given category. Will still return an array of `CategoryData`.
	///
	/// - Returns: An array of `CategoryData` containing all category IDs and titles. Or just the one, if you use the ?cat parameter.
	func categoriesHandler(_ req: Request) async throws -> [CategoryData] {
		var effectiveAccessLevel: UserAccessLevel = .unverified
		let user = req.auth.get(UserCacheData.self)
		if let user = user {
			effectiveAccessLevel = user.accessLevel
		}
		let categoryQuery = Category.query(on: req.db).categoryAccessFilter(for: user)
		if let catID = req.query[UUID.self, at: "cat"] {
			categoryQuery.filter(\.$id == catID)
		}
		let categories = try await categoryQuery.all()
		let sortedCats = categories.sorted {
			if $0.accessLevelToView != $1.accessLevelToView {
				return $0.accessLevelToView > $1.accessLevelToView
			}
			if $0.accessLevelToCreate != $1.accessLevelToCreate {
				return $0.accessLevelToCreate > $1.accessLevelToCreate
			}
			return $0.title < $1.title
		}
		// return as CategoryData
		return try sortedCats.map {
			// This instance of the paginator uses the Category.forumCount from the database
			// since we don't know what the user has requested yet. Used to be Category.numThreads.
			try CategoryData($0, restricted: $0.accessLevelToCreate > effectiveAccessLevel, paginator: Paginator(total: Int($0.forumCount), start: 0, limit: 50))
		}
	}

	// MARK: - tokenAuthGroup Handlers (logged in)
	// All handlers in this route group require a valid HTTP Bearer Authentication
	// header in the request.

	// MARK: Returns Forum Lists
	/// `GET /api/v3/forum/categories/:ID`
	///
	/// Retrieve a list of forums in the specifiec `Category`. Will not return forums created by blocked users.
	///
	/// **URL Query Parameters:**
	/// * `?sort=[create, update, title, event]` - Sort forums by `create` time, `update` time, or `title`, or the start time of their associated `Event`.
	/// * `?order=[ascending, descending]` - Specify a sort order. Omit this parameter to use the default ordering for the category type.
	/// Create and update return newest forums first. `event` is only valid for Event categories, is default for them, and returns forums in ascending event start time; secondary sort
	/// is alpha on event title. `Update` is the default for non-event categories.
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
	///
	/// beforedate and afterdate set the anchor point for returning threads. By default the anchor is 'newest create date'. When sorting on
	/// update time, these params may be used to ensure a series of calls see (mostly) contiguous resullts. As users keep posting
	/// to threads, the sorting for most recently updated threads is constantly changing. A paged UI, for example, may show N threads
	/// per page and use beforedate/afterdate as the user moves between pages to ensure continuity.
	/// When sorting on update time, afterdate and beforedate operate on the threads' update time. Create and Alpha sort use create time.
	/// These options are mutally exclusive; if both are present, beforeDate will be used.
	/// * `?afterdate=DATE` -
	/// * `?beforedate=DATE` -
	///
	/// With no parameters, defaults to `?sort=update&start=0&limit=50`.
	///
	/// If you want to ensure you have all the threads in a category, you can sort by create time and ask for threads newer than
	/// the last time you asked. If you want to update last post times and post counts, you can sort by update time and get the
	/// latest updates.
	///
	/// - Throws: 404 error if the category ID is not valid.
	/// - Returns: `CategoryData` containing category forums.
	func categoryForumsHandler(_ req: Request) async throws -> CategoryData {
		let cacheUser: UserCacheData = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
		let category = try await Category.findFromParameter(categoryIDParam, on: req)
		try guardUserCanAccessCategory(cacheUser, category: category)
		// remove blocks from results, unless it's an admin category
		let blocked = category.accessLevelToCreate.hasAccess(.moderator) ? [] : cacheUser.getBlocks()
		// sort user categories
		let countQuery = try Forum.query(on: req.db)
			.filter(\.$category.$id == category.requireID())
			.filter(\.$creator.$id !~ blocked)
			.join(ForumReaders.self, on: \Forum.$id == \ForumReaders.$forum.$id, method: .left)
			.join(
				Forum.self,
				ForumReaders.self,
				on: .custom(
					#"AND "\#(ForumReaders.schema)"."\#(ForumReaders().$user.$id.key)" = '\#(cacheUser.userID)'"#
				)
			)
			// User muting of a forum should take sort precedence over pinning.
			// They explicitly don't want to see it, so don't shove it in their face.
			// Not relevany anymore, but for anyone reading this in the future:
			// Nullibility influences sort order.
			.sort(ForumReaders.self, \.$isMuted, .descending)
			.sort(Forum.self, \.$pinned, .descending)
		if category.isEventCategory {
			_ = countQuery.join(child: \.$scheduleEvent, method: .left)
			// https://github.com/jocosocial/swiftarr/issues/199
			// .withDeleted() applies to the entire query, not just the joined table.
			// So simply slapping that on there would continue to display deleted Forums
			// in the list which is not good. The group filter afterwards mimicks the
			// behavior that Fluent defaults to when filtering soft-deleted data.
			.withDeleted()
			.group(.or) { group in 
				group.filter(\.$deletedAt == nil).filter(\.$deletedAt > Date())
			}
		}
		var dateFilterUsesUpdate = false
		let orderDirection = req.orderDirection()
		switch req.query[String.self, at: "sort"] {
		case "create": _ = countQuery.sort(\.$createdAt, orderDirection ?? .descending)
		case "title": _ = countQuery.sort(.custom("lower(\"forum\".\"title\")"), orderDirection ?? .ascending)
		case "update":
			_ = countQuery.sort(\.$lastPostTime, orderDirection ?? .descending)
			dateFilterUsesUpdate = true
		default:
			if category.isEventCategory {
				// Sort by event start time
				_ = countQuery.sort(Event.self, \Event.$startTime, orderDirection ?? .ascending).sort(Event.self, \Event.$title, orderDirection ?? .ascending)
			}
			else {
				_ = countQuery.sort(\.$lastPostTime, orderDirection ?? .descending)
				dateFilterUsesUpdate = true
			}
		}
		if let beforeDate = req.query[Date.self, at: "beforedate"] {
			if dateFilterUsesUpdate {
				countQuery.filter(\.$lastPostTime < beforeDate)
			}
			else {
				countQuery.filter(\.$createdAt < beforeDate)
			}
		}
		else if let afterDate = req.query[Date.self, at: "afterdate"] {
			if dateFilterUsesUpdate {
				countQuery.filter(\.$lastPostTime > afterDate)
			}
			else {
				countQuery.filter(\.$createdAt > afterDate)
			}
		}
		let forumsQuery = countQuery.copy().range(start..<(start + limit))
		let forums = try await forumsQuery.all()
		// We store the number of threads in a category in the database via Category.forumCount.
		// But this is global and doesn't account for users blocks. For the purposes of Pagination
		// we use the number of results from the query as the "forum count".
		let forumCount = try await countQuery.count()
		let forumList = try await buildForumListData(forums, on: req, user: cacheUser)
		return try CategoryData(
			category,
			restricted: category.accessLevelToCreate > cacheUser.accessLevel,
			paginator: Paginator(total: forumCount, start: start, limit: limit),
			forumThreads: forumList
		)
	}

	/// `GET /api/v3/forum/search`
	///
	/// Retrieve all `Forum`s in all categories that match the specified criteria. Results will be sorted by most recent post time by default..
	/// Does not return results from categories for which the user does not have access.
	///
	/// **URL Query Parameters**:
	/// * `?search=STRING` - Matches forums with STRING in their title.
	/// * `?category=UUID` - Limit results to forums in given category. Adding this multiple times ORs all categories together
	/// * `?creatorself` - Matches forums created by the current user..
	/// * `?creator=STRING` - Matches forums created by the given username. Adding this multiple times ORs all forum creators together
	/// * `?creatorid=UUID` - Matches forums created by the given userID. Adding this multiple times ORs all forum creators together
	/// * `?favorite` - Limit results to forums that are favorited by the current user.
	/// * `?mute` - Limit results to forums that are muted by the current user.
	/// * `?searchposts=STRING` - Matches FORUMS where any post in the forum contains the given search string.
	/// * `?unread` - Limit resuts to forums that have posts the current user hasn't read
	/// * `?posted` - Matches forums where the current user posted.
	/// 
	/// * `?start=INT` - The index into the array of forums to start returning results. 0 for first forum.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	/// * `?sort=[create, update, title]` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first.\
	/// * `?order=[ascending, descending]` - Specify a sort order. Omit this parameter to use the default ordering.
	///
	///
	/// - Parameter searchString: In the URL path.
	/// - Returns: A `ForumSearchData` containing all matching forums.
	func forumSearchHandler(_ req: Request) async throws -> ForumSearchData {
		struct QueryStruct: Content {
			var search: String?
			var category: [UUID]?
			var creatorself: Bool?
			var creator: [String]?
			var creatorid: [UUID]?
			var favorite: Bool?
			var mute: Bool?
			var searchposts: String?
			var unread: Bool?
			var posted: Bool?
			var start: Int?
			var limit: Int?
			var sort: String?
			var order: String?
			
			mutating func afterDecode() throws {
				start = start ?? 0
				limit = (limit ?? 50).clamped(to: 0...Settings.shared.maximumForums)
				// postgres "_" and "%" are wildcards, so escape for literals
				search = search?.replacingOccurrences(of: "_", with: "\\_").replacingOccurrences(of: "%", with: "\\%")
						.trimmingCharacters(in: .whitespacesAndNewlines)
				if let search = search, search.isEmpty {
					throw Abort(.badRequest, reason: "Search string, while optional, must not be empty if it exists.")
				}
				searchposts = searchposts?.replacingOccurrences(of: "_", with: "\\_").replacingOccurrences(of: "%", with: "\\%")
						.trimmingCharacters(in: .whitespacesAndNewlines)
				if let searchposts = searchposts, searchposts.isEmpty {
					throw Abort(.badRequest, reason: "Search string, while optional, must not be empty if it exists.")
				}
			}
		}
		let cacheUser = try req.auth.require(UserCacheData.self)
		var urlQuery = try req.query.decode(QueryStruct.self)
		// Vapor/URLEncodedForm/URLEncodedFormDecoder.swift doesn't seem to want to decode 'flag' URL query params into structs.
		// Because of that, we have to do this to set the values. See https://github.com/vapor/vapor/issues/3163
		urlQuery.creatorself = req.query[Bool.self, at: "creatorself"]
		urlQuery.favorite = req.query[Bool.self, at: "favorite"]
		urlQuery.mute = req.query[Bool.self, at: "mute"]
		urlQuery.unread = req.query[Bool.self, at: "unread"]
		urlQuery.posted = req.query[Bool.self, at: "posted"]
		// Searches need to actually include a filter criteria; else this method just returns all the forums
		guard urlQuery.search != nil || urlQuery.category != nil || urlQuery.creatorself == true || urlQuery.creator != nil || 
				urlQuery.creatorid != nil || urlQuery.favorite == true || urlQuery.mute == true || urlQuery.searchposts != nil || 
				urlQuery.unread == true || urlQuery.posted == true else {
			throw Abort(.badRequest, reason: "Search request must contain at least one search option. You have to filter on something.")
		}
			
		let countQuery = Forum.query(on: req.db)
				.filter(\.$creator.$id !~ cacheUser.getBlocks())
				.categoryAccessFilter(for: cacheUser)
		if let search = urlQuery.search {
			countQuery.fullTextFilter(\.$title, search)
		}
		if let categoryFilter = urlQuery.category {
			// categoryAccessFilter() ensures that the Category is joined into the query.
			countQuery.filter(Category.self, \.$id ~~ categoryFilter)
		}
		if urlQuery.creatorself == true {
			countQuery.filter(\.$creator.$id == cacheUser.userID)
		}
		var creatorIDFilter: [UUID] = urlQuery.creatorid ?? []
		if let creatorNames = urlQuery.creator, !creatorNames.isEmpty {
			let creatingUsers = req.userCache.getUsers(usernames: creatorNames)
			guard creatingUsers.count == creatorNames.count else {
				throw Abort(.badRequest, reason: "No user with username: \(creatorNames).")
			}
			creatorIDFilter.append(contentsOf: creatingUsers.map { $0.userID })
		}
		if !creatorIDFilter.isEmpty {
			countQuery.filter(\.$creator.$id ~~ creatorIDFilter)
		}
		if urlQuery.favorite == true || urlQuery.mute == true {			
			countQuery.join(ForumReaders.self, on: \Forum.$id == \ForumReaders.$forum.$id)
					.filter(ForumReaders.self, \.$user.$id == cacheUser.userID)
			if urlQuery.favorite == true {
				countQuery.filter(ForumReaders.self, \.$isFavorite == true)
			}
			if urlQuery.mute == true {
				countQuery.filter(ForumReaders.self, \.$isMuted == true)
			}
		}
		if urlQuery.searchposts != nil || urlQuery.posted == true  {
			countQuery.join(ForumPost.self, on: \Forum.$id == \ForumPost.$forum.$id)
			if let search = urlQuery.searchposts  {
				countQuery.fullTextFilter(ForumPost.self, \.$text, search)
			}
			if urlQuery.posted == true {
				countQuery.filter(ForumPost.self, \ForumPost.$author.$id == cacheUser.userID)
			}
		}
		if urlQuery.unread == true {
			countQuery.joinWithFilter(method: .left, from: \Forum.$id, to: \ForumReaders.$forum.$id, otherFilters: 
					[.value(.path(ForumReaders.path(for: \.$user.$id), schema: ForumReaders.schema), .equal, .bind(cacheUser.userID))])
					.group(.or) { (or) in
						or.filter(ForumReaders.self, \.$lastPostReadID == nil)
						or.filter(\Forum.$lastPostID != \ForumReaders.$lastPostReadID)
					}
		}
		// get forums and total forum count, turn into [ForumListData] and then insert into ForumSearchData
		let forumCount = try await countQuery.count()
		let start = urlQuery.start ?? 0
		let limit = urlQuery.limit ?? 50
		let orderDirection = req.orderDirection();
		let forumQuery = countQuery.copy().range(start..<(start + limit)).join(child: \.$scheduleEvent, method: .left)
		switch req.query[String.self, at: "sort"] {
			case "create": _ = forumQuery.sort(\.$createdAt, orderDirection ?? .descending)
			case "title": _ = forumQuery.sort(.custom("lower(\"forum\".\"title\")"), orderDirection ?? .ascending)
			default: _ = forumQuery.sort(\.$lastPostTime, orderDirection ?? .descending)
		}
		let forums = try await forumQuery.all()
		let forumList = try await buildForumListData(forums, on: req, user: cacheUser)
		return ForumSearchData( paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
	}

	/// `GET /api/v3/forum/owner`
	///
	/// Retrieve a list of all `Forum`s created by the user. Default is to be sorted by title.
	///
	/// **URL Query Parameters**:
	/// * `?cat=CATEGORY_ID` - Limit returned list to forums in the given category (that were also created by the current user).
	/// * `?sort=[create, update, title]` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first.
	/// * `?order=[ascending, descending]` - Specify a sort order. Omit this parameter to use the default ordering.
	/// * `?start=INT` - The index into the array of forums to start returning results. 0 for first forum.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	///
	/// - Returns: A `ForumSearchData` containing all forums created by the user.
	func ownerHandler(_ req: Request) async throws -> ForumSearchData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
		let countQuery = Forum.query(on: req.db).filter(\.$creator.$id == cacheUser.userID)
			.categoryAccessFilter(for: cacheUser)
		if let cat = req.query[UUID.self, at: "cat"] {
			countQuery.filter(\.$category.$id == cat)
		}
		let forumCount = try await countQuery.count()
		let orderDirection = req.orderDirection();
		let forumQuery = countQuery.copy().range(start..<(start + limit)).join(child: \.$scheduleEvent, method: .left)
		switch req.query[String.self, at: "sort"] {
		case "create": _ = forumQuery.sort(\.$createdAt, orderDirection ?? .descending)
		case "update": _ = forumQuery.sort(\.$lastPostTime, orderDirection ?? .descending)
		default: _ = forumQuery.sort(.custom("lower(forum.title)"), orderDirection ?? .ascending)
		}
		async let forums = try forumQuery.all()
		let forumList = try await buildForumListData(forums, on: req, user: cacheUser)
		return ForumSearchData(paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
	}

	/// `GET /api/v3/forum/favorites`
	///
	/// Retrieve the `Forum`s the user has favorited.
	///
	/// **URL Query Parameters**:
	/// * `?cat=CATEGORY_ID` - Only show favorites in the given category
	/// * `?sort=STRING` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first. `update` is the default.
	/// * `?order=[ascending, descending]` - Specify a sort order. Omit this parameter to use the default ordering.
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
	///
	/// - Returns: A `ForumSearchData` containing the user's favorited forums.
	func favoritesHandler(_ req: Request) async throws -> ForumSearchData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
		let countQuery = Forum.query(on: req.db).filter(\.$creator.$id !~ cacheUser.getBlocks())
			.categoryAccessFilter(for: cacheUser)
			.join(ForumReaders.self, on: \Forum.$id == \ForumReaders.$forum.$id)
			.filter(ForumReaders.self, \.$user.$id == cacheUser.userID)
			.filter(ForumReaders.self, \.$isFavorite == true)
		if let cat = req.query[UUID.self, at: "cat"] {
			countQuery.filter(\.$category.$id == cat)
		}
		let forumCount = try await countQuery.count()
		let orderDirection = req.orderDirection()
		let forumQuery = countQuery.copy().range(start..<(start + limit)).join(child: \.$scheduleEvent, method: .left)
		switch req.query[String.self, at: "sort"] {
		case "create": _ = forumQuery.sort(\.$createdAt, orderDirection ?? .descending)
		case "title": _ = forumQuery.sort(.custom("lower(\"forum\".\"title\")"), orderDirection ?? .ascending)
		default: _ = forumQuery.sort(\.$lastPostTime, orderDirection ?? .descending)
		}
		async let forums = try forumQuery.all()
		let forumList = try await buildForumListData(forums, on: req, user: cacheUser, forceIsFavorite: true)
		return ForumSearchData(paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
	}

	/// `GET /api/v3/forum/mutes`
	///
	/// Retrieve the `Forum`s the user has muted.
	///
	/// **URL Query Parameters**:
	/// * `?cat=CATEGORY_ID` - Only show favorites in the given category
	/// * `?sort=STRING` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first. `update` is the default.
	/// * `?order=[ascending, descending]` - Specify a sort order. Omit this parameter to use the default ordering.
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
	///
	/// - Returns: A `ForumSearchData` containing the user's muted forums.
	func mutesHandler(_ req: Request) async throws -> ForumSearchData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
		let countQuery = Forum.query(on: req.db).filter(\.$creator.$id !~ cacheUser.getBlocks())
			.categoryAccessFilter(for: cacheUser)
			.join(ForumReaders.self, on: \Forum.$id == \ForumReaders.$forum.$id)
			.filter(ForumReaders.self, \.$user.$id == cacheUser.userID)
			.filter(ForumReaders.self, \.$isMuted == true)
		if let cat = req.query[UUID.self, at: "cat"] {
			countQuery.filter(\.$category.$id == cat)
		}
		let forumCount = try await countQuery.count()
		let orderDirection = req.orderDirection()
		let forumQuery = countQuery.copy().range(start..<(start + limit)).join(child: \.$scheduleEvent, method: .left)
		switch req.query[String.self, at: "sort"] {
		case "create": _ = forumQuery.sort(\.$createdAt, orderDirection ?? .descending)
		case "title": _ = forumQuery.sort(.custom("lower(\"forum\".\"title\")"), orderDirection ?? .ascending)
		default: _ = forumQuery.sort(\.$lastPostTime, orderDirection ?? .descending)
		}
		async let forums = try forumQuery.all()
		let forumList = try await buildForumListData(forums, on: req, user: cacheUser, forceIsMuted: true)
		return ForumSearchData(paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
	}

	/// `GET /api/v3/forum/unread`
	///
	/// Retrieve the `Forum`s the user has not read.
	///
	/// **URL Query Parameters**:
	/// * `?cat=CATEGORY_ID` - Only show favorites in the given category
	/// * `?sort=STRING` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first. `update` is the default.
	/// * `?order=[ascending, descending]` - Specify a sort order. Omit this parameter to use the default ordering.
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
	///
	/// - Returns: A `ForumSearchData` containing the user's muted forums.
	func unreadHandler(_ req: Request) async throws -> ForumSearchData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
		// https://github.com/jocosocial/swiftarr/issues/217
		// Lots of swearing, source code reading, and AI hallucinations went into the crafting of this
		// join. Unfortunately we can't do:
		//   .join(ForumReaders.self, on: \Forum.$id == \ForumReaders.$forum.$id && \ForumReaders.$user.$id == cacheUser.userID, method: .left)
		// because we get an error that:
		//   binary operator '&&' cannot be applied to operands of type 'ComplexJoinFilter' and 'ModelValueFilter<ForumReaders>'
		// which is very sad. The resultant SQL should read something like:
		//   ... LEFT JOIN "forum+readers" ON "forum"."id"="forum+readers"."forum" AND "forum+readers"."user"='$' WHERE ...
		let joinFilters: [DatabaseQuery.Filter] = [
			.field(.path(Forum.path(for: \.$id), schema: Forum.schema), .equal, .path(ForumReaders.path(for: \.$forum.$id), schema: ForumReaders.schema)),
			.value(.path(ForumReaders.path(for: \.$user.$id), schema: ForumReaders.schema), .equal, .bind(cacheUser.userID))
		]
		let countQuery = Forum.query(on: req.db).filter(\.$creator.$id !~ cacheUser.getBlocks())
			.categoryAccessFilter(for: cacheUser)	
			.join(ForumReaders.self, joinFilters, method: .left)
			.group(.or) { (or) in
				or.filter(ForumReaders.self, \.$lastPostReadID == nil)
				or.filter(\Forum.$lastPostID != \ForumReaders.$lastPostReadID)
			}
		if let cat = req.query[UUID.self, at: "cat"] {
			countQuery.filter(\.$category.$id == cat)
		}
		let forumCount = try await countQuery.count()
		let orderDirection = req.orderDirection()
		let forumQuery = countQuery.copy().range(start..<(start + limit)).join(child: \.$scheduleEvent, method: .left)
		switch req.query[String.self, at: "sort"] {
		case "create": _ = forumQuery.sort(\.$createdAt, orderDirection ?? .descending)
		case "title": _ = forumQuery.sort(.custom("lower(\"forum\".\"title\")"), orderDirection ?? .ascending)
		default: _ = forumQuery.sort(\.$lastPostTime, orderDirection ?? .descending)
		}
		let forums = try await forumQuery.all()
		let forumList = try await buildForumListData(forums, on: req, user: cacheUser)
		return ForumSearchData(paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
	}

	/// `GET /api/v3/forum/recent`
	///
	/// Retrieve the `Forum`s the user has recently visited. Results are sorted by most recent time each forum was visited.
	///
	/// **URL Query Parameters**:
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
	///
	/// - Returns: A `ForumSearchData` containing the user's favorited forums.
	func recentsHandler(_ req: Request) async throws -> ForumSearchData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
		let countQuery = Forum.query(on: req.db).filter(\.$creator.$id !~ cacheUser.getBlocks())
				.categoryAccessFilter(for: cacheUser)
				.join(ForumReaders.self, on: \Forum.$id == \ForumReaders.$forum.$id)
				.filter(ForumReaders.self, \.$user.$id == cacheUser.userID)
		let forumCount = try await countQuery.count()
		let rangeQuery = countQuery.copy().range(start..<(start + limit))
				.sort(ForumReaders.self, \.$updatedAt, .descending)
				.join(child: \.$scheduleEvent, method: .left)
		let forums = try await rangeQuery.all()
		let forumList = try await buildForumListData(forums, on: req, user: cacheUser, forceIsFavorite: false)
		return ForumSearchData(paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
	}

	// MARK: Returns Posts
	/// `GET /api/v3/forum/ID`
	///
	/// Retrieve a `Forum` with all its `ForumPost`s. Content from blocked or muted users,
	/// or containing user's muteWords, is not returned. Posts are always sorted by creation time.
	///
	/// **URL Query Parameters:**
	/// * `?start=INT` - The index into the array of posts to start returning results. 0 for first post. Not compatible with `startPost`.
	/// * `?startPost=INT` - PostID of a post in the thread.  Acts as if `start` had been used with the index of this post within the thread.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	///
	/// The first post in the result `posts` array (assuming it isn't blocked/muted) will be, in priority order:
	/// 1. The `start`-th post in the thread (first post has index 0).
	/// 2. The post with id of `startPost`
	/// 3. The page of thread posts (with `limit` as pagesize) that contains the last post read by the user.
	/// 4. The first post in the thread.
	///
	/// Start and Limit may not take all of the forum post filters into account, meaning you may receive fewer posts than requested even if your response doesn't include the last post.
	/// When asking for e.g. the first 50 posts in a thread you may only receive 46 posts, as 4 posts in that batch were filtered out after the database query.
	/// To continue reading the thread, ask to start with post 50 (not post 47)--you'll receive however many posts are viewable by the user in the range 50...99 .
	/// Doing it this way makes Forum read counts invariant to blocks--if a user reads a forum, then blocks a user, then
	/// comes back to the forum, they should come back to the same place they were in previously.
	///
	/// - Parameter forumID: in URL path
	/// - Throws: 404 error if the forum is not available.
	/// - Returns: `ForumData` containing the forum's metadata and posts.
	func forumThreadHandler(_ req: Request) async throws -> ForumData {
		let user = try req.auth.require(UserCacheData.self)
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.with(\.$category)
		}
		try guardUserCanAccessCategory(user, category: forum.category)
		return try await buildForumData(forum, on: req)
	}

	/// `GET /api/v3/forum/post/ID/forum`
	///
	/// Retrieve the `ForumData` of the specified `ForumPost`'s parent `Forum`.
	///
	/// **URL Query Parameters**:
	/// * `?start=INT` - The index into the array of posts to start returning results. 0 for first post.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	///
	/// The first post in the result `posts` array (assuming it isn't blocked/muted) will be, in priority order:
	/// 	- The `start`-th post in the thread (first post has index 0).
	/// 	- The post with ID given by the `ID` path parameter
	///
	/// Start and Limit do not take blocks and mutes into account, matching the behavior of the totalPosts values. Instead, when asking for e.g. the first 50 posts in a thread,
	/// you may only receive 46 posts, as 4 posts in that batch were blocked/muted. To continue reading the thread, ask to start with post 50 (not post 47)--you'll receive however
	/// many posts are viewable by the user in the range 50...99 . Doing it this way makes Forum read counts invariant to blocks--if a user reads a forum, then blocks a user, then
	/// comes back to the forum, they should come back to the same place they were in previously.
	///
	/// - Parameter postID: In the URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ForumData` containing the post's parent forum.
	func postForumThreadHandler(_ req: Request) async throws -> ForumData {
		let user = try req.auth.require(UserCacheData.self)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		guard let forum = post.$forum.value else {
			throw Abort(.internalServerError, reason: "Could not find the forum containing this forum post.")
		}
		try guardUserCanAccessCategory(user, category: post.forum.category)
		return try await buildForumData(forum, on: req, startPostID: post.requireID())
	}

	/// `GET /api/v3/forum/forevent/ID`
	///
	/// Retrieve the `Forum` associated with an `Event`, with its `ForumPost`s. Content from
	/// blocked or muted users, or containing user's muteWords, is not returned.
	///
	/// **URL Query Parameters**:
	/// * `?start=INT` - The index into the array of posts to start returning results. 0 for first post. Default is the last post the user read, rounded down to a multiple of `limit`.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	///
	/// - Parameter eventID: In the URL path.
	/// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
	/// - Returns: `ForumData` containing the forum's metadata and all posts.
	func eventForumThreadHandler(_ req: Request) async throws -> ForumData {
		let user = try req.auth.require(UserCacheData.self)
		let event = try await Event.findFromParameter("event_id", on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		guard let forum = event.forum else {
			throw Abort(.internalServerError, reason: "event has no forum")
		}
		try guardUserCanAccessCategory(user, category: forum.category)
		return try await buildForumData(forum, on: req)
	}

	/// `GET /api/v3/forum/post/ID`
	///
	/// Retrieve the specified `ForumPost` with full user `LikeType` data.
	///
	/// - Parameter postID: In the URL path.
	/// - Throws: 404 error if the post is not available.
	/// - Returns: `PostDetailData` containing the specified post.
	func postHandler(_ req: Request) async throws -> PostDetailData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		try guardUserCanAccessCategory(cacheUser, category: post.forum.category)
		if cacheUser.getBlocks().contains(post.$author.id) || cacheUser.getMutes().contains(post.$author.id)
			|| post.containsMutewords(using: cacheUser.mutewords ?? [])
		{
			throw Abort(.notFound, reason: "post is not available")
		}
		// get likes data and bookmark state
		let postLikes = try await PostLikes.query(on: req.db).filter(\.$post.$id == post.requireID()).all()
		var laughUsers = [UUID]()
		var likeUsers = [UUID]()
		var loveUsers = [UUID]()
		var isFavorite = false
		for postLike in postLikes {
			if postLike.isFavorite && postLike.$user.id == cacheUser.userID {
				isFavorite = true
			}
			switch postLike.likeType {
			case .laugh?: laughUsers.append(postLike.$user.id)
			case .love?: loveUsers.append(postLike.$user.id)
			case .like?: likeUsers.append(postLike.$user.id)
			case .none: break
			}
		}
		// init return struct
		var postDetailData = try PostDetailData(post: post, author: req.userCache.getHeader(post.$author.id))
		postDetailData.isBookmarked = isFavorite
		postDetailData.laughs = req.userCache.getHeaders(laughUsers)
		postDetailData.likes = req.userCache.getHeaders(likeUsers)
		postDetailData.loves = req.userCache.getHeaders(loveUsers)
		return postDetailData
	}

	/// `GET /api/v3/forum/post/search`
	///
	/// Search all `ForumPost`s that match the filters given in the URL query parameters:
	///
	/// **URL Query Parameters**:
	/// * `?search=STRING` - Matches posts whose text contains the given search string.
	/// * `?hashtag=STRING` - Matches posts whose text contains the given #hashtag. The leading # is optional in the query parameter.
	/// * `?mentionname=STRING` - Matches posts whose text contains a @mention of the given username. The leading @ is optional in the query parameter.
	/// * `?mentionid=UUID` - Matches posts whose text contains a @mention of the user with the given userID. Do not prefix userID with @.
	/// * `?mentionself=true` - Matches posts whose text contains a @mention of the current user.
	/// * `?ownreacts=true` - Matches posts the current user has reacted to.
	/// * `?byself=true` - Matches posts the current user authored.
	/// * `?bookmarked=true` - Matches posts the user has bookmarked.
	/// * `?creatorid=STRING` - Matches posts created by the given userID.
	///
	/// Additionally, you can constrain results to either posts in a specific category, or a specific forum. If both are specified, forum is ignored.
	/// * `?forum=UUID` - Confines the search to posts in the given forum thread.
	/// * `?category=UUID` - Confines the search to posts in the given forum category.
	///
	/// While `mentionname` does not test whether the @mention matches any user's username, `mentionid` does. Also `mentionname`, `mentionid`
	/// and `mentionself` are mutually exclusive parameters.
	///
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
	///
	/// - Returns: `PostSearchData` containing the search results..
	func postSearchHandler(_ req: Request) async throws -> PostSearchData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		var postFilterMentions: String? = nil
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForumPosts)
		// Start building a query.
		// Note: categoryAccessFilter() joins the post's forum and category, but other filters (below) may require the join as well.
		var query = ForumPost.query(on: req.db).filter(\.$author.$id !~ cacheUser.getBlocks())
			.filter(\.$author.$id !~ cacheUser.getMutes())
			.sort(\.$id, .descending)
			.categoryAccessFilter(for: cacheUser)

		let matchBookmarked = req.query[String.self, at: "bookmarked"] == "true"
		let ownReacts = req.query[String.self, at: "ownreacts"] == "true"
		if ownReacts || matchBookmarked {
			query.join(PostLikes.self, on: \ForumPost.$id == \PostLikes.$post.$id)
				.filter(PostLikes.self, \.$user.$id == cacheUser.userID)
			if matchBookmarked {
				query.filter(PostLikes.self, \.$isFavorite == true)
			}
			if ownReacts {
				query.filter(PostLikes.self, \.$likeType != nil)
			}
		}
		if let categoryStr = req.query[String.self, at: "category"] {
			guard let categoryID = UUID(categoryStr) else {
				throw Abort(.badRequest, reason: "category parameter requires a valid UUID")
			}
			// Depends on `.join(Forum.self, on: \ForumPost.$forum.$id == \Forum.$id)`, above
			query = query.filter(Forum.self, \.$category.$id == categoryID)
		}
		else if let forumID = req.query[UUID.self, at: "forum"] {
			query = query.filter(\.$forum.$id == forumID)
		}
		// https://github.com/jocosocial/swiftarr/issues/167
		// Limiting this to mods for the moment because the amount of dishonorable uses I can
		// think of is very high. This feature is useful in the mod context because it allows
		// mods to get a sense of the content that the user has been posting.
		// For example: If a user has been reported multiple times and a ban decision is being
		// considered, seeing if the user has been perpetually un-excellent in the forums
		// is much easier. In the Twarrt Stream we had a feature where you could see all posts
		// by user for a similar reason (and because that's what a lot of social media tools do).
		// This limitation is very much open to consideration.
		// There's a corresponding userIsMod in the Site HTML template.
		if let creatorID = req.query[UUID.self, at: "creatorid"], let creatingUser = req.userCache.getUser(creatorID) {
			guard cacheUser.accessLevel.hasAccess(.moderator) else {
				throw Abort(.forbidden, reason: "Only moderators can use creatorid on this endpoint")
			}
			query = query.filter(\.$author.$id == creatingUser.userID)
		}

		if var searchStr = req.query[String.self, at: "search"] {
			searchStr = searchStr.replacingOccurrences(of: "_", with: "\\_")
				.replacingOccurrences(of: "%", with: "\\%")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			query.fullTextFilter(\.$text, searchStr)
			if !searchStr.contains(" ") && start == 0 {
				try await markNotificationViewed(user: cacheUser, type: .alertwordPost(searchStr, 0), on: req)
			}
		}
		if var hashtag = req.query[String.self, at: "hashtag"] {
			// postgres "_" and "%" are wildcards, so escape for literals
			hashtag = hashtag.replacingOccurrences(of: "_", with: "\\_")
				.replacingOccurrences(of: "%", with: "\\%")
				.trimmingCharacters(in: .whitespacesAndNewlines)
			if !hashtag.hasPrefix("#") {
				hashtag = "#\(hashtag)"
			}
			query.filter(\.$text, .custom("ILIKE"), "%\(hashtag)%")
		}
		if let mentionID = req.query[String.self, at: "mentionid"], let mentionUUID = UUID(mentionID),
			let mentionedUser = req.userCache.getUser(mentionUUID)
		{
			postFilterMentions = mentionedUser.username
		}
		else if let mentionName = req.query[String.self, at: "mentionname"] {
			postFilterMentions = mentionName
		}
		else if let mentionSelf = req.query[String.self, at: "mentionself"], mentionSelf == "true" {
			postFilterMentions = cacheUser.username
			// TODO: Set user's mentionsViewed to == mentions
		}
		if var mentionName = postFilterMentions {
			if !mentionName.hasPrefix("@") {
				mentionName = "@\(mentionName)"
			}
			postFilterMentions = mentionName
			query.filter(\.$text, .custom("ILIKE"), "%\(mentionName)%")
			if mentionName.lowercased() == "@moderator" && cacheUser.accessLevel.hasAccess(.moderator) {
				try await markNotificationViewed(user: cacheUser, type: .moderatorForumMention(0), on: req)
			}
			if mentionName.lowercased() == "@twitarrteam" && cacheUser.accessLevel.hasAccess(.twitarrteam) {
				try await markNotificationViewed(user: cacheUser, type: .twitarrTeamForumMention(0), on: req)
			}
		}
		if let byself = req.query[Bool.self, at: "byself"], byself == true {
			query.filter(\.$author.$id == cacheUser.userID)
		}

		let countQuery = query.copy()
		let rangeQuery = query.copy()
		let totalPostsFound = try await countQuery.count()
		let posts = try await rangeQuery.range(start..<(start + limit)).all()
		// The filter() for mentions will include usernames that are prefixes for other usernames and other false positives.
		// This filters those out after the query.
		var postFilteredPosts = posts
		if let postFilter = postFilterMentions {
			postFilteredPosts = postFilteredPosts.compactMap { $0.filterForMention(of: postFilter) }
			if postFilter == "@\(cacheUser.username)" {
				try await markNotificationViewed(user: cacheUser, type: .forumMention(0), on: req)
			}
		}
		let postData = try await buildPostData(postFilteredPosts, userID: cacheUser.userID, on: req, mutewords: cacheUser.mutewords)
		return PostSearchData(queryString: req.url.query ?? "", posts: postData,
				paginator: Paginator(total: totalPostsFound, start: start, limit: limit))
	}

	// MARK: POST and DELETE actions

	/// `POST /api/v3/forum/post/ID/bookmark`
	///
	/// Add a bookmark of the specified `ForumPost`.
	///
	/// - Parameter postID: In the URL path.
	/// - Throws: 400 error if the post is already bookmarked.
	/// - Returns: 201 Created on success; 200 OK if already bookmarked.
	func bookmarkAddHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		let postLike =
			try await PostLikes.query(on: req.db).filter(\.$post.$id == post.requireID())
			.filter(\.$user.$id == cacheUser.userID)
			.first() ?? PostLikes(cacheUser.userID, post)
		if postLike.isFavorite {
			return .ok
		}
		postLike.isFavorite = true
		try await postLike.save(on: req.db)
		return .created
	}

	/// `POST /api/v3/forum/post/ID/bookmark/remove`
	/// `DELETE /api/v3/forum/post/ID/bookmark`
	///
	/// Remove a bookmark of the specified `ForumPost`.
	///
	/// - Parameter postID: In the URL path.
	/// - Throws: 400 error if the user has not bookmarked any posts.
	/// - Returns: 204 NoContent on success.
	func bookmarkRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		guard
			let postLike = try await PostLikes.query(on: req.db).filter(\.$post.$id == post.requireID())
				.filter(\.$user.$id == cacheUser.userID).first(), postLike.isFavorite == true
		else {
			return .noContent
		}
		postLike.isFavorite = false
		try await postLike.save(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/forum/ID/favorite`
	///
	/// Add the specified `Forum` to the user's tagged forums list.
	///
	/// - Parameter forumID: In the URL path.
	/// - Returns: 201 Created on success; 200 OK if already favorited.
	func favoriteAddHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		let forumReader =
			try await ForumReaders.query(on: req.db).filter(\.$forum.$id == forum.requireID())
			.filter(\.$user.$id == cacheUser.userID).first() ?? ForumReaders(cacheUser.userID, forum)
		if forumReader.isMuted == true {
			throw Abort(.badRequest, reason: "Cannot favorite a muted forum.")
		}
		if forumReader.isFavorite {
			return .ok
		}
		forumReader.isFavorite = true
		try await forumReader.save(on: req.db)
		return .created
	}

	/// `POST /api/v3/forum/ID/favorite/remove`
	/// `DELETE /api/v3/forum/ID/favorite`
	///
	/// Remove the specified `Forum` from the user's tagged forums list.
	///
	/// - Parameter forumID: In the URL path.
	/// - Throws: 400 error if the forum was not favorited.
	/// - Returns: 204 No Content on success; 200 OK if already not favorited.
	func favoriteRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let forumID = req.parameters.get(forumIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Invalid Forum ID parameter")
		}
		guard
			let forumReader = try await ForumReaders.query(on: req.db).filter(\.$forum.$id == forumID)
				.filter(\.$user.$id == cacheUser.userID).first(), forumReader.isFavorite == true
		else {
			return .ok
		}
		forumReader.isFavorite = false
		try await forumReader.save(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/forum/ID/mute`
	///
	/// Mute the `Forum` for the current user.
	///
	/// - Parameter forumID: In the URL path.
	/// - Returns: 201 Created on success; 200 OK if already muted.
	func muteAddHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		let forumReader =
			try await ForumReaders.query(on: req.db).filter(\.$forum.$id == forum.requireID())
			.filter(\.$user.$id == cacheUser.userID).first() ?? ForumReaders(cacheUser.userID, forum)
		if forumReader.isFavorite {
			throw Abort(.badRequest, reason: "Cannot mute a favorited forum.")
		}
		if forumReader.isMuted != nil {
			return .ok
		}
		forumReader.isMuted = true
		try await forumReader.save(on: req.db)
		return .created
	}

	/// `DELETE /api/v3/forum/ID/mute`
	///
	/// Unmute the specified `Forum` for the current user.
	///
	/// - Parameter forumID: In the URL path.
	/// - Throws: 400 error if the forum was not muted.
	/// - Returns: 204 No Content on success; 200 OK if already not muted.
	func muteRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let forumID = req.parameters.get(forumIDParam.paramString, as: UUID.self) else {
			throw Abort(.badRequest, reason: "Invalid Forum ID parameter")
		}
		guard
			let forumReader = try await ForumReaders.query(on: req.db).filter(\.$forum.$id == forumID)
				.filter(\.$user.$id == cacheUser.userID).first(), forumReader.isMuted == true
		else {
			return .ok
		}
		forumReader.isMuted = nil
		try await forumReader.save(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/forum/ID/pin`
	///
	/// Pin the forum to the category.
	///
	/// - Parameter forumID: In the URL path.
	/// - Returns: 201 Created on success; 200 OK if already pinned.
	func forumPinAddHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Only moderators can pin a forum thread.")
		}
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		if forum.pinned == true {
			return .ok
		}
		forum.pinned = true;
		try await forum.save(on: req.db)
		try await forum.logIfModeratorAction(.pin, moderatorID: cacheUser.userID, on: req)
		return .created
	}

	/// `DELETE /api/v3/forum/ID/pin`
	///
	/// Unpin the forum from the category.
	///
	/// - Parameter forumID: In the URL path.
	/// - Returns: 204 No Content on success; 200 OK if already not pinned.
	func forumPinRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.hasAccess(.moderator) else {
			throw Abort(.forbidden, reason: "Only moderators can pin a forum thread.")
		}
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		if forum.pinned != true {
			return .ok
		}
		forum.pinned = false;
		try await forum.save(on: req.db)
		try await forum.logIfModeratorAction(.unpin, moderatorID: cacheUser.userID, on: req)
		return .noContent
	}

	/// `POST /api/v3/forum/categories/ID/create`
	///
	/// Creates a new `Forum` in the specified `Category`, and the first `ForumPost` within
	/// the newly created forum. Creating a forum in a category requires a `userAccessLevel` >= the category's `accessLevelToCreate`.
	///
	/// - Note: Users may be able to add posts to existing forum threads in categories where they don't have access to create new threads.
	///
	/// This function intentionally does not generate a ForumReader pivot for the user that created it.
	/// https://github.com/jocosocial/swiftarr/issues/168
	/// See SiteForumController.swift for more.
	/// 
	/// - Parameter categoryID: in URL path
	/// - Parameter requestBody: `ForumCreateData` payload in the HTTP body.
	/// - Throws: 403 error if the user is not authorized to create a forum.
	/// - Returns: `ForumData` containing the new forum's contents.
	func forumCreateHandler(_ req: Request) async throws -> ForumData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// see `ForumCreateData.validations()`
		try cacheUser.guardCanCreateContent()
		let data = try ValidatingJSONDecoder().decode(ForumCreateData.self, fromBodyOf: req)
		// check authorization to create
		let category = try await Category.findFromParameter(categoryIDParam, on: req)
		guard cacheUser.accessLevel.hasAccess(category.accessLevelToCreate) else {
			throw Abort(.forbidden, reason: "users cannot create forums in category")
		}
		try guardUserCanAccessCategory(cacheUser, category: category)
		// process images
		let imageFilenames = try await self.processImages(data.firstPost.images, usage: .forumPost, on: req)
		// create forum
		let effectiveAuthor = data.firstPost.effectiveAuthor(actualAuthor: cacheUser, on: req)
		let forum = try Forum(title: data.title, category: category, creatorID: effectiveAuthor.userID, isLocked: false)
		try await forum.save(on: req.db)
		try await forum.logIfModeratorAction(.post, moderatorID: cacheUser.userID, on: req)
		// create first post
		let forumPost = try ForumPost(forum: forum, authorID: effectiveAuthor.userID, text: data.firstPost.text, images: imageFilenames)
		try await forumPost.save(on: req.db)
		try await forumPost.logIfModeratorAction(.post, moderatorID: cacheUser.userID, on: req)
		// Update the forum last post at
		forum.lastPostTime = Date()
		forum.lastPostID = forumPost.id
		try await forum.save(on: req.db)
		// Update the Category's cached count of forums
		category.forumCount = try await Int32(category.$forums.query(on: req.db).count())
		try await category.save(on: req.db)
		// If the post @mentions anyone, update their mention counts
		try await processForumMentions(post: forumPost, editedText: nil, isCreate: true, on: req)
		let creatorHeader = effectiveAuthor.makeHeader()
		let postData = try PostData(post: forumPost, author: creatorHeader, bookmarked: false, userLike: nil, likeCount: 0)
		let forumData = try ForumData(forum: forum, creator: creatorHeader, isFavorite: false, isMuted: false, posts: [postData], 
				pager: Paginator(total: 1, start: 0, limit: 50))
		return forumData
	}

	/// `POST /api/v3/forum/ID/rename/:new_name`
	///
	/// Rename the specified `Forum` to the specified title string.
	///
	/// - Parameter forumID: in URL path
	/// - Parameter new_name: in URL path; URL-path encoded.
	/// - Throws: 403 error if the user does not have credentials to modify the forum. 404 error
	///   if the forum ID is not valid.
	/// - Returns: 201 Created on success.
	func forumRenameHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard let nameParameter = req.parameters.get("new_name")?.removingPercentEncoding, nameParameter.count > 0
		else {
			throw Abort(.badRequest, reason: "No new name parameter for forum name change.")
		}
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		// must be forum owner or .moderator
		try cacheUser.guardCanModifyContent(forum, customErrorString: "User cannot modify forum title.")
		if forum.title != nameParameter {
			try await ForumEdit(forum: forum, editorID: cacheUser.userID, categoryChanged: false).save(on: req.db)
			forum.title = nameParameter
			try await forum.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
			try await forum.save(on: req.db)
		}
		return .created
	}

	/// `POST /api/v3/forum/ID/report`
	///
	/// Creates a `Report` regarding the specified `Forum`. The 'correct' use of this method is to report issues with the forum title. However,
	/// no amount of guidance is going to get users to not use this method to report on individual posts in the thread, even though there's a
	/// separate reporting API for reporting posts.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter forumID: in URL path
	/// - Parameter requestBody: `ReportData` payload in the HTTP body.
	/// - Returns: 201 Created on success.
	func forumReportHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		return try await forum.fileReport(submitter: cacheUser, submitterMessage: data.message, on: req)
	}

	/// `POST /api/v3/forum/ID/delete`
	/// `DELETE /api/v3/forum/ID`
	///
	/// Delete the specified `Forum`. This soft-deletes the forum itself and all the forum's posts. The posts have to be deleted so they
	/// won't be returned by search methods.
	///
	/// To delete, the user must have an access level allowing them to delete the forum. Currently this means moderators and above.
	/// This means a regular user cannot delete a forum they created themselves.
	///
	/// - Parameter forumID: in URL path
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func forumDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard cacheUser.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have access to delete forums.")
		}
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.categoryAccessFilter(for: cacheUser)
		}
		let category = try await forum.$category.get(on: req.db)
		try cacheUser.guardCanModifyContent(forum)
		try await forum.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		let posts = try await ForumPost.query(on: req.db).filter(\.$forum.$id == forum.requireID()).all()
		try await processThreadDeleteMentions(posts: posts, on: req)
		try await posts.delete(on: req.db)
		try await forum.delete(on: req.db)
		// Update Category's cached forum count
		let count = try await category.$forums.query(on: req.db).count()
		category.forumCount = Int32(count)
		try await category.save(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/forum/ID/create`
	///
	/// Create a new `ForumPost` in the specified `Forum`.
	///
	/// Creating a new post in a forum updates that forum's `lastPostTime` timestamp. Editing, deleting, or reacting to posts does not change the timestamp.
	/// This behavior sets the sort order for forums in a category when using the `update` sort order.
	///
	/// - Parameter forumID: in URL path
	/// - Parameter requestBody: `PostContentData`
	/// - Throws: 403 error if the forum is locked or user is blocked.
	/// - Returns: `PostData` containing the post's contents and metadata.
	func postCreateHandler(_ req: Request) async throws -> Response {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// see `PostContentData.validations()`
		let newPostData = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
		// get forum
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.with(\.$category)
		}
		try guardUserCanAccessCategory(cacheUser, category: forum.category)
		try guardUserCanPostInForum(cacheUser, in: forum)
		// ensure user has access to forum; user cannot retrieve block-owned forum, but prevent end-run
		guard !cacheUser.getBlocks().contains(forum.$creator.id) else {
			throw Abort(.forbidden, reason: "user cannot post in forum")
		}
		// process images
		let filenames = try await self.processImages(newPostData.images, usage: .forumPost, on: req)
		// create post
		let effectiveAuthor = newPostData.effectiveAuthor(actualAuthor: cacheUser, on: req)
		let forumPost = try ForumPost(
			forum: forum,
			authorID: effectiveAuthor.userID,
			text: newPostData.text,
			images: filenames
		)
		try await forumPost.save(on: req.db)
		forum.lastPostTime = Date()
		forum.lastPostID = forumPost.id
		try await forum.save(on: req.db)
		try await forumPost.logIfModeratorAction(.post, moderatorID: cacheUser.userID, on: req)
		// If the post @mentions anyone, update their mention counts
		try await processForumMentions(post: forumPost, editedText: nil, isCreate: true, on: req)
		// return as PostData, with 201 status
		let response = Response(status: .created)
		try response.content.encode(PostData(post: forumPost, author: effectiveAuthor.makeHeader()))
		return response
	}

	/// `POST /api/v3/forum/post/ID/delete`
	/// `DELETE /api/v3/forum/post/ID`
	///
	/// Delete the specified `ForumPost`.
	///
	/// To delete, the user must have an access level allowing them to delete the post, and the forum itself must not be locked or in quarantine.
	///
	/// - Parameter postID: in URL path
	/// - Throws: 403 error if the user is not permitted to delete.
	/// - Returns: 204 No Content on success.
	func postDeleteHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		try guardUserCanAccessCategory(cacheUser, category: post.forum.category)
		try guardUserCanPostInForum(cacheUser, in: post.forum, editingPost: post)
		try await post.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
		try await processForumMentions(post: post, editedText: nil, on: req)
		try await post.delete(on: req.db)
		return .noContent
	}

	/// `POST /api/v3/forum/post/ID/report`
	///
	/// Create a `Report` regarding the specified `ForumPost`.
	///
	/// - Note: The accompanying report message is optional on the part of the submitting user,
	///   but the `ReportData` is mandatory in order to allow one. If there is no message,
	///   send an empty string in the `.message` field.
	///
	/// - Parameter requestBody:`ReportData``
	/// - Throws: 409 error if user has already reported the post.
	/// - Returns: 201 Created on success.
	func postReportHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let data = try req.content.decode(ReportData.self)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		try guardUserCanAccessCategory(cacheUser, category: post.forum.category)
		return try await post.fileReport(submitter: cacheUser, submitterMessage: data.message, on: req)
	}

	/// `POST /api/v3/forum/post/ID/laugh`
	///
	/// Add a "laugh" reaction to the specified `ForumPost`. If there is an existing `LikeType`
	/// reaction by the user, it is replaced.
	///
	/// - Parameter postID: in URL path
	/// - Throws: 403 error if user is the post's creator.
	/// - Returns: `PostData` containing the updated like info.
	func postLaughHandler(_ req: Request) async throws -> PostData {
		return try await postReactHandler(req, likeType: .laugh)
	}

	/// `POST /api/v3/forum/post/ID/like`
	///
	/// Add a "like" reaction to the specified `ForumPost`. If there is an existing `LikeType`
	/// reaction by the user, it is replaced.
	///
	/// - Parameter postID: in URL path
	/// - Throws: 403 error if user is the post's creator.
	/// - Returns: `PostData` containing the updated like info.
	func postLikeHandler(_ req: Request) async throws -> PostData {
		return try await postReactHandler(req, likeType: .like)
	}

	/// `POST /api/v3/forum/post/ID/love`
	///
	/// Add a "love" reaction to the specified `ForumPost`. If there is an existing `LikeType`
	/// reaction by the user, it is replaced.
	///
	/// - Parameter postID: in URL path
	/// - Throws: 403 error if user is the post's creator.
	/// - Returns: `PostData` containing the updated like info.
	func postLoveHandler(_ req: Request) async throws -> PostData {
		return try await postReactHandler(req, likeType: .love)
	}

	func postReactHandler(_ req: Request, likeType: LikeType) async throws -> PostData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get post and forum
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		try guardUserCanAccessCategory(cacheUser, category: post.forum.category)
		guard post.$author.id != cacheUser.userID else {
			throw Abort(.forbidden, reason: "user cannot like own post")
		}
		let postLike =
			try await PostLikes.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
			.filter(\.$post.$id == post.requireID())
			.first() ?? PostLikes(cacheUser.userID, post)
		postLike.likeType = likeType
		try await postLike.save(on: req.db)
		let postDataArray = try await buildPostData([post], userID: cacheUser.userID, on: req)
		return postDataArray[0]
	}

	/// `POST /api/v3/forum/post/ID/unreact`
	/// `DELETE /api/v3/forum/post/ID/like`
	/// `DELETE /api/v3/forum/post/ID/laugh`
	/// `DELETE /api/v3/forum/post/ID/love`
	///
	/// Remove a `LikeType` reaction from the specified `ForumPost`.
	///
	/// - Parameter postID: in URL path
	/// - Throws: 403 error if user is the post's creator.
	/// - Returns: `PostData` containing the updated like info.
	func postUnreactHandler(_ req: Request) async throws -> PostData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// get post and forum
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		try guardUserCanAccessCategory(cacheUser, category: post.forum.category)
		guard post.$author.id != cacheUser.userID else {
			throw Abort(.forbidden, reason: "user cannot like own post")
		}
		if let postLike = try await PostLikes.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
			.filter(\.$post.$id == post.requireID()).first()
		{
			postLike.likeType = nil
			try await postLike.save(on: req.db)
		}
		let postDataArray = try await buildPostData([post], userID: cacheUser.userID, on: req)
		return postDataArray[0]
	}

	/// `POST /api/v3/forum/post/ID/update`
	///
	/// Update the specified `ForumPost`.
	///
	/// - Parameter postID: in URL path
	/// - Parameter requestBody: `PostContentData`
	/// - Throws: 403 error if user is not post owner or has read-only access.
	/// - Returns: `PostData` containing the post's contents and metadata.
	func postUpdateHandler(_ req: Request) async throws -> PostData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		// see `PostContentData.validations()`
		let newPostData = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		// Ensure use can view items in this category
		try guardUserCanAccessCategory(cacheUser, category: post.forum.category)
		// ensure user has write access, the post can be modified by them, and the forum isn't locked.
		try guardUserCanPostInForum(cacheUser, in: post.forum, editingPost: post)
		// process images
		let filenames = try await self.processImages(newPostData.images, usage: .forumPost, on: req)
		// update if there are changes
		let normalizedText = newPostData.text.replacingOccurrences(of: "\r\n", with: "\r")
		if post.text != normalizedText || post.images != filenames {
			// If the post @mentions anyone, update their mention counts
			try await processForumMentions(post: post, editedText: normalizedText, on: req)
			// Save current contents into an Edit record first
			let forumEdit = try ForumPostEdit(post: post, editorID: cacheUser.userID)
			post.text = normalizedText
			post.images = filenames
			try await post.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
			try await forumEdit.save(on: req.db)
			try await post.save(on: req.db)
		}
		// return updated post as PostData
		let postDataArray = try await buildPostData([post], userID: cacheUser.userID, on: req)
		return postDataArray[0]
	}

	/// `GET /api/v3/forum/:forumID/pinnedposts`
	///
	/// Get a list of all of the pinned posts within this forum.
	/// This currently does not implement paginator because if pagination is needed for pinned
	/// posts what the frak have you done?
	///
	/// - Parameter forumID: In the URL path.
	/// - Returns array of `PostData`.
	func forumPinnedPostsHandler(_ req: Request) async throws -> [PostData] {
		let user = try req.auth.require(UserCacheData.self)
		let forum = try await Forum.findFromParameter(forumIDParam, on: req) { query in
			query.with(\.$category)
		}
		try guardUserCanAccessCategory(user, category: forum.category)
		let query = try await ForumPost.query(on: req.db)
			.filter(\.$author.$id !~ user.getBlocks())
			.filter(\.$author.$id !~ user.getMutes())
			.categoryAccessFilter(for: user)
			.filter(\.$forum.$id == forum.requireID())
			.filter(\.$pinned == true)
			.all()
		return try await buildPostData(query, userID: user.userID, on: req, mutewords: user.mutewords)
	}

	/// `POST /api/v3/forum/post/:postID/pin`
	///
	/// Pin the post to the forum.
	///
	/// - Parameter postID: In the URL path.
	/// - Returns: 201 Created on success; 200 OK if already pinned.
	func forumPostPinAddHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		// Only forum creator and moderators can pin posts within a forum.
		try cacheUser.guardCanModifyContent(post, customErrorString: "User cannot pin posts in this forum.")
		// But it becomes moderators only if the forum is locked.
		if (post.forum.moderationStatus == .locked && !cacheUser.accessLevel.hasAccess(.moderator)) {
			throw Abort(.forbidden, reason: "Only moderators can perform pin actions on a locked forum.")
		}

		if post.pinned == true {
			return .ok
		}
		post.pinned = true;
		try await post.save(on: req.db)
		try await post.logIfModeratorAction(.pin, moderatorID: cacheUser.userID, on: req)
		return .created
	}

	/// `DELETE /api/v3/forum/:postID/ID/pin`
	///
	/// Unpin the post from the forum.
	///
	/// - Parameter postID: In the URL path.
	/// - Returns: 204 No Content on success; 200 OK if already not pinned.
	func forumPostPinRemoveHandler(_ req: Request) async throws -> HTTPStatus {
		let cacheUser = try req.auth.require(UserCacheData.self)
		let post = try await ForumPost.findFromParameter(postIDParam, on: req) { query in
			query.with(\.$forum) { forum in
				forum.with(\.$category)
			}
		}
		// Only forum creator and moderators can pin posts within a forum.
		try cacheUser.guardCanModifyContent(post, customErrorString: "User cannot pin posts in this forum.")
		// But it becomes moderators only if the forum is locked.
		if (post.forum.moderationStatus == .locked && !cacheUser.accessLevel.hasAccess(.moderator)) {
			throw Abort(.forbidden, reason: "Only moderators can perform pin actions on a locked forum.")
		}

		if post.pinned != true {
			return .ok
		}
		post.pinned = false;
		try await post.save(on: req.db)
		try await post.logIfModeratorAction(.unpin, moderatorID: cacheUser.userID, on: req)
		return .noContent
	}
}

// Utilities for route methods
extension ForumController {

	/// Ensures the given user has appropriate access to create or edit posts in the given forum. If editing a post, you must pass the post in the `editingPost` parameter.
	func guardUserCanPostInForum(_ user: UserCacheData, in forum: Forum, editingPost: ForumPost? = nil) throws {
		if let post = editingPost {
			try user.guardCanModifyContent(post)
		}
		else {
			try user.guardCanCreateContent()
		}
		guard
			user.accessLevel.canEditOthersContent()
				|| (forum.moderationStatus == .normal || forum.moderationStatus == .modReviewed)
		else {
			throw Abort(.forbidden, reason: "Forum is locked.")
		}
	}

	/// Ensures the given user has the required access to view forums and posts in the given category.
	func guardUserCanAccessCategory(_ user: UserCacheData, category: Category) throws {
		guard user.accessLevel.hasAccess(category.accessLevelToView) else {
			throw Abort(.forbidden, reason: "User cannot view this forum category.")
		}
		if !user.accessLevel.hasAccess(.moderator), let requiredRole = category.requiredRole {
			guard user.userRoles.contains(requiredRole) else {
				throw Abort(.forbidden, reason: "User does not have role to view this forum category.")
			}
		}
	}

	/// Returns a dictionary mapping ForumIDs to ForumPosts, where each ForumPost is the last post made in its Forum by a user who isn't blocked or muted.
	/// The code in the guard works by running a query for each Forum in the array; for 50 forums it takes ~82ms to resolve. The code in the bottom half of the fn
	/// uses SQLKit to make a more complicated query, returning answers for all forums in one result set. Takes ~9ms.
	///
	/// The resulting dictionary may not contain all forum IDs from the input array--a forum with no posts or for which all posts are blocked/muted will have no 'last post'.
	func forumListGetLastPosts(_ forums: [Forum], on req: Request, user: UserCacheData) async throws -> [UUID:
		ForumPost]
	{
		if forums.isEmpty {
			return [:]
		}
		guard let sql = req.db as? SQLDatabase else {
			// Use Fluent to get the result if SQL database isn't available. This is likely much slower.
			let lastPosts = try await withThrowingTaskGroup(of: (UUID, ForumPost?).self) { group -> [UUID: ForumPost] in
				for forum in forums {
					group.addTask {
						try await (
							forum.requireID(),
							forum.$posts.query(on: req.db).sort(\.$createdAt, .descending)
								.filter(\.$author.$id !~ user.getBlocks()).filter(\.$author.$id !~ user.getMutes())
								.first()
						)
					}
				}
				var resultDict = [UUID: ForumPost]()
				for try await postTuple in group {
					if let post = postTuple.1 {
						resultDict[postTuple.0] = post
					}
				}
				return resultDict
			}
			return lastPosts
		}
		let forumUUIDArray = try forums.map { try $0.requireID() }
		let forumFieldName = SQLIdentifier(ForumPost().$forum.$id.key.description)
		let idFieldName = SQLIdentifier(ForumPost().$id.key.description)
		let authorFieldName = SQLIdentifier(ForumPost().$author.$id.key.description)
		let subSelect = sql.select()
			.columns(SQLColumn(forumFieldName), SQLAlias(SQLFunction("MAX", args: "id"), as: SQLColumn("latestpostid")))
			.from(ForumPost.schema)
			.where(forumFieldName, .in, forumUUIDArray)
			.where(SQLColumn("deleted_at"), .is, SQLLiteral.null)
			.groupBy(forumFieldName)
		if !user.getBlocks().isEmpty || !user.getMutes().isEmpty {
			subSelect.where(authorFieldName, .notIn, Array(user.getBlocks().union(user.getMutes())))
		}
		let rows = try await sql.select()
			.column("*")
			.from(SQLGroupExpression(subSelect.query), as: SQLRaw("latestposts"))
			.join(SQLIdentifier(ForumPost.schema), on: idFieldName, .equal, SQLRaw("latestposts.latestpostid"))
			.all()
		let posts: [UUID: ForumPost] = try rows.reduce(into: [:]) { dict, row in
			let post = try row.decode(fluentModel: ForumPost.self)
			dict[post.$forum.id] = post
		}
		return posts
	}

	// Very useful snippet for debugging SQL statement builders.
	//		var s = SQLSerializer(database: sql)
	//		subSelect.query.serialize(to: &s)
	//		print(s.sql)

	/// Builds an array of `ForumListData` from the given `Forums`.
	/// `ForumListData` does not return post content, but does return post counts.
	/// `eventTime` and `timeZone` only get filled in if there's a Event join attached to the Forum, which should only happen for forums in Event categories.
	func buildForumListData(
		_ forums: [Forum],
		on req: Request,
		user: UserCacheData,
		forceIsFavorite: Bool? = nil,
		forceIsMuted: Bool? = nil
	) async throws -> [ForumListData] {
		// get forum metadata
		let forumIDs = try forums.map { try $0.requireID() }
		let postCounts = try await forums.childCountsPerModel(
			atPath: \.$posts,
			on: req.db,
			fluentFilter: { builder in
				// Deleted_at filter not required as Fluent will automatically filter soft-deleted posts.
				builder.filter(\.$author.$id !~ user.getBlocks()).filter(\.$author.$id !~ user.getMutes())
			},
			sqlFilter: { builder in
				builder.where(SQLColumn("deleted_at"), .is, SQLLiteral.null)
				let hideAuthors = user.getBlocks().union(user.getMutes())
				if !hideAuthors.isEmpty {
					builder.where("author", .notIn, Array(hideAuthors))
				}
			}
		)
		let readCounts = try await forums.childCountsPerModel(
			atPath: \.$posts,
			on: req.db,
			fluentFilter: { builder in
				// Deleted_at filter not required as Fluent will automatically filter soft-deleted posts.
				builder.filter(\.$author.$id !~ user.getBlocks()).filter(\.$author.$id !~ user.getMutes())
					.join(ForumReaders.self, on: \ForumPost.$forum.$id == \ForumReaders.$forum.$id)
					.filter(ForumReaders.self, \.$user.$id == user.userID)
					.filter(\ForumPost.$id < \ForumReaders.$lastPostReadID)
			},
			sqlFilter: { builder in
				builder.join(
					ForumReaders.schema,
					on: SQLColumn("forum", table: "forumpost"),
					.equal,
					SQLColumn("forum", table: "forum+readers")
				)
				builder.where(
					SQLColumn("user", table: "forum+readers"),
					.equal,
					SQLLiteral.string(user.userID.uuidString)
				)
				builder.where(SQLColumn("deleted_at", table: "forumpost"), .is, SQLLiteral.null)
				let hideAuthors = user.getBlocks().union(user.getMutes())
				if !hideAuthors.isEmpty {
					builder.where(SQLIdentifier(ForumPost().$author.$id.key.description), .notIn, Array(hideAuthors))
				}
				builder.where(
					SQLColumn("id", table: "forumpost"),
					.lessThanOrEqual,
					SQLColumn("last_post_read_id", table: "forum+readers")
				)
			}
		)
		let readerPivots = try await ForumReaders.query(on: req.db).filter(\.$user.$id == user.userID)
			.filter(\.$forum.$id ~~ forumIDs).all()
		let lastPostsDict = try await forumListGetLastPosts(forums, on: req, user: user)

		let readerPivotsDict = readerPivots.reduce(into: [:]) { $0[$1.$forum.id] = $1 }
		let returnListData: [ForumListData] = try forums.map { forum in
			let forumID = try forum.requireID()
			let creatorHeader = try req.userCache.getHeader(forum.$creator.id)
			var lastPosterHeader: UserHeader?
			var lastPostTime: Date?
			if let lastPost = lastPostsDict[forumID] {
				lastPosterHeader = try req.userCache.getHeader(lastPost.$author.id)
				lastPostTime = lastPost.createdAt
			}
			let thisForumReaderPivot = readerPivotsDict[forumID]
			let joinedEvent = try? forum.joined(Event.self)
			return try ForumListData(
				forum: forum,
				creator: creatorHeader,
				postCount: postCounts[forumID] ?? 0,
				readCount: readCounts[forumID] ?? 0,
				lastPostAt: lastPostTime,
				lastPoster: lastPosterHeader,
				isFavorite: forceIsFavorite ?? thisForumReaderPivot?.isFavorite ?? false,
				isMuted: forceIsMuted ?? thisForumReaderPivot?.isMuted ?? false,
				event: joinedEvent
			)
		}
		return returnListData
	}

	/// Builds a `ForumData` with the contents of the given `Forum`. Uses the requests' "limit" and "start" query parameters
	/// to return only a subset of the forums' posts (for forums where postCount > limit).
	func buildForumData(_ forum: Forum, on req: Request, startPostID: Int? = nil) async throws -> ForumData {
		let cacheUser = try req.auth.require(UserCacheData.self)
		var readerPivot = try await forum.$readers.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID)
			.first()
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 1...Settings.shared.maximumForumPosts)
		let query = forum.$posts.query(on: req.db)
			.filter(\.$author.$id !~ cacheUser.getBlocks())
			.filter(\.$author.$id !~ cacheUser.getMutes())
			.sort(\.$createdAt, .ascending)
		let postCount = try await query.count()

		// Determine the start offset into the posts array.
		var start = 0
		if let startParam = req.query[Int.self, at: "start"] {
			start = max(startParam, 0)
		}
		else if let startPostIDParam = req.query[Int.self, at: "startPost"] {
			start = try await forum.$posts.query(on: req.db).filter(\.$id < startPostIDParam)
				.filter(\.$author.$id !~ cacheUser.getBlocks()).filter(\.$author.$id !~ cacheUser.getMutes()).count()
		}
		else if let directStartPostID = startPostID {
			start = try await forum.$posts.query(on: req.db).filter(\.$id < directStartPostID)
				.filter(\.$author.$id !~ cacheUser.getBlocks()).filter(\.$author.$id !~ cacheUser.getMutes()).count()
		}
		else if let lastReadPost = readerPivot?.lastPostReadID {
			start = try await forum.$posts.query(on: req.db).filter(\.$id < lastReadPost)
				.filter(\.$author.$id !~ cacheUser.getBlocks()).filter(\.$author.$id !~ cacheUser.getMutes()).count()
			start = max((start / limit) * limit, 0)
		}
		let posts = try await query.range(start...start + max(limit - 1, 0)).all()
		if let lastPostID = posts.last?.id {
			if readerPivot == nil {
				readerPivot = try ForumReaders(cacheUser.userID, forum)
			}
			if let pivot = readerPivot, lastPostID > (pivot.lastPostReadID ?? 0) {
				pivot.lastPostReadID = lastPostID
				try await pivot.save(on: req.db)
			}
		}
		let flattenedPosts = try await buildPostData(
			posts,
			userID: cacheUser.userID,
			on: req,
			mutewords: cacheUser.mutewords
		)
		let creatorHeader = try req.userCache.getHeader(forum.$creator.id)
		let pager = Paginator(total: postCount, start: start, limit: limit)
		// For event forums
		var event: Event? = nil
		if forum.category.isEventCategory {
			event = try await forum.$scheduleEvent.query(on: req.db).first()
		}
		return try ForumData(
			forum: forum,
			creator: creatorHeader,
			isFavorite: readerPivot?.isFavorite ?? false,
			isMuted: readerPivot?.isMuted ?? false,
			posts: flattenedPosts,
			pager: pager,
			event: event
		)
	}

	// Builds an array of PostData structures from the given posts, adding the user's bookmarks and likes
	// for the post, as well as the total count of likes. The optional parameters are for callers that
	// only need some of the functionality, or for whom some of the values are known in advance e.g.
	// the method that returns a user's bookmarked posts can assume all the posts it finds are in fact bookmarked.
	func buildPostData(
		_ posts: [ForumPost],
		userID: UUID,
		on req: Request,
		mutewords: [String]? = nil,
		assumeBookmarked: Bool? = nil,
		assumeLikeType: LikeType? = nil,
		matchHashtag: String? = nil
	) async throws -> [PostData] {
		// remove muteword posts
		var filteredPosts = posts
		if let mutes = mutewords {
			filteredPosts = posts.compactMap { $0.filterOutStrings(using: mutes) }
		}
		// get exact hashtag if we're matching on hashtag
		if let hashtag = matchHashtag {
			filteredPosts = filteredPosts.compactMap { filteredPost in
				let text = filteredPost.text.lowercased()
				let words = text.components(separatedBy: .whitespacesAndNewlines + .contentSeparators)
				return words.contains(hashtag) ? filteredPost : nil
			}
		}

		let postIDs = try filteredPosts.map { try $0.requireID() }
		let userLikes = try await PostLikes.query(on: req.db).filter(\.$post.$id ~~ postIDs)
			.filter(\.$user.$id == userID).all()
		let likeCountDict = try await filteredPosts.childCountsPerModel(
			atPath: \.$likes.$pivots,
			on: req.db,
			fluentFilter: { builder in builder.filter(\.$likeType != nil) },
			sqlFilter: { builder in builder.where("liketype", .isNot, SQLLiteral.null) }
		)
		let userLikeDict = Dictionary(userLikes.map { ($0.$post.id, $0) }, uniquingKeysWith: { (first, _) in first })
		let postDataArray = try filteredPosts.map { post -> PostData in
			let postID = try post.requireID()
			let author = try req.userCache.getHeader(post.$author.id)
			let bookmarked = assumeBookmarked ?? userLikeDict[postID]?.isFavorite ?? false
			let userLike = userLikeDict[postID]?.likeType
			let likeCount = likeCountDict[postID] ?? 0
			return try PostData(
				post: post,
				author: author,
				bookmarked: bookmarked,
				userLike: userLike,
				likeCount: likeCount
			)
		}
		return postDataArray
	}

	// Scans the text of forum posts as they are created/edited/deleted, finds @mentions, updates mention counts for
	// mentioned `User`s.
	func processForumMentions(post: ForumPost, editedText: String?, isCreate: Bool = false, on req: Request)
		async throws
	{
		let postID = post.id ?? 0
		try await withThrowingTaskGroup(of: Void.self) { group in
			// Load the forum and category for this post, if we don't have it already. Usually these values are already loaded in.
			if post.$forum.value == nil {
				try await post.$forum.load(on: req.db)
			}
			if post.forum.$category.value == nil {
				try await post.forum.$category.load(on: req.db)
			}
			let accessLevelToView = post.forum.category.accessLevelToView
			let role = post.forum.category.requiredRole
			let canUserAccessCategory = { @Sendable (user: UserCacheData) -> UUID? in
				if !user.accessLevel.hasAccess(accessLevelToView) {
					return nil
				}
				if !user.accessLevel.hasAccess(.moderator), let role = role, !user.userRoles.contains(role) {
					return nil
				}
				return user.userID
			}
			let userDidntMentionSelf = { (userID: UUID) -> Bool in
				post.authorUUID != userID 
			}
			// Mentions
			let cacheUser = try req.auth.require(UserCacheData.self)
			let (subtracts, adds) = post.getMentionsDiffs(editedString: editedText, isCreate: isCreate)
			if !subtracts.isEmpty {
				let subtractUUIDs = req.userCache.getUsers(usernames: subtracts).compactMap(canUserAccessCategory).filter(userDidntMentionSelf)
				group.addTask {
					try await subtractNotifications(users: subtractUUIDs, type: .forumMention(postID), on: req)
				}
				if subtracts.map({ $0.lowercased() }).contains("twitarrteam") {
					let ttMembers = req.userCache.allUsersWithAccessLevel(.twitarrteam)
					group.addTask {
						try await subtractNotifications(users: ttMembers.filter({ $0.userID != cacheUser.userID}).map({ $0.userID }), type: .twitarrTeamForumMention(postID), on: req)
					}
				}
				if subtracts.map({ $0.lowercased()}).contains("moderator") {
					let modMembers = req.userCache.allUsersWithAccessLevel(.moderator)
					group.addTask {
						try await subtractNotifications(users: modMembers.filter({ $0.userID != cacheUser.userID}).map({ $0.userID }), type: .moderatorForumMention(postID), on: req)
					}
				}
			}
			if !adds.isEmpty {
				let addUUIDs = req.userCache.getUsers(usernames: adds).compactMap(canUserAccessCategory).filter(userDidntMentionSelf)
				var authorText = "A user"
				if let authorName = req.userCache.getUser(post.$author.id)?.username {
					authorText = "User @\(authorName)"
				}
				let infoStr = "\(authorText) wrote a forum post that @mentioned you."
				group.addTask {
					try await addNotifications(users: addUUIDs, type: .forumMention(postID), info: infoStr, on: req)
				}
				if adds.map({ $0.lowercased() }).contains("twitarrteam") {
					let ttMembers = req.userCache.allUsersWithAccessLevel(.twitarrteam)
					let infoStr = "\(authorText) wrote a forum post that @mentioned twitarrteam."
					group.addTask {
						try await addNotifications(users: ttMembers.filter({ $0.userID != cacheUser.userID}).map({ $0.userID }), type: .twitarrTeamForumMention(postID), info: infoStr, on: req)
					}
				}
				if adds.map({ $0.lowercased()}).contains("moderator") {
					let modMembers = req.userCache.allUsersWithAccessLevel(.moderator)
					let infoStr = "\(authorText) wrote a forum post that @mentioned moderator."
					group.addTask {
						try await addNotifications(users: modMembers.filter({ $0.userID != cacheUser.userID}).map({ $0.userID }), type: .moderatorForumMention(postID), info: infoStr, on: req)
					}
				}
			}
			// Alertwords
			let (alertSubtracts, alertAdds) = post.getAlertwordDiffs(editedString: editedText, isCreate: isCreate)
			let alertSet = try await req.redis.getAllAlertwords()
			let subtractingAlertWords = alertSubtracts.intersection(alertSet)
			let addingAlertWords = alertAdds.intersection(alertSet)
			subtractingAlertWords.forEach { word in
				group.addTask {
					let userIDs = try await req.redis.getUsersForAlertword(word)
					let validUserIDs = req.userCache.getUsers(userIDs).compactMap(canUserAccessCategory)
					try await subtractNotifications(users: validUserIDs, type: .alertwordPost(word, postID), on: req)
				}
			}
			if addingAlertWords.count > 0 {
				var authorText = "A user"
				if let authorName = req.userCache.getUser(post.$author.id)?.username {
					authorText = "User @\(authorName)"
				}
				addingAlertWords.forEach { word in
					let infoStr = "\(authorText) wrote a forum post containing your alert word '\(word)'."
					group.addTask {
						let userIDs = try await req.redis.getUsersForAlertword(word)
						let validUserIDs = req.userCache.getUsers(userIDs).compactMap(canUserAccessCategory)
						try await addNotifications(
							users: validUserIDs,
							type: .alertwordPost(word, postID),
							info: infoStr,
							on: req
						)
					}
				}
			}

			// Hashtags
			let hashtags = post.getHashtags()
			if !hashtags.isEmpty {
				group.addTask { try await req.redis.addHashtags(hashtags) }
			}
			// I believe this line is required to let subtasks propagate thrown errors by rethrowing.
			try await group.waitForAll()
		}
	}

	// Deleting a forum thread means we delete a bunch of posts at once. This fn coalesces the updates to User models
	// so that each User is updated at most one time for a thread deletion.
	func processThreadDeleteMentions(posts: [ForumPost], on req: Request) async throws {
		var mentionAdjustCounts = [String: Int]()
		posts.forEach { post in
			let (subtracts, _) = post.getMentionsDiffs(editedString: nil, isCreate: false)
			subtracts.forEach { username in
				var entry = mentionAdjustCounts[username] ?? 0
				entry += 1
				mentionAdjustCounts[username] = entry
			}
		}
		_ = try await withThrowingTaskGroup(of: Void.self) { group in
			mentionAdjustCounts.forEach { username, value in
				if let userID = req.userCache.getHeader(username)?.userID {
					group.addTask {
						try await subtractNotifications(
							users: [userID],
							type: .forumMention(0),
							subtractCount: value,
							on: req
						)
					}
				}
			}
			for try await _ in group {}
		}
		// FIXME: I believe this fn should also adjust alertword counts, but need to test first to prove it doesn't do the right thing.
	}
}

extension QueryBuilder {

	/// Given a `ForumPost`, `Forum`, or `Category` query, adds filters to the query to filter out entities in categories the current user cannot see.
	/// Joins the Category (and the Forum, if necessary) to the query to do this.
	@discardableResult func categoryAccessFilter(for possibleUser: UserCacheData?) -> Self {
		switch Model.self {
		case is ForumPost.Type:
			self.join(Forum.self, on: \Forum.$id == \ForumPost.$forum.$id)
			self.join(Category.self, on: \Category.$id == \Forum.$category.$id)
		case is Forum.Type:
			self.join(Category.self, on: \Category.$id == \Forum.$category.$id)
		case is Category.Type:
			break
		default: break
		}
		guard let user = possibleUser else {
			return self.filter(Category.self, \.$accessLevelToView <= .quarantined)
				.filter(Category.self, \.$requiredRole == nil)
		}
		self.filter(Category.self, \Category.$accessLevelToView <= user.accessLevel)
		if user.accessLevel >= .moderator {
			return self
		}
		if user.userRoles.isEmpty {
			return self.filter(Category.self, \.$requiredRole == nil)
		}

		return self.group(.or) { group in
			group.filter(Category.self, \.$requiredRole == nil).filter(Category.self, \.$requiredRole ~~ user.userRoles)
		}
	}

}
