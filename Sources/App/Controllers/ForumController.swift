import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/forum/*` route endpoints and handler functions related
/// to forums.

struct ForumController: APIRouteCollection {
        
	/// Required. Registers routes to the incoming router.
	func registerRoutes(_ app: Application) throws {
        
		// convenience route group for all /api/v3/forum endpoints
		let forumRoutes = app.grouped(DisabledAPISectionMiddleware(feature: .forums)).grouped("api", "v3", "forum")

		// Flex access endpoints
		let flexAuthGroup = addFlexCacheAuthGroup(to: forumRoutes)
		flexAuthGroup.get("categories", use: categoriesHandler)

		// Forum Route Group, requires token
		let tokenAuthGroup = addTokenAuthGroup(to: forumRoutes)
		let tokenCacheAuthGroup = addTokenCacheAuthGroup(to: forumRoutes)
		
			// Categories
		tokenCacheAuthGroup.get("categories", categoryIDParam, use: categoryForumsHandler)

			// Forums - CRUD first, then actions on forums
		tokenCacheAuthGroup.post("categories", categoryIDParam, "create", use: forumCreateHandler)
		tokenCacheAuthGroup.get(forumIDParam, use: forumHandler)
		tokenCacheAuthGroup.get("post", postIDParam, "forum", use: postForumHandler)			// Returns the forum a post is in.
		tokenCacheAuthGroup.get("forevent", ":event_id", use: eventForumHandler)
		tokenCacheAuthGroup.post(forumIDParam, "rename", ":new_name", use: forumRenameHandler)
		tokenCacheAuthGroup.post(forumIDParam, "delete", use: forumDeleteHandler)
		tokenCacheAuthGroup.delete(forumIDParam, use: forumDeleteHandler)
		
		tokenAuthGroup.post(forumIDParam, "report", use: forumReportHandler)

			// 'Favorite' applies to forums, while 'Bookmark' is for posts
		tokenCacheAuthGroup.get("favorites", use: favoritesHandler)
		tokenCacheAuthGroup.post(forumIDParam, "favorite", use: favoriteAddHandler)
		tokenCacheAuthGroup.post(forumIDParam, "favorite", "remove", use: favoriteRemoveHandler)
		tokenCacheAuthGroup.delete(forumIDParam, "favorite", use: favoriteRemoveHandler)

		tokenCacheAuthGroup.get("match", ":search_string", use: forumMatchHandler)
		tokenCacheAuthGroup.get("owner", use: ownerHandler)

			// Posts - CRUD first, then actions on posts
		tokenCacheAuthGroup.post(forumIDParam, "create", use: postCreateHandler)
		tokenCacheAuthGroup.get("post", postIDParam, use: postHandler)
		tokenCacheAuthGroup.post("post", postIDParam, "update", use: postUpateHandler)
		tokenCacheAuthGroup.post("post", postIDParam, "delete", use: postDeleteHandler)
		tokenCacheAuthGroup.delete("post", postIDParam, use: postDeleteHandler)

		tokenCacheAuthGroup.post("post", postIDParam, "laugh", use: postLaughHandler)
		tokenCacheAuthGroup.post("post", postIDParam, "like", use: postLikeHandler)
		tokenCacheAuthGroup.post("post", postIDParam, "love", use: postLoveHandler)
		tokenCacheAuthGroup.post("post", postIDParam, "unreact", use: postUnreactHandler)
		tokenCacheAuthGroup.delete("post", postIDParam, "laugh", use: postUnreactHandler)
		tokenCacheAuthGroup.delete("post", postIDParam, "like", use: postUnreactHandler)
		tokenCacheAuthGroup.delete("post", postIDParam, "love", use: postUnreactHandler)
		tokenAuthGroup.post("post", postIDParam, "report", use: postReportHandler)

			// 'Favorite' applies to forums, while 'Bookmark' is for posts
		tokenAuthGroup.post("post", postIDParam, "bookmark", use: bookmarkAddHandler)
		tokenAuthGroup.post("post", postIDParam, "bookmark", "remove", use: bookmarkRemoveHandler)
		tokenAuthGroup.delete("post", postIDParam, "bookmark", use: bookmarkRemoveHandler)

			// ForumPost search. Takes a bunch of options.
		tokenCacheAuthGroup.get("post", "search", use: postSearchHandler)
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
    /// - Returns: An array of <doc:CategoryData> containing all category IDs and titles. Or just the one, if you use the ?cat parameter.
    func categoriesHandler(_ req: Request) throws -> EventLoopFuture<[CategoryData]> {
        var effectiveAccessLevel: UserAccessLevel = .unverified
        if let user = req.auth.get(UserCacheData.self) {
        	effectiveAccessLevel = user.accessLevel
        }
    	let futureCategories = Category.query(on: req.db).filter(\.$accessLevelToView <= effectiveAccessLevel)
		if let catID = req.query[UUID.self, at: "cat"]  {
			futureCategories.filter(\.$id == catID)
		}
        return futureCategories.all().flatMapThrowing { (categories) in
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
				try CategoryData($0, restricted: $0.accessLevelToCreate > effectiveAccessLevel)
			}
        }
    }
        
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
        
    /// `GET /api/v3/forum/catgories/ID`
    ///
    /// Retrieve a list of forums in the specifiec `Category`. Will not return forums created by blocked users.
	/// 
	/// **URL Query Parameters:**
	/// * `?sort=[create, update, title]` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first.
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
	/// With no parameters, defaults to `?sort=create&start=0&limit=50`.
	/// 
	/// If you want to ensure you have all the threads in a category, you can sort by create time and ask for threads newer than 
	/// the last time you asked. If you want to update last post times and post counts, you can sort by update time and get the
	/// latest updates. 
    ///
    /// - Throws: 404 error if the category ID is not valid.
    /// - Returns: <doc:CategoryData> containing category forums.
    func categoryForumsHandler(_ req: Request) throws -> EventLoopFuture<CategoryData> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        let start = (req.query[Int.self, at: "start"] ?? 0)
        let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
        // get user's taggedForum barrel, and category
        return Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID).filter(\.$barrelType == .taggedForum).first()
        		.and(Category.findFromParameter(categoryIDParam, on: req).addModelID()).throwingFlatMap { (barrel, categoryTuple) in
            let (category, categoryID) = categoryTuple
            guard cacheUser.accessLevel.hasAccess(category.accessLevelToView) else {
            	throw Abort(.forbidden, reason: "User cannot view this forum category.")
            }
			// remove blocks from results, unless it's an admin category
			let blocked = category.accessLevelToCreate.hasAccess(.moderator) ? [] : cacheUser.getBlocks()
			// sort user categories
			let query = Forum.query(on: req.db)
					.filter(\.$category.$id == categoryID)
					.filter(\.$creator.$id !~ blocked)
					.range(start..<(start + limit))
			var dateFilterUsesUpdate = false
			switch req.query[String.self, at: "sort"] {
				case "update": _ = query.sort(\.$updatedAt, .descending); dateFilterUsesUpdate = true
				case "title": _ = query.sort(\.$title, .ascending)
				default: _ = query.sort(\.$createdAt, .descending)
			}
			if let beforeDate = req.query[Date.self, at: "beforedate"] {
				query.filter((dateFilterUsesUpdate ? \.$updatedAt : \.$createdAt) < beforeDate)
			}
			else if let afterDate = req.query[Date.self, at: "afterdate"] {
				query.filter((dateFilterUsesUpdate ? \.$updatedAt : \.$createdAt) > afterDate)
			}
			return query.all().throwingFlatMap { forums in
				return try buildForumListData(forums, on: req, userID: cacheUser.userID, favoritesBarrel: barrel).flatMapThrowing { forumList in
					return try CategoryData(category, restricted: category.accessLevelToCreate > cacheUser.accessLevel,
							forumThreads: forumList)
				}
			}
        }
    }
    
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
	/// Start and Limit do not take blocks and mutes into account, matching the behavior of the totalPosts values. Instead, when asking for e.g. the first 50 posts in a thread,
	/// you may only receive 46 posts, as 4 posts in that batch were blocked/muted. To continue reading the thread, ask to start with post 50 (not post 47)--you'll receive however
	/// many posts are viewable by the user in the range 50...99 . Doing it this way makes Forum read counts invariant to blocks--if a user reads a forum, then blocks a user, then
	/// comes back to the forum, they should come back to the same place they were in previously.
	///
	/// - Parameter forumID: in URL path
	/// - Throws: 404 error if the forum is not available.
	/// - Returns: <doc:ForumData> containing the forum's metadata and posts.
	func forumHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
		let user = try req.auth.require(UserCacheData.self)
		return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { forum in
			guard user.accessLevel.hasAccess(forum.accessLevelToView) else {
				throw Abort(.forbidden, reason: "User cannot view this forum category.")
			}
			return try buildForumData(forum, on: req)
		}
	}
	
	
	/// `GET /api/v3/forum/match/STRING`
	///
	/// Retrieve all `Forum`s in all categories whose title contains the specified string. Results will be sorted in decending order of creation time.
	/// Does not return results from categories for which the user does not have access.
	///
	/// **URL Query Parameters**:
	/// * `?start=INT` - The index into the array of forums to start returning results. 0 for first forum.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	///
	/// - Parameter searchString: In the URL path.
	/// - Returns: An array of <doc:ForumListData> containing all matching forums.
	func forumMatchHandler(_ req: Request) throws -> EventLoopFuture<ForumSearchData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		guard var search = req.parameters.get("search_string") else {
			throw Abort(.badRequest, reason: "Missing search parameter.")
		}
		let start = (req.query[Int.self, at: "start"] ?? 0)
		let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
		// postgres "_" and "%" are wildcards, so escape for literals
		search = search.replacingOccurrences(of: "_", with: "\\_")
		search = search.replacingOccurrences(of: "%", with: "\\%")
		search = search.trimmingCharacters(in: .whitespacesAndNewlines)
		// get user's blocks and taggedForum barrel
        return Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID).filter(\.$barrelType == .taggedForum).first()
				.throwingFlatMap { (barrel) in
			// get forums, remove blocks
			let blocked = cacheUser.getBlocks()
			let countQuery = Forum.query(on: req.db).filter(\.$creator.$id !~ blocked).filter(\.$title, .custom("ILIKE"), "%\(search)%")
					.filter(\.$accessLevelToView <= cacheUser.accessLevel)
			let resultQuery = countQuery.copy().sort(\.$createdAt, .descending).range(start..<(start + limit))
			return countQuery.count().and(resultQuery.all()).throwingFlatMap { (forumCount, forums) in
				return try buildForumListData(forums, on: req, userID: cacheUser.userID, favoritesBarrel: barrel).map { forumList in
					return ForumSearchData(paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
				}
			}
		}
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
	/// - Returns: <doc:ForumData> containing the post's parent forum.
	func postForumHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
		let user = try req.auth.require(UserCacheData.self)
		return ForumPost.findFromParameter(postIDParam, on: req).flatMap { post in
			return post.$forum.get(on: req.db).throwingFlatMap { forum in
				guard user.accessLevel.hasAccess(forum.accessLevelToView) else {
					throw Abort(.forbidden, reason: "User cannot view this forum.")
				}
				return try buildForumData(forum, on: req, startPostID: post.requireID())
			}
		}
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
	/// - Returns: <doc:ForumData> containing the forum's metadata and all posts.
	func eventForumHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
		let user = try req.auth.require(UserCacheData.self)
		return Event.findFromParameter("event_id", on: req).throwingFlatMap { event in
			guard let forumID = event.$forum.id else {
				throw Abort(.internalServerError, reason: "event has no forum")
			}
			return Forum.find(forumID, on: req.db).unwrap(or: Abort(.internalServerError, reason: "forum not found"))
					.throwingFlatMap { forum in
				guard user.accessLevel.hasAccess(forum.accessLevelToView) else {
					throw Abort(.forbidden, reason: "User cannot view this forum.")
				}
				return try buildForumData(forum, on: req)
			}
		}
	}


	/// `GET /api/v3/forum/post/ID`
	///
	/// Retrieve the specified `ForumPost` with full user `LikeType` data.
	///
	/// - Parameter postID: In the URL path.
	/// - Throws: 404 error if the post is not available.
	/// - Returns: <doc:PostDetailData> containing the specified post.
	func postHandler(_ req: Request) throws -> EventLoopFuture<PostDetailData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		return ForumPost.findFromParameter(postIDParam, on: req).addModelID().flatMap { (post, postID) in
			return post.$forum.load(on: req.db).throwingFlatMap {
				guard cacheUser.accessLevel.hasAccess(post.forum.accessLevelToView) else {
					throw Abort(.forbidden, reason: "User cannot view this forum.")
				}
				if cacheUser.getBlocks().contains(post.$author.id) || cacheUser.getMutes().contains(post.$author.id) ||
						post.containsMutewords(using: cacheUser.mutewords ?? []) {
					return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "post is not available"))
				}
				// get likes data and bookmark state
				let bookmarkFuture = Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID)
						.filter(\.$barrelType == .bookmarkedPost).first()
				let likesFuture = PostLikes.query(on: req.db).filter(\.$post.$id == postID).all()
				return likesFuture.and(bookmarkFuture).flatMapThrowing { (postLikes, bookmarkBarrel) in
					let bookmarked = try bookmarkBarrel?.userInfo["bookmarks"]?.contains(String(post.requireID())) ?? false
					let laughUsers = postLikes.filter { $0.likeType == .laugh }.map { $0.$user.id }
					let likeUsers = postLikes.filter { $0.likeType == .like }.map { $0.$user.id }
					let loveUsers = postLikes.filter { $0.likeType == .love }.map { $0.$user.id }
					// init return struct
					var postDetailData = try PostDetailData(post: post, author: req.userCache.getHeader(post.$author.id))
					postDetailData.isBookmarked = bookmarked
					postDetailData.laughs = req.userCache.getHeaders(laughUsers).map { SeaMonkey(header: $0) }
					postDetailData.likes = req.userCache.getHeaders(likeUsers).map { SeaMonkey(header: $0) }
					postDetailData.loves = req.userCache.getHeaders(loveUsers).map { SeaMonkey(header: $0) }
					return postDetailData
				}
			}
		}
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
	/// - Returns: <doc:PostSearchData> containing the search results..
	func postSearchHandler(_ req: Request) throws -> EventLoopFuture<PostSearchData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
        var postFilterMentions: String? = nil
        
        // BookmarkFuture is nil if we can't (or shouldn't) filter on bookmarks but [] if there aren't any bookmarks.
        var bookmarkFuture: EventLoopFuture<[Int]?> = req.eventLoop.makeSucceededFuture(nil)
        if let isBookmarked = req.query[String.self, at: "bookmarked"], isBookmarked == "true" {
        	bookmarkFuture = Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID).filter(\.$barrelType == .bookmarkedPost)
        			.first().map { barrel in
				return (barrel?.userInfo["bookmarks"] ?? []).compactMap { Int($0) }
			}        	
        }
		return bookmarkFuture.throwingFlatMap { bookmarks in
			let start = (req.query[Int.self, at: "start"] ?? 0)
			let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForumPosts)
			// Start building a query.
			// Note: The forum join() here is used to check access level, but other filters may require the join as well.
			var query = ForumPost.query(on: req.db).filter(\.$author.$id !~ cacheUser.getBlocks())
					.filter(\.$author.$id !~ cacheUser.getMutes())
					.sort(\.$id, .descending)
					.join(Forum.self, on: \ForumPost.$forum.$id == \Forum.$id)
					.filter(Forum.self, \.$accessLevelToView <= cacheUser.accessLevel)

			if let ownreacts = req.query[String.self, at: "ownreacts"], ownreacts == "true" {
				query.join(PostLikes.self, on: \ForumPost.$id == \PostLikes.$post.$id).filter(PostLikes.self, \.$user.$id == cacheUser.userID)
			//	query = user.$postLikes.query(on: req.db)
			}
			if let foundBookmarks = bookmarks {
				query.filter(\.$id ~~ foundBookmarks)
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
			
			if var searchStr = req.query[String.self, at: "search"] {
				searchStr = searchStr.replacingOccurrences(of: "_", with: "\\_")
						.replacingOccurrences(of: "%", with: "\\%")
						.trimmingCharacters(in: .whitespacesAndNewlines)
				query = query.filter(\.$text, .custom("ILIKE"), "%\(searchStr)%")
				if !searchStr.contains(" ") && start == 0 {
					markNotificationViewed(userID: cacheUser.userID, type: .alertwordPost(searchStr), on: req)
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
					let mentionedUser = req.userCache.getUser(mentionUUID) {
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
			}
			if let byself = req.query[Bool.self, at: "byself"], byself == true {
				query.filter(\.$author.$id == cacheUser.userID)
			}
			
			return query.count().flatMap { totalPosts in
				return query.range(start..<(start + limit)).all().throwingFlatMap { posts in
					// The filter() for mentions will include usernames that are prefixes for other usernames and other false positives.
					// This filters those out after the query. 
					var postFilteredPosts = posts
					if let postFilter = postFilterMentions {
						postFilteredPosts = posts.compactMap { $0.filterForMention(of: postFilter) }
						if postFilter == "@\(cacheUser.username)" {
							markNotificationViewed(userID: cacheUser.userID, type: .forumMention, on: req)
						}
					}
					return try buildPostData(postFilteredPosts, userID: cacheUser.userID, on: req, mutewords: cacheUser.mutewords).map { postData in
						return PostSearchData(queryString: req.url.query ?? "", totalPosts: totalPosts, 
								start: start, limit: limit, posts: postData)
					}
				}
			}
		}
	}
    
    /// `POST /api/v3/forum/post/ID/bookmark`
    ///
    /// Add a bookmark of the specified `ForumPost`.
    ///
    /// - Parameter postID: In the URL path.
    /// - Throws: 400 error if the post is already bookmarked.
    /// - Returns: 201 Created on success.
    func bookmarkAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get post and user's bookmarkedPost barrel
        return ForumPost.findFromParameter(postIDParam, on: req)
        	.and(user.getBookmarkBarrel(of: .bookmarkedPost, on: req.db))
        	.flatMapThrowing { (post, bookmarkBarrel) -> Barrel in
                // create barrel if needed
                let barrel = bookmarkBarrel ?? Barrel(ownerID: userID, barrelType: .bookmarkedPost, name: "Posts")
                // ensure bookmark doesn't exist
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                let postIDStr = try post.bookmarkIDString()
                guard !bookmarks.contains(postIDStr) else {
                    throw Abort(.badRequest, reason: "post already bookmarked")
                }
                // add post and return 201
                bookmarks.append(postIDStr)
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel
			}
			.flatMap { barrel in
                return barrel.save(on: req.db).transform(to: .created)
            }
    }
    
    /// `POST /api/v3/forum/post/ID/bookmark/remove`
    /// `DELETE /api/v3/forum/post/ID/bookmark`
    ///
    /// Remove a bookmark of the specified `ForumPost`.
    ///
    /// - Parameter postID: In the URL path.
    /// - Throws: 400 error if the user has not bookmarked any posts.
    /// - Returns: 204 NoContent on success.
    func bookmarkRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        // get post and user's bookmarkedPost barrel
        return ForumPost.findFromParameter(postIDParam, on: req)
        	.and(user.getBookmarkBarrel(of: .bookmarkedPost, on: req.db))
        	.flatMapThrowing { (post, bookmarkBarrel) -> Barrel in
                guard let barrel = bookmarkBarrel else {
                    throw Abort(.badRequest, reason: "user has not bookmarked any posts")
                }
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                // remove post and return 204
                let postIDStr = try post.bookmarkIDString()
                if let index = bookmarks.firstIndex(of: postIDStr) {
                    bookmarks.remove(at: index)
                }
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel
			}
			.flatMap { barrel in
                return barrel.save(on: req.db).transform(to: .noContent)
            }
    }
    
    /// `POST /api/v3/forum/ID/favorite`
    ///
    /// Add the specified `Forum` to the user's tagged forums list.
    ///
    /// - Parameter forumID: In the URL path.
    /// - Returns: 201 Created on success.
    func favoriteAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        // get forum and barrel
        let barrelFuture = Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID).filter(\.$barrelType == .taggedForum).first()
        return Forum.findFromParameter(forumIDParam, on: req).addModelID()
        		.and(barrelFuture.unwrap(orReplace: Barrel(ownerID: cacheUser.userID, barrelType: .taggedForum)))
        		.flatMap { (arg0, barrel) in
			let (_, forumID) = arg0
			// add forum and return 201
			if !barrel.modelUUIDs.contains(forumID) {
				barrel.modelUUIDs.append(forumID)
			}
			return barrel.save(on: req.db).transform(to: .created)
		}
    }
    
    /// `POST /api/v3/forum/ID/favorite/remove`
    /// `DELETE /api/v3/forum/ID/favorite`
    ///
    /// Remove the specified `Forum` from the user's tagged forums list.
    ///
    /// - Parameter forumID: In the URL path.
    /// - Throws: 400 error if the forum was not favorited.
    /// - Returns: 204 No Content on success.
    func favoriteRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        // get forum and barrel
        let barrelFuture = Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID).filter(\.$barrelType == .taggedForum).first()
        return Forum.findFromParameter(forumIDParam, on: req).addModelID()
				.and(barrelFuture).flatMap { (arg0, forumBarrel) in
			let (_, forumID) = arg0
			guard let barrel = forumBarrel else {
				return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "user has not tagged any forums"))
			}
			// remove forum
			guard let index = barrel.modelUUIDs.firstIndex(of: forumID) else {
				return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "forum was not tagged"))
			}
			barrel.modelUUIDs.remove(at: index)
			return barrel.save(on: req.db).transform(to: .noContent)
		}
    }
    
    /// `GET /api/v3/forum/favorites`
    ///
    /// Retrieve the `Forum`s in the user's taggedForum barrel, sorted by title.
	/// 
	/// **URL Query Parameters**:
	/// * `?sort=STRING` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first.
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
    ///
    /// - Returns: An array of  <doc:ForumListData> containing the user's favorited forums.
    func favoritesHandler(_ req: Request) throws -> EventLoopFuture<ForumSearchData> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        let start = (req.query[Int.self, at: "start"] ?? 0)
        let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
        // get user's taggedForum barrel
        return Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID).filter(\.$barrelType == .taggedForum).first()
       			.flatMap { (barrel) in
            guard let barrel = barrel else {
				let pager = Paginator(total: 0, start: start, limit: limit)
				return req.eventLoop.future(ForumSearchData(paginator: pager, forumThreads: []))
            }
			// get forums
			let countQuery = Forum.query(on: req.db).filter(\.$id ~~ barrel.modelUUIDs).filter(\.$creator.$id !~ cacheUser.getBlocks())
					.filter(\.$accessLevelToView <= cacheUser.accessLevel)
			let rangeQuery = countQuery.copy().range(start..<(start + limit))
			switch req.query[String.self, at: "sort"] {
				case "update": _ = rangeQuery.sort(\.$updatedAt, .descending);
				case "title": _ = rangeQuery.sort(\.$title, .ascending)
				default: _ = rangeQuery.sort(\.$createdAt, .descending)
			}
			return countQuery.count().and(rangeQuery.all()).throwingFlatMap { (forumCount, forums) in
				return try buildForumListData(forums, on: req, userID: cacheUser.userID, forceIsFavorite: true).map { forumList in
					return ForumSearchData(paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
				}
            }
        }
    }
    
    /// `POST /api/v3/forum/categories/ID/create`
    ///
    /// Creates a new `Forum` in the specified `Category`, and the first `ForumPost` within
    /// the newly created forum. Creating a forum in a category requires a `userAccessLevel` >= the category's `accessLevelToCreate`.
	/// 
	/// - Note: Users may be able to add posts to existing forum threads in categories where they don't have access to create new threads.
    ///
    /// - Parameter categoryID: in URL path
    /// - Parameter requestBody: <doc:ForumCreateData> payload in the HTTP body.
    /// - Throws: 403 error if the user is not authorized to create a forum.
    /// - Returns: <doc:ForumData> containing the new forum's contents.
    func forumCreateHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
        let cacheUser = try req.auth.require(UserCacheData.self)
		// see `ForumCreateData.validations()`
		try cacheUser.guardCanCreateContent()
		let data = try ValidatingJSONDecoder().decode(ForumCreateData.self, fromBodyOf: req)
        // check authorization to create
        return Category.findFromParameter(categoryIDParam, on: req).throwingFlatMap { (category) in
            guard cacheUser.accessLevel.hasAccess(category.accessLevelToCreate) else {
				return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "users cannot create forums in category"))
            }
			// process images
			return self.processImages(data.firstPost.images, usage: .forumPost, on: req).throwingFlatMap { (imageFilenames) in
				// create forum
				let forum = try Forum(title: data.title, category: category, creatorID: cacheUser.userID, isLocked: false)
				return forum.save(on: req.db).throwingFlatMap { (_) in
                    // create first post
					let forumPost = try ForumPost(forum: forum, authorID: cacheUser.userID, text: data.firstPost.text, images: imageFilenames)
                    // return as ForumData
                    return forumPost.save(on: req.db).flatMapThrowing { (_) in
                    	// Update Category
                    	_ = category.$forums.query(on: req.db).count().map { count -> EventLoopFuture<Void> in
                    		category.forumCount = Int32(count)
                    		return category.save(on: req.db)                    		
                    	}
                    	// If the post @mentions anyone, update their mention counts
                    	processForumMentions(forum: forum, post: forumPost, editedText: nil, isCreate: true, on: req)
                    
                    	let creatorHeader = cacheUser.makeHeader()
                    	let postData = try PostData(post: forumPost, author: creatorHeader, 
                    			bookmarked: false, userLike: nil, likeCount: 0)
						let forumData = try ForumData(forum: forum, creator: creatorHeader,
								isFavorite: false, posts: [postData], pager: Paginator(total: 1, start: 0, limit: 50))
						return forumData
                    }
                }
            }
        }
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
    func forumRenameHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let cacheUser = try req.auth.require(UserCacheData.self)
		guard let nameParameter = req.parameters.get("new_name"), nameParameter.count > 0 else {
			throw Abort(.badRequest, reason: "No new name parameter for forum name change.")
		}
        return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { (forum) in
            // must be forum owner or .moderator
			try cacheUser.guardCanModifyContent(forum, customErrorString: "User cannot modify forum title.")
			if forum.title != nameParameter {
				_ = try ForumEdit(forum: forum, editorID: cacheUser.userID).save(on: req.db)
            	forum.title = nameParameter
  				forum.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
				return forum.save(on: req.db).transform(to: .created)
			}
			return req.eventLoop.future(.created)
        }
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
    /// - Parameter requestBody: <doc:ReportData> payload in the HTTP body.
    /// - Returns: 201 Created on success.
    func forumReportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)
        return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { forum in
        	return try forum.fileReport(submitter: user, submitterMessage: data.message, on: req)
		}
    }
    
    /// `POST /api/v3/forum/ID/delete`
	/// `DELETE /api/v3/forum/ID`
    ///
    /// Delete the specified `Forum`. This soft-deletes the forum itself and all the forum's posts. The posts have to be deleted so they 
	/// won't be returned by search methods.
	/// 
	/// To delete, the user must have an access level allowing them to delete the forum. Currently this means moderators and above.
    ///
    /// - Parameter forumID: in URL path
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No Content on success.
    func forumDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        guard cacheUser.accessLevel.canEditOthersContent() else {
			throw Abort(.forbidden, reason: "User does not have access to delete forums.")
        }
        return Forum.findFromParameter(forumIDParam, on: req).flatMap { forum in
			return forum.$category.get(on: req.db).throwingFlatMap { category in
				try cacheUser.guardCanModifyContent(forum)
				forum.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
				return try ForumPost.query(on: req.db).filter(\.$forum.$id == forum.requireID()).all().throwingFlatMap { posts in
					processThreadDeleteMentions(posts: posts, on: req)
					let deleteFutures = posts.map { $0.delete(on: req.db) }
					return deleteFutures.flatten(on: req.eventLoop).flatMap {
						return forum.delete(on: req.db).flatMap { _ in
							// Update Category
							return category.$forums.query(on: req.db).count().flatMap { count in
								category.forumCount = Int32(count)
								return category.save(on: req.db).transform(to: .noContent)  
							}
						}
					}
				}
			}
        }
    }
	
    /// `GET /api/v3/forum/owner`
    ///
    /// Retrieve a list of all `Forum`s created by the user, sorted by title.
    ///
	/// **URL Query Parameters**:
	/// * `?start=INT` - The index into the array of forums to start returning results. 0 for first forum.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50. Clamped to a max value set in Settings.
	///
    /// - Returns: An array of <doc:ForumListData> containing all forums created by the user.
    func ownerHandler(_ req: Request) throws-> EventLoopFuture<ForumSearchData> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        let start = (req.query[Int.self, at: "start"] ?? 0)
        let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumForums)
        // get user's taggedForum barrel
        return Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID).filter(\.$barrelType == .taggedForum).first()
       			.flatMap { (barrel) in
            let countQuery = Forum.query(on: req.db).filter(\.$creator.$id == cacheUser.userID)
            		.filter(\.$accessLevelToView <= cacheUser.accessLevel)
            let resultQuery = countQuery.copy().sort(\.$title, .ascending).range(start..<(start + limit))
			return countQuery.count().and(resultQuery.all()).throwingFlatMap { (forumCount, forums) in
				return try buildForumListData(forums, on: req, userID: cacheUser.userID, favoritesBarrel: barrel).map { forumList in
					return ForumSearchData(paginator: Paginator(total: forumCount, start: start, limit: limit), forumThreads: forumList)
				}
			}
        }
    }
    
    /// `POST /api/v3/forum/ID/create`
    ///
    /// Create a new `ForumPost` in the specified `Forum`.
    ///
    /// - Parameter forumID: in URL path
    /// - Parameter requestBody: <doc:PostContentData>
    /// - Throws: 403 error if the forum is locked or user is blocked.
    /// - Returns: <doc:PostData> containing the post's contents and metadata.
    func postCreateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        // see `PostContentData.validations()`
 		let newPostData = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
        // get forum
        return Forum.findFromParameter(forumIDParam, on: req).throwingFlatMap { forum in
			try guardUserCanPostInForum(cacheUser, in: forum)
            // ensure user has access to forum; user cannot retrieve block-owned forum, but prevent end-run
			guard !cacheUser.getBlocks().contains(forum.$creator.id) else {
				throw Abort(.forbidden, reason: "user cannot post in forum")
			}
			// process images
			return self.processImages(newPostData.images, usage: .forumPost, on: req).throwingFlatMap { (filenames) in
				// create post
				let effectiveAuthor = newPostData.effectiveAuthor(actualAuthor: cacheUser, on: req)
				let forumPost = try ForumPost(forum: forum, authorID: effectiveAuthor.userID, text: newPostData.text, images: filenames)
				return forumPost.save(on: req.db).flatMapThrowing { (_) in
					// If the post @mentions anyone, update their mention counts
					processForumMentions(forum: forum, post: forumPost, editedText: nil, isCreate: true, on: req)
					// return as PostData, with 201 status
					let response = Response(status: .created)
					try response.content.encode(PostData(post: forumPost, author: effectiveAuthor.makeHeader()))
					return response
				}
			}
        }
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
    func postDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        return ForumPost.findFromParameter(postIDParam, on: req).flatMap { post in
        	return post.$forum.load(on: req.db).throwingFlatMap {
				try guardUserCanPostInForum(cacheUser, in: post.forum, editingPost: post)
  				post.logIfModeratorAction(.delete, moderatorID: cacheUser.userID, on: req)
				processForumMentions(forum: post.forum, post: post, editedText: nil, on: req)
        	    return post.delete(on: req.db).transform(to: .noContent)
			}
        }
    }
    
    /// `POST /api/v3/forum/post/ID/report`
    ///
    /// Create a `Report` regarding the specified `ForumPost`.
    ///
    /// - Note: The accompanying report message is optional on the part of the submitting user,
    ///   but the `ReportData` is mandatory in order to allow one. If there is no message,
    ///   send an empty string in the `.message` field.
    ///
    /// - Parameter requestBody:<doc:ReportData`> 
    /// - Throws: 409 error if user has already reported the post.
    /// - Returns: 201 Created on success.
    func postReportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)
        return ForumPost.findFromParameter(postIDParam, on: req).throwingFlatMap { post in
        	return try post.fileReport(submitter: user, submitterMessage: data.message, on: req)
		}
    }
    
    /// `POST /api/v3/forum/post/ID/laugh`
    ///
    /// Add a "laugh" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter postID: in URL path
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: <doc:PostData> containing the updated like info.
    func postLaughHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .laugh)
    }
    
	/// `POST /api/v3/forum/post/ID/like`
    ///
    /// Add a "like" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter postID: in URL path
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: <doc:PostData> containing the updated like info.
    func postLikeHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .like)
	}
    
    /// `POST /api/v3/forum/post/ID/love`
    ///
    /// Add a "love" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter postID: in URL path
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: <doc:PostData> containing the updated like info.
    func postLoveHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .love)
	}
	
	func postReactHandler(_ req: Request, likeType: LikeType) throws -> EventLoopFuture<PostData> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        // get post
        return ForumPost.findFromParameter(postIDParam, on: req).addModelID().flatMap { (post, postID) in
        	return post.$forum.load(on: req.db).throwingFlatMap {
				guard post.$author.id != cacheUser.userID else {
					throw Abort(.forbidden, reason: "user cannot like own post")
				}
				guard cacheUser.accessLevel.hasAccess(post.forum.accessLevelToView) else {
					throw Abort(.forbidden, reason: "User cannot view this forum.")
				}
				return PostLikes.query(on: req.db).filter(\.$user.$id == cacheUser.userID).filter(\.$post.$id == postID)
						.first().throwingFlatMap { existingLike in
					let postLike = try existingLike ?? PostLikes(cacheUser.userID, post)
					postLike.likeType = likeType
					return postLike.save(on: req.db).throwingFlatMap { 
						return try buildPostData([post], userID: cacheUser.userID, on: req).map { postDataArray in
							return postDataArray[0]
						}
					}
				}
			}
		}
	}
    
    /// `POST /api/v3/forum/post/ID/unreact`
    /// `DELETE /api/v3/forum/post/ID/like`
    /// `DELETE /api/v3/forum/post/ID/laugh`
    /// `DELETE /api/v3/forum/post/ID/love`
    ///
    /// Remove a `LikeType` reaction from the specified `ForumPost`.
    ///
    /// - Parameter postID: in URL path
    /// - Throws: 400 error if there was no existing reaction. 403 error if user is the post's creator.
    /// - Returns: <doc:PostData> containing the updated like info.
    func postUnreactHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
        let cacheUser = try req.auth.require(UserCacheData.self)
        // get post
        return ForumPost.findFromParameter(postIDParam, on: req).addModelID().flatMap { (post, postID) in
        	return post.$forum.load(on: req.db).throwingFlatMap {
				guard post.$author.id != cacheUser.userID else {
					return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own post"))
				}
				guard cacheUser.accessLevel.hasAccess(post.forum.accessLevelToView) else {
					throw Abort(.forbidden, reason: "User cannot view this forum.")
				}
				// check for existing like
				return PostLikes.query(on: req.db)
						.filter(\.$user.$id == cacheUser.userID)
						.filter(\.$post.$id == postID)
						.first()
						.unwrap(or: Abort(.badRequest, reason: "user does not have a reaction on the post"))
						.throwingFlatMap { (like) in
					// remove pivot
					return like.delete(on: req.db).throwingFlatMap { (_) in
						return try buildPostData([post], userID: cacheUser.userID, on: req).map { postDataArray in
							return postDataArray[0]
						}
					}
				}
			}
        }
    }
    
    /// `POST /api/v3/forum/post/ID/update`
    ///
    /// Update the specified `ForumPost`.
    ///
    /// - Parameter postID: in URL path
    /// - Parameter requestBody: <doc:PostContentData> 
    /// - Throws: 403 error if user is not post owner or has read-only access.
    /// - Returns: <doc:PostData> containing the post's contents and metadata.
    func postUpateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let cacheUser = try req.auth.require(UserCacheData.self)
		// see `PostContentData.validations()`
		let newPostData = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
        return ForumPost.findFromParameter(postIDParam, on: req).addModelID().flatMap { (post, postID) in
        	return post.$forum.load(on: req.db).throwingFlatMap {
				// ensure user has write access, the post can be modified by them, and the forum isn't locked.
				try guardUserCanPostInForum(cacheUser, in: post.forum, editingPost: post)
				guard cacheUser.accessLevel.hasAccess(post.forum.accessLevelToView) else {
					throw Abort(.forbidden, reason: "User cannot view this forum.")
				}
				// process images
				return self.processImages(newPostData.images, usage: .forumPost, on: req).throwingFlatMap { (filenames) in
					// update if there are changes
					let normalizedText = newPostData.text.replacingOccurrences(of: "\r\n", with: "\r")
					if post.text != normalizedText || post.images != filenames {
                    	// If the post @mentions anyone, update their mention counts
                    	processForumMentions(forum: post.forum, post: post, editedText: normalizedText, on: req)
						// stash current contents first
						let forumEdit = try ForumPostEdit(post: post, editorID: cacheUser.userID)
						post.text = normalizedText
						post.images = filenames
  						post.logIfModeratorAction(.edit, moderatorID: cacheUser.userID, on: req)
						return post.save(on: req.db).and(forumEdit.save(on: req.db)).transform(to: (post, true))
					}
					return req.eventLoop.future((post, false))
				}
				.throwingFlatMap { (post, wasCreated: Bool) in
					// return updated post as PostData, with 200 or 201 status
					return try buildPostData([post], userID: cacheUser.userID, on: req).flatMapThrowing { postDataArray in
						let response = Response(status: wasCreated ? .created : .ok)
						try response.content.encode(postDataArray[0])
						return response
					}
				}
			}
		}
    }
}

// Utilities for route methods
extension ForumController {

	/// Ensures the given user has appropriate access to create or edit posts in the given forum. If editing a post, you must pass the post in the `editingPost` parameter.
	func guardUserCanPostInForum(_ user: User, in forum: Forum, editingPost: ForumPost? = nil) throws {
		if let post = editingPost {
			try user.guardCanModifyContent(post) 
		}
		else {
			try user.guardCanCreateContent()
		}
		guard user.accessLevel.canEditOthersContent() || (forum.moderationStatus == .normal || forum.moderationStatus == .modReviewed) else {
			throw Abort(.forbidden, reason: "Forum is locked.")
		}
	}
	
	/// Ensures the given user has appropriate access to create or edit posts in the given forum. If editing a post, you must pass the post in the `editingPost` parameter.
	func guardUserCanPostInForum(_ user: UserCacheData, in forum: Forum, editingPost: ForumPost? = nil) throws {
		if let post = editingPost {
			try user.guardCanModifyContent(post) 
		}
		else {
			try user.guardCanCreateContent()
		}
		guard user.accessLevel.canEditOthersContent() || (forum.moderationStatus == .normal || forum.moderationStatus == .modReviewed) else {
			throw Abort(.forbidden, reason: "Forum is locked.")
		}
	}
	
	/// Builds an array of `ForumListData` from the given `Forums`. `ForumListData` does not return post content, but does return post counts.
	func buildForumListData(_ forums: [Forum], on req: Request, userID: UUID,
			favoritesBarrel: Barrel? = nil, forceIsFavorite: Bool? = nil) throws -> EventLoopFuture<[ForumListData]> {
		// get forum metadata
		let forumIDs = try forums.map { try $0.requireID() }
		let forumPostCountsFuture = try forums.childCountsPerModel(atPath: \.$posts, on: req.db)
//		let readerPivotsFuture = user.$readForums.$pivots.query(on: req.db).filter(\.$forum.$id ~~ forumIDs).all()
		let readerPivotsFuture = ForumReaders.query(on: req.db).filter(\.$user.$id == userID).filter(\.$forum.$id ~~ forumIDs).all()
		let forumLastPostsFuture: [EventLoopFuture<ForumPost?>] = forums.map { forum in
			forum.$posts.query(on: req.db).sort(\.$createdAt, .descending).first()
		}
		// resolve futures
		return forumPostCountsFuture.and(readerPivotsFuture).flatMap { (postCounts, readerPivots) in
			return forumLastPostsFuture.flatten(on: req.eventLoop).flatMapThrowing { forumLastPosts in
				let postEnumeration: [(UUID, ForumPost)] = forumLastPosts.compactMap {
					if let post = $0 { 
						return (post.$forum.id, post) 
					}
					else {
						return nil
					}
				}
				let lastPostsDict = Dictionary(postEnumeration, uniquingKeysWith: { (first, _) in first })
				let readerPivotsDict = Dictionary(readerPivots.map { ($0.$forum.id, $0) }, 
						 uniquingKeysWith: { (first, _) in first })
				let returnListData: [ForumListData] = try forums.map { forum in
					let forumID = try forum.requireID()
					let creatorHeader = try req.userCache.getHeader(forum.$creator.id)
					var lastPosterHeader: UserHeader? 
					var lastPostTime: Date? 
					if let lastPost = lastPostsDict[forumID] {
						lastPosterHeader = try req.userCache.getHeader(lastPost.$author.id)
						lastPostTime = lastPost.createdAt
					}
					return try ForumListData(forum: forum, creator: creatorHeader, postCount: postCounts[forumID] ?? 0, 
							readCount: readerPivotsDict[forumID]?.readCount ?? 0, 
							lastPostAt: lastPostTime, lastPoster: lastPosterHeader,
							isFavorite: forceIsFavorite ?? favoritesBarrel?.contains(forum) ?? false)
				}
				return returnListData
			}
		}
	}
	
	/// Builds a `ForumData` with the contents of the given `Forum`. Uses the requests' "limit" and "start" query parameters
	/// to return only a subset of the forums' posts (for forums where postCount > limit).
	func buildForumData(_ forum: Forum, on req: Request, startPostID: Int? = nil) throws -> EventLoopFuture<ForumData> {
		let cacheUser = try req.auth.require(UserCacheData.self)
		return forum.$posts.query(on: req.db).count().flatMap { postCount in
			let barrelFuture = Barrel.query(on: req.db).filter(\.$ownerID == cacheUser.userID).filter(\.$barrelType == .taggedForum).first()
			return forum.$readers.$pivots.query(on: req.db).filter(\.$user.$id == cacheUser.userID).first()
					.and(barrelFuture).flatMap { (readerPivot, favoriteForumBarrel) in
				let clampedReadCount = min(readerPivot?.readCount ?? 0, postCount)
				let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 1...Settings.shared.maximumForumPosts)
				var future: EventLoopFuture<(Int?, Int)>
				if let startParam = req.query[Int.self, at: "start"] {
					let startCount = max(startParam, 0)
					// Get the 'start' post without filtering blocks and mutes
					future = forum.$posts.query(on: req.db)
							.sort(\.$createdAt, .ascending)
							.range(startCount...startCount)
							.first()
							.flatMapThrowing { startPost in
						return try (startPost?.requireID(), startCount)
					}
				}
				else if let startPostIDParam = req.query[Int.self, at: "startPost"] {
					future = forum.$posts.query(on: req.db).filter(\.$id < startPostIDParam).count().map { (startCount: Int) in
						return (startPostIDParam, startCount)
					}
				}
				else if let directStartPostID = startPostID {
					future = forum.$posts.query(on: req.db).filter(\.$id < directStartPostID).count().map { (startCount: Int) in
						return (directStartPostID, startCount)
					}
				}
				else {
					let defaultStart = max((clampedReadCount / limit) * limit, 0)
					// Get the 'start' post without filtering blocks and mutes
					future = forum.$posts.query(on: req.db)
							.sort(\.$createdAt, .ascending)
							.range(defaultStart...defaultStart)
							.first()
							.flatMapThrowing { startPost in
						return try (startPost?.requireID(), defaultStart)
					}
				}
				return future.throwingFlatMap { (resolvedStartPostID: Int?, start: Int) in
					// filter posts
					var query = forum.$posts.query(on: req.db)
							.filter(\.$author.$id !~ cacheUser.getBlocks())
							.filter(\.$author.$id !~ cacheUser.getMutes())
							.sort(\.$createdAt, .ascending)
					if let resolvedStartPostID = resolvedStartPostID {
						query = query.range(0..<limit).filter(\.$id >= resolvedStartPostID)
					}
					else {
						query = query.range(start...start + limit)
					}
					return query.all().throwingFlatMap { (posts) -> EventLoopFuture<ForumData> in
						if let pivot = readerPivot {
							let newReadCount = min(start + limit, postCount)
							if newReadCount > pivot.readCount || pivot.readCount > postCount {
								pivot.readCount = newReadCount
								_ = pivot.save(on: req.db)
							}
						}
						else {
							let newReader = try ForumReaders(cacheUser.userID, forum)
							newReader.readCount = min(start + limit, postCount)
							_ = newReader.save(on: req.db)
						}
						return try buildPostData(posts, userID: cacheUser.userID, on: req, mutewords: cacheUser.mutewords).flatMapThrowing { flattenedPosts in
							let creatorHeader = try req.userCache.getHeader(forum.$creator.id)
							let pager = Paginator(total: postCount, start: start, limit: limit)
							let result = try ForumData(forum: forum, creator: creatorHeader, 
									isFavorite: favoriteForumBarrel?.contains(forum) ?? false, posts: flattenedPosts, pager: pager)
							return result
						}
					}
				}
			}
		}
	}
		
	// Builds an array of PostData structures from the given posts, adding the user's bookmarks and likes
	// for the post, as well as the total count of likes. The optional parameters are for callers that
	// only need some of the functionality, or for whom some of the values are known in advance e.g.
	// the method that returns a user's bookmarked posts can assume all the posts it finds are in fact bookmarked.
	func buildPostData(_ posts: [ForumPost], userID: UUID, on req: Request, mutewords: [String]? = nil, 
			assumeBookmarked: Bool? = nil, assumeLikeType: LikeType? = nil, matchHashtag: String? = nil) throws -> EventLoopFuture<[PostData]> {
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
		let bookmarkFuture = Barrel.query(on: req.db).filter(\.$ownerID == userID)
				.filter(\.$barrelType == .bookmarkedPost).first()
		let userLikesFuture = PostLikes.query(on: req.db).filter(\.$post.$id ~~ postIDs)
					.filter(\.$user.$id == userID).all()
		let likeCountsFuture = try filteredPosts.childCountsPerModel(atPath: \.$likes.$pivots, on: req.db)
		return bookmarkFuture.and(userLikesFuture).and(likeCountsFuture).flatMapThrowing { (arg0, likeCountDict) in
			let (bookmarkBarrel, userLikes) = arg0
			let bookmarks = bookmarkBarrel?.userInfo["bookmarks"] ?? []
			let userLikeDict = Dictionary(userLikes.map { ($0.$post.id, $0) }, uniquingKeysWith: { (first, _) in first })

			let postDataArray = try filteredPosts.map { post -> PostData in 
				let postID = try post.requireID()
				let author = try req.userCache.getHeader(post.$author.id)
				let bookmarked = try assumeBookmarked ?? bookmarks.contains(post.bookmarkIDString())
				let userLike = userLikeDict[postID]?.likeType
				let likeCount = likeCountDict[postID] ?? 0
				return try PostData(post: post, author: author, bookmarked: bookmarked, userLike: userLike, likeCount: likeCount)
			}
			return postDataArray
		}
	}
	
	// Scans the text of forum posts as they are created/edited/deleted, finds @mentions, updates mention counts for
	// mentioned `User`s.
	@discardableResult func processForumMentions(forum: Forum, post: ForumPost, editedText: String?, 
			isCreate: Bool = false, on req: Request) -> EventLoopFuture<Void> {
// Mentions
		var futures: [EventLoopFuture<Void>] = []
		let (subtracts, adds) = post.getMentionsDiffs(editedString: editedText, isCreate: isCreate)
		if !subtracts.isEmpty {
			let subtractUUIDs = req.userCache.getUsers(usernames: subtracts).compactMap { 
				$0.accessLevel.hasAccess(forum.accessLevelToView) ? $0.userID : nil
			}
			futures.append(subtractNotifications(users: subtractUUIDs, type: .forumMention, on: req))
		}
		if !adds.isEmpty {
			let addUUIDs = req.userCache.getUsers(usernames: adds).compactMap { 
				$0.accessLevel.hasAccess(forum.accessLevelToView) ? $0.userID : nil
			}
			var authorText = "A user"
			if let authorName = req.userCache.getUser(post.$author.id)?.username {
				authorText = "User @\(authorName)"
			}
			let infoStr = "\(authorText) wrote a forum post that @mentioned you."
			futures.append(addNotifications(users: addUUIDs, type: .forumMention, info: infoStr, on: req))
		}
// Alertwords
		let (alertSubtracts, alertAdds) = post.getAlertwordDiffs(editedString: editedText, isCreate: isCreate)
		futures.append(req.redis.zrangebyscore(from: "alertwords", withMinimumScoreOf: 1.0).flatMap { alertwords in 
			let alertSet = Set(alertwords.compactMap { String.init(fromRESP: $0) })
			let subtractingAlertWords = alertSubtracts.intersection(alertSet)
			let addingAlertWords = alertAdds.intersection(alertSet)
			var wordFutures: [EventLoopFuture<Void>] = []
			subtractingAlertWords.forEach { word in
				wordFutures.append(subtractAlertwordNotifications(type: .alertwordPost(word), minAccess: forum.accessLevelToView, on: req))
			}
			if addingAlertWords.count > 0 {
				var authorText = "A user"
				if let authorName = req.userCache.getUser(post.$author.id)?.username {
					authorText = "User @\(authorName)"
				}
				addingAlertWords.forEach { word in
					let infoStr = "\(authorText) wrote a forum post containing your alert word '\(word)'."
					wordFutures.append(addAlertwordNotifications(type: .alertwordPost(word), minAccess: forum.accessLevelToView,
							info: infoStr, on: req))
				}
			}
			return wordFutures.flatten(on: req.eventLoop).transform(to: ())
		})
// Hashtags
		let hashtags = post.getHashtags().map { ($0, 0.0 ) }
		futures.append(hashtags.isEmpty ? req.eventLoop.future() : req.redis.zadd(hashtags, to: "hashtags").transform(to: ()))

		return futures.flatten(on: req.eventLoop).transform(to: ())
	}
	
	// Deleting a forum thread means we delete a bunch of posts at once. This fn coalesces the updates to User models
	// so that each User is updated at most one time for a thread deletion.
	@discardableResult func processThreadDeleteMentions(posts: [ForumPost], on req: Request) -> EventLoopFuture<Void> {
		var mentionAdjustCounts = [String : Int]()
		posts.forEach { post in
			let (subtracts, _) = post.getMentionsDiffs(editedString: nil, isCreate: false)
			subtracts.forEach { username in
				var entry = mentionAdjustCounts[username] ?? 0
				entry += 1
				mentionAdjustCounts[username] = entry
			}
		}
		return mentionAdjustCounts.compactMap { username, value in
			if let userID = req.userCache.getHeader(username)?.userID {
				return subtractNotifications(users: [userID], type: .forumMention, subtractCount: value, on: req)
			}
			return nil
		}.flatten(on: req.eventLoop)
	}
}
