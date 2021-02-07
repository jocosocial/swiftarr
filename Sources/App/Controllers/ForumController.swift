import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/forum/*` route endpoints and handler functions related
/// to forums.

struct ForumController: RouteCollection {
    // MARK: RouteCollection Conformance
        
    /// Required. Registers routes to the incoming router.
    func boot(routes: RoutesBuilder) throws {
        
        // convenience route group for all /api/v3/forum endpoints
        let forumRoutes = routes.grouped("api", "v3", "forum")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.authenticator()
        let guardAuthMiddleware = User.guardMiddleware()
        let tokenAuthMiddleware = Token.authenticator()
        
        // set protected route groups
        let sharedAuthGroup = forumRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = forumRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        forumRoutes.get("categories", use: categoriesHandler)
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        sharedAuthGroup.get(":forum_id", use: forumHandler)
        sharedAuthGroup.get("categories", ":category_id", use: categoryForumsHandler)
        sharedAuthGroup.get("match", ":search_string", use: forumMatchHandler)
        sharedAuthGroup.get("post", ":post_id", use: postHandler)
        sharedAuthGroup.get("post", ":post_id", "forum", use: postForumHandler)
        sharedAuthGroup.get("post", "hashtag", ":hashtag_string", use: postHashtagHandler)
        sharedAuthGroup.get("post", "search", ":search_string", use: postSearchHandler)
        sharedAuthGroup.get(":forum_id", "search", ":search_string", use: forumSearchHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.get("bookmarks", use: bookmarksHandler)
        tokenAuthGroup.post("categories", ":category_id", "create", use: forumCreateHandler)
        tokenAuthGroup.post(":forum_id", "favorite", use: favoriteAddHandler)
        tokenAuthGroup.post(":forum_id", "favorite", "remove", use: favoriteRemoveHandler)
        tokenAuthGroup.get("favorites", use: favoritesHandler)
        tokenAuthGroup.get("likes", use: likesHandler)
        tokenAuthGroup.post(":forum_id", "lock", use: forumLockHandler)
        tokenAuthGroup.get("mentions", use: mentionsHandler)
        tokenAuthGroup.get("owner", use: ownerHandler)
        tokenAuthGroup.post("post", ":post_id", "bookmark", use: bookmarkAddHandler)
        tokenAuthGroup.post("post", ":post_id", "bookmark", "remove", use: bookmarkRemoveHandler)
        tokenAuthGroup.post(":forum_id", "create", use: postCreateHandler)
        tokenAuthGroup.post("post", ":post_id", "delete", use: postDeleteHandler)
        tokenAuthGroup.post("post", ":post_id", "image", use: imageHandler)
        tokenAuthGroup.post("post", ":post_id", "image", "remove", use: imageRemoveHandler)
        tokenAuthGroup.post("post", ":post_id", "laugh", use: postLaughHandler)
        tokenAuthGroup.post("post", ":post_id", "like", use: postLikeHandler)
        tokenAuthGroup.post("post", ":post_id", "love", use: postLoveHandler)
        tokenAuthGroup.post("post", ":post_id", "report", use: postReportHandler)
        tokenAuthGroup.post("posts", use: postsHandler)
        tokenAuthGroup.post("post", ":post_id", "unreact", use: postUnreactHandler)
        tokenAuthGroup.post("post", ":post_id", "update", use: postUpateHandler)
        tokenAuthGroup.post(":forum_id", "rename", ":new_name", use: forumRenameHandler)
        tokenAuthGroup.post(":forum_id", "report", use: forumReportHandler)
        tokenAuthGroup.post(":forum_id", "unlock", use: forumUnlockHandler)

    }
    
    // MARK: - Open Access Handlers

    /// `GET /api/v3/forum/categories`
    ///
    /// Retrieve a list of all forum `Category`s, sorted by type (admin, user)
    /// and title. 
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[CategoryData]` containing all category IDs and titles.
    func categoriesHandler(_ req: Request) throws -> EventLoopFuture<[CategoryData]> {
        return Category.query(on: req.db)
			.all()
            .flatMapThrowing { (categories) in
            	let sortedCats = categories.sorted {
            		return $0.isRestricted == $1.isRestricted ? $0.title < $1.title : $0.isRestricted
            	}
                // return as CategoryData
                return try sortedCats.map {
                    try CategoryData(categoryID: $0.requireID(), title: $0.title, isRestricted: $0.isRestricted)
                }
        }
    }
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/forum/catgories/ID`
    ///
    /// Retrieve a list of all forums in the specifiec `Category`. Will not return forums created by blocked users.
	/// 
	/// * `?sort=STRING` - Sort forums by `create`, `update`, or `title`. Create and update return newest forums first.
	/// * `?start=INT` - The index into the sorted list of forums to start returning results. 0 for first item, which is the default.
	/// * `?limit=INT` - The max # of entries to return. Defaults to 50
	/// 
	/// These options set the anchor point for returning threads. By default the anchor is 'newest create date'. When sorting on 
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
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the category ID is not valid.
    /// - Returns: `[ForumListData]` containing all category forums.
    func categoryForumsHandler(_ req: Request) throws -> EventLoopFuture<[ForumListData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        let start = (req.query[Int.self, at: "start"] ?? 0)
        let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...200)
        // get user's taggedForum barrel, and category
        return user.getBookmarkBarrel(of: .taggedForum, on: req)
        	.and(Category.findFromParameter("category_id", on: req).addModelID()).flatMap {
            (barrel, categoryTuple) in
            let (category, categoryID) = categoryTuple
			// remove blocks from results, unless it's an admin category
			let blocked = category.isRestricted ? [] : req.userCache.getBlocks(userID)
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
			return query.all().flatMap { (forums) in
				return buildForumListData(forums, on: req, favoritesBarrel: barrel)
			}
        }
    }
    
    /// `GET /api/v3/forum/ID`
    ///
    /// Retrieve a `Forum` with all its `ForumPost`s. Content from blocked or muted users,
    /// or containing user's muteWords, is not returned.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the forum is not available.
    /// - Returns: `ForumData` containing the forum's metadata and all posts.
    func forumHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
        let user = try req.auth.require(User.self)
        let cacheUser = try req.userCache.getUser(user)
        // get user's taggedForum barrel
		return user.getBookmarkBarrel(of: .taggedForum, on: req)
				.and(Forum.findFromParameter("forum_id", on: req)).flatMap { (barrel, forum) in
			// filter posts
			return forum.$posts.query(on: req.db)
				.filter(\.$author.$id !~ cacheUser.getBlocks())
				.filter(\.$author.$id !~ cacheUser.getMutes())
				.sort(\.$createdAt, .ascending)
				.all()
				.flatMap { (posts) -> EventLoopFuture<ForumData> in
					return buildForumData(forum, posts: posts, user: user, on: req, 
							mutewords: cacheUser.mutewords, favoriteForumBarrel: barrel)
				}
        }
    }
    
    /// `GET /api/v3/forum/match/STRING`
    ///
    /// Retrieve all `Forum`s whose title contains the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumListData]` containing all matching forums.
    func forumMatchHandler(_ req: Request) throws -> EventLoopFuture<[ForumListData]> {
        let user = try req.auth.require(User.self)
        guard var search = req.parameters.get("search_string") else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
		// get user's blocks and taggedForum barrel
		return user.getBookmarkBarrel(of: .taggedForum, on: req)
     		.throwingFlatMap { (barrel) in
                // get forums, remove blocks
        		let blocked = try req.userCache.getBlocks(user)
                return Forum.query(on: req.db)
                    .filter(\.$creator.$id !~ blocked)
                    .filter(\.$title, .custom("ILIKE"), "%\(search)%")
                    .all()
                    .flatMap { (forums) in
                    	return buildForumListData(forums, on: req, favoritesBarrel: barrel)
                	}
            }
    }
    
    /// `GET /api/v3/forum/ID/search/STRING`
    ///
    /// Retrieve all `ForumPost`s in the specified `Forum` that contain the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all matching posts in the forum.
    func forumSearchHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        guard var search = req.parameters.get("search_string") else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
        }
		// postgres "_" and "%" are wildcards, so escape for literals
		search = search.replacingOccurrences(of: "_", with: "\\_")
		search = search.replacingOccurrences(of: "%", with: "\\%")
		search = search.trimmingCharacters(in: .whitespacesAndNewlines)
		// get forum and cached blocks
        return Forum.findFromParameter("forum_id", on: req)
        	.and(ForumPost.getCachedFilters(for: user, on: req))
        	.flatMap { (forum, filters) in
                // get posts
                return forum.$posts.query(on: req.db)
                    .filter(\.$author.$id !~ filters.blocked)
                    .filter(\.$author.$id !~ filters.muted)
                    .filter(\.$text, .custom("ILIKE"), "%\(search)%")
                    .all()
                    .flatMap { (posts) in
						return buildPostData(posts, user: user, on: req, mutewords: filters.mutewords)
                	}
            }
    }
    
    /// `GET /api/v3/forum/post/ID/forum`
    ///
    /// Retrieve the `ForumData` of the specified `ForumPost`'s parent `Forum`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: A 5xx response should be reported as a likely bug, please and thank you.
    /// - Returns: `ForumData` containing the post's parent forum.
    func postForumHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
        let user = try req.auth.require(User.self)
        let cacheUser = try req.userCache.getUser(user)
        // get user's taggedForum barrel, and cached filters, and forum post
        return user.getBookmarkBarrel(of: .taggedForum, on: req)
     	  	.and(ForumPost.findFromParameter("post_id", on: req))
        	.flatMap { (barrel, post) in
                // get forum
                return post.$forum.get(on: req.db).flatMap { (forum) in
					return forum.$posts.query(on: req.db)
						.filter(\.$author.$id !~ cacheUser.getBlocks())
						.filter(\.$author.$id !~ cacheUser.getMutes())
						.sort(\.$createdAt, .ascending)
						.all()
						.flatMap { (posts) in
							return buildForumData(forum, posts: posts, user: user, on: req, 
									mutewords: cacheUser.mutewords, favoriteForumBarrel: barrel)
                        }
                }
            }
    }
    
    /// `GET /api/v3/forum/post/ID`
    ///
    /// Retrieve the specified `ForumPost` with full user `LikeType` data.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the post is not available.
    /// - Returns: `PostDetailData` containing the specified post.
    func postHandler(_ req: Request) throws -> EventLoopFuture<PostDetailData> {
        let user = try req.auth.require(User.self)
        return ForumPost.findFromParameter("post_id", on: req).addModelID()
         	.and(ForumPost.getCachedFilters(for: user, on: req))
        	.flatMap { (arg0, filters) in
        		let (post, postID) = arg0
				if filters.blocked.contains(post.author.id!) || filters.muted.contains(post.author.id!) ||
						post.containsMutewords(using: filters.mutewords) {
                	return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "post is not available"))
                }
        	
				// get likes data and bookmark state
                return PostLikes.query(on: req.db)
					.filter(\.$post.$id == postID)
					.all()
					.and(user.hasBookmarked(post, on: req))
					.flatMap { (postLikes, bookmarked) in
						// get users
						let likeUsers: [EventLoopFuture<User>] = postLikes.map { (postLike) -> EventLoopFuture<User> in
							return User.find(postLike.user.id, on: req.db)
								.unwrap(or: Abort(.internalServerError, reason: "user not found"))
						}
						return likeUsers.flatten(on: req.eventLoop).flatMapThrowing { (users) in
							let seamonkeys = try users.map {
								try $0.convertToSeaMonkey()
							}
							// init return struct
							var postDetailData = try PostDetailData(
								postID: post.requireID(),
								createdAt: post.createdAt ?? Date(),
								authorID: post.author.requireID(),
								text: post.isQuarantined ? "This post is under moderator review." : post.text,
								image: post.isQuarantined ? "" : post.image,
								isBookmarked: bookmarked,
								laughs: [],
								likes: [],
								loves: []
							)
							// sort seamonkeys into like types
							for (index, like) in postLikes.enumerated() {
								switch like.likeType {
									case .laugh:
										postDetailData.laughs.append(seamonkeys[index])
									case .like:
										postDetailData.likes.append(seamonkeys[index])
									case .love:
										postDetailData.loves.append(seamonkeys[index])
									default: continue
								}
							}
							return postDetailData
						}
                	}
            }
    }
    
    /// `GET /api/v3/forum/post/hashtag/#STRING`
    ///
    /// Retrieve all `ForumPost`s that contain the exact specified hashtag.
    ///
    /// - Note: By "exact" we mean the string cannot be a substring of another hashtag (there
    ///   must be a trailing space), but the match is not case-sensitive. For example, `#joco`
    ///   will not match `#joco2020` or `#joco#2020`, but will match `#JoCo`. Use the more
    ///   generic `GET /api/v3/forum/post/search/STRING` endpoint with the same `#joco`
    ///   parameter if you want that type of substring matching behavior.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the specified string is not a hashtag.
    /// - Returns: `[PostData]` containing all matching posts.
    func postHashtagHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        guard var hashtag = req.parameters.get("hashtag_string") else {
            throw Abort(.badRequest, reason: "Missing hashtag parameter.")
        }
        // ensure it's a hashtag
        guard hashtag.hasPrefix("#") else {
            throw Abort(.badRequest, reason: "hashtag parameter must start with '#'")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        hashtag = hashtag.replacingOccurrences(of: "_", with: "\\_")
        hashtag = hashtag.replacingOccurrences(of: "%", with: "\\%")
        hashtag = hashtag.trimmingCharacters(in: .whitespacesAndNewlines)
        // get cached blocks
        return ForumPost.getCachedFilters(for: user, on: req).flatMap { (filters) in
            // get posts
            return ForumPost.query(on: req.db)
                .filter(\.$author.$id !~ filters.blocked)
                .filter(\.$author.$id !~ filters.muted)
                .filter(\.$text, .custom("ILIKE"), "%\(hashtag) %")
                .all()
                .flatMap { (posts) in
 					return buildPostData(posts, user: user, on: req, mutewords: filters.mutewords)
            	}
        }
    }
    
    /// `GET /api/v3/forum/post/search/STRING`
    ///
    /// Retrieve all `ForumPost`s that contain the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all matching posts.
    func postSearchHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        guard var search = req.parameters.get("search_string") else {
            throw Abort(.badRequest, reason: "Missing search parameter.")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // get cached blocks
        return ForumPost.getCachedFilters(for: user, on: req).flatMap {  (filters) in
            // get posts
            return ForumPost.query(on: req.db)
                .filter(\.$author.$id !~ filters.blocked)
                .filter(\.$author.$id !~ filters.muted)
                .filter(\.$text, .custom("ILIKE"), "%\(search)%")
                .all()
                .flatMap { (posts) in
 					return buildPostData(posts, user: user, on: req, mutewords: filters.mutewords)
            	}
        }
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/forum/post/ID/bookmark`
    ///
    /// Add a bookmark of the specified `ForumPost`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the post is already bookmarked.
    /// - Returns: 201 Created on success.
    func bookmarkAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get post and user's bookmarkedPost barrel
        return ForumPost.findFromParameter("post_id", on: req)
        	.and(user.getBookmarkBarrel(of: .bookmarkedPost, on: req))
        	.flatMapThrowing { (post, bookmarkBarrel) -> Barrel in
                // create barrel if needed
                let barrel = bookmarkBarrel ?? Barrel(ownerID: userID, barrelType: .bookmarkedPost)
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
    ///
    /// Remove a bookmark of the specified `ForumPost`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the user has not bookmarked any posts.
    func bookmarkRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        // get post and user's bookmarkedPost barrel
        return ForumPost.findFromParameter("post_id", on: req)
        	.and(user.getBookmarkBarrel(of: .bookmarkedPost, on: req))
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
    
    /// `GET /api/v3/forum/bookmarks`
    ///
    /// Retrieve all `ForumPost`s the user has bookmarked, sorted by creation timestamp.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all bookmarked posts.
    func bookmarksHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get bookmarkedPost barrel
        return user.getBookmarkBarrel(of: .bookmarkedPost, on: req).flatMap { (barrel) in
            let bookmarkStrings = barrel?.userInfo["bookmarks"] ?? []
            // convert to IDs
            let bookmarks = bookmarkStrings.compactMap { Int($0) }
            // filter blocks only
            let blocked = req.userCache.getBlocks(userID)
			// get twarrts
			return ForumPost.query(on: req.db)
				.filter(\.$id ~~ bookmarks)
				.filter(\.$author.$id !~ blocked)
				.sort(\.$createdAt, .ascending)
				.all()
				.flatMap { (posts) in
					return buildPostData(posts, user: user, on: req, assumeBookmarked: true)
            }
        }
    }
    
    /// `POST /api/v3/forum/ID/favorite`
    ///
    /// Add the specified `Forum` to the user's tagged forums list.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: 201 Created on success.
    func favoriteAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get forum and barrel
        return Forum.findFromParameter("forum_id", on: req).addModelID()
        	.and(user.getBookmarkBarrel(of: .taggedForum, on: req)
        			.unwrap(orReplace: Barrel(ownerID: userID, barrelType: .taggedForum)))
        	.flatMap { (arg0, barrel) in
        		let (_, forumID) = arg0
				// add forum and return 201
				barrel.modelUUIDs.append(forumID)
				return barrel.save(on: req.db).transform(to: .created)
            }
    }
    
    /// `POST /api/v3/forum/ID/favorite/remove`
    ///
    /// Remove the specified `Forum` from the user's tagged forums list.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the forum was not favorited.
    /// - Returns: 204 No Content on success.
    func favoriteRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        // get forum
        return Forum.findFromParameter("forum_id", on: req).addModelID()
			.and(user.getBookmarkBarrel(of: .taggedForum, on: req))
        	.flatMap { (arg0, forumBarrel) in
        		let (_, forumID) = arg0
				guard let barrel = forumBarrel else {
					return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "user has not tagged any forums"))
				}
				// remove event
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
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumListData]` containing the user's favorited forums.
    func favoritesHandler(_ req: Request) throws -> EventLoopFuture<[ForumListData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get user's taggedForum barrel
        return user.getBookmarkBarrel(of: .taggedForum, on: req).flatMap { (barrel) in
            guard let barrel = barrel else {
                 return req.eventLoop.future([])
            }
            // respect blocks
            let blocked = req.userCache.getBlocks(userID)
			// get forums
			return Forum.query(on: req.db)
				.filter(\.$id ~~ barrel.modelUUIDs)
				.filter(\.$creator.$id !~ blocked)
				.sort(\.$title, .ascending)
				.all()
				.flatMap { (forums) in
					return buildForumListData(forums, on: req, forceIsFavorite: true)
            }
        }
    }
    
    /// `POST /api/v3/forum/categories/ID/create`
    ///
    /// Creates a new `Forum` in the specified `Category`, and the first `ForumPost` within
    /// the newly created forum. Creating a forum in an `.isRestricted` category requires
    /// administrative access.
    ///
    /// - Requires: `ForumCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ForumCreateData` containing the forum's title and initial post contents.
    /// - Throws: 403 error if the user is not authorized to create a forum.
    /// - Returns: `ForumData` containing the new forum's contents.
    func forumCreateHandler(_ req: Request) throws -> EventLoopFuture<ForumData> {
        let user = try req.auth.require(User.self)
		// see `ForumCreateData.validations()`
        try ForumCreateData.validate(content: req)
        let data = try req.content.decode(ForumCreateData.self)
        // check authorization to create
        return Category.findFromParameter("category_id", on: req).throwingFlatMap { (category) in
            guard !category.isRestricted || user.accessLevel.hasAccess(.moderator)  else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "users cannot create forums in category"))
            }
			// process image
			return self.processImage(data: data.image, forType: .forumPost, on: req).throwingFlatMap { (imageName) in
				// create forum
				let forum = try Forum(title: data.title, category: category, creator: user, isLocked: false)
				return forum.save(on: req.db).throwingFlatMap { (_) in
                    // create first post
                    let forumPost = try ForumPost(forum: forum, author: forum.creator, text: data.text, image: imageName)
                    // return as ForumData
                    return forumPost.save(on: req.db).flatMapThrowing { (_) in
                    	let creatorHeader = try req.userCache.getHeader(user.requireID())
                    	let postData = try PostData(post: forumPost, author: creatorHeader, 
                    			bookmarked: false, userLike: nil, likeCount: 0)
						let forumData = try ForumData(forum: forum, creator: creatorHeader,
								isFavorite: false, posts: [postData])
						return forumData
                    }
                }
            }
        }
    }
    
    /// `POST /api/v3/forum/ID/lock`
    ///
    /// Place a read-only lock on the specified `Forum`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have credentials to modify the forum. 404 error
    ///   if the forum ID is not valid.
    /// - Returns: 201 Created on success.
    func forumLockHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        return Forum.findFromParameter("forum_id", on: req).flatMap { (forum) in
            // must be forum owner or .moderator
            guard forum.creator.id == userID || user.accessLevel.hasAccess(.moderator)  else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "forum cannot be modified by user"))
            }
            forum.isLocked = true
            return forum.save(on: req.db).transform(to: .created)
        }
    }
    
    /// `POST /api/v3/forum/ID/unlock`
    ///
    /// Remove a read-only lock on the specified `Forum`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have credentials to modify the forum. 404 error
    ///   if the forum ID is not valid.
    /// - Returns: 204 No Content on success.
    func forumUnlockHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        return Forum.findFromParameter("forum_id", on: req).flatMap { (forum) in
            // must be forum owner or .moderator
            guard forum.creator.id == userID || user.accessLevel.hasAccess(.moderator)  else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "forum cannot be modified by user"))
            }
            forum.isLocked = false
            return forum.save(on: req.db).transform(to: .noContent)
        }
    }
    
    /// `POST /api/v3/forum/ID/rename/:new_name`
    ///
    /// Rename the specified `Forum` to the specified title string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have credentials to modify the forum. 404 error
    ///   if the forum ID is not valid.
    /// - Returns: 201 Created on success.
    func forumRenameHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
		guard let nameParameter = req.parameters.get("new_name"), nameParameter.count > 0 else {
			throw Abort(.badRequest, reason: "No new name parameter for forum name change.")
		}
        return Forum.findFromParameter("forum_id", on: req).flatMap { (forum) in
            // must be forum owner or .moderator
            guard forum.creator.id == userID || user.accessLevel.hasAccess(.moderator)  else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "forum cannot be modified by user"))
            }
            forum.title = nameParameter
            return forum.save(on: req.db).transform(to: .created)
        }
    }
    
    /// `POST /api/v3/forum/ID/report`
    ///
    /// Creates a `Report` regarding the specified `Forum`.
    ///
    /// - Note: The accompanying report message is optional on the part of the submitting user,
    ///   but the `ReportData` is mandatory in order to allow one. If there is no message,
    ///   send an empty string in the `.message` field.
    ///
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
    /// - Returns: 201 Created on success.
    func forumReportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)
        let parent = try user.parentAccount(on: req)
        let forum = Forum.findFromParameter("forum_id", on: req).addModelID()
        return parent.and(forum).throwingFlatMap { (parent, arg1) in
        	let (forum, forumID) = arg1
            let report = try Report( reportType: .forum, reportedID: forumID.uuidString,
                	submitter: parent, submitterMessage: data.message)
			return forum.fileReport(report, on: req)
        }
    }
    
    
    /// `POST /api/v3/forum/post/ID/image`
    ///
    /// Sets the `ForumPost` image to the file uploaded in the HTTP body.
    ///
    /// - Requires: `ImageUpdloadData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ImageUploadData` containg the filename and image file.
    /// - Throws: 403 error if the user does not have permission to modify the post.
    /// - Returns: `PostData` containing the updated image value.
    func imageHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
		let data = try req.content.decode(ImageUploadData.self)
		// get post
        return ForumPost.findFromParameter("post_id", on: req).addModelID().flatMap { (post, postID) in
            guard post.$author.id == userID || user.accessLevel.hasAccess(.moderator) else {
				return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot modify post"))
            }
			// get generated filename
			return self.processImage(data: data.image, forType: .userProfile, on: req).throwingFlatMap { (filename) in
				// replace existing image
				if !post.image.isEmpty {
					// create ForumEdit record
					let forumEdit = try ForumEdit(post: post)
					// archive thumbnail
					DispatchQueue.global(qos: .background).async {
						self.archiveImage(post.image, from: self.imageDir)
					}
					return forumEdit.save(on: req.db).transform(to: filename)
				}
				return req.eventLoop.future(filename)
			}
			.flatMap { (filename: String) in
				// update post
				post.image = filename
				return post.save(on: req.db).flatMap { (_) in
					// return as PostData. Because a mod can call this to modify an image on another user's post,
					// we may need to process userLikes and likeCounts.
					return buildPostData([post], user: user, on: req).map { postDataArray in
						return postDataArray[0]
					}
				}
			}
		}
    }
    
    /// `POST /api/v3/forum/post/ID/image/remove`
    ///
    /// Removes the image from a `ForumPost`, if there is one. A `ForumEdit` record is created
    /// if there was an image to remove.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have permission to modify the post.
    /// - Returns: `PostData` containing updated image name.
    func imageRemoveHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        return ForumPost.findFromParameter("post_id", on: req).addModelID().throwingFlatMap { (post, postID) in
            guard post.author.id == userID || user.accessLevel.hasAccess(.moderator) else {
				throw Abort(.forbidden, reason: "user cannot modify post")
            }
			if !post.image.isEmpty {
				// create ForumEdit record
				let forumEdit = try ForumEdit(post: post)
				// archive thumbnail
				DispatchQueue.global(qos: .background).async {
					self.archiveImage(post.image, from: self.imageDir)
				}
				// Makes a future we don't wait on.
				_ = forumEdit.save(on: req.db)
			}
			// remove image filename from post
			post.image = ""
			return post.save(on: req.db).flatMap { (_) in
				// return as PostData. Because a mod can call this to modify an image on another user's post,
				// we may need to process userLikes and likeCounts.
				return buildPostData([post], user: user, on: req).map { postDataArray in
					return postDataArray[0]
				}
			}
		}
    }
    
    /// `GET /api/v3/forum/likes`
    ///
    /// Retrieve all `ForumPost`s the user has liked.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all liked posts.
    func likesHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        // respect blocks
        let blocked = try req.userCache.getBlocks(user)
		// get liked posts
		return user.$postLikes.query(on: req.db)
			.filter(\.$author.$id !~ blocked)
			.all()
			.flatMap { (posts) in
				return buildPostData(posts, user: user, on: req)
        }
    }
    
    /// `GET /api/v3/forum/mentions`
    ///
    /// Retrieve all `ForumPost`s whose content mentions the user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all posts containing mentions.
    func mentionsHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        // respect blocks
        let blocked = try req.userCache.getBlocks(user)
		// get mention posts
		return ForumPost.query(on: req.db)
			.filter(\.$author.$id !~ blocked)
			.filter(\.$text, .custom("ILIKE"), "%@\(user.username) %")
			.sort(\.$createdAt, .ascending)
			.all()
			.flatMap { (posts) in
				return buildPostData(posts, user: user, on: req)
        }
    }
    
    /// `GET /api/v3/forum/owner`
    /// `GET /api/v3/user/forums`
    ///
    /// Retrieve a list of all `Forum`s created by the user, sorted by title.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumListData]` containing all forums created by the user.
    func ownerHandler(_ req: Request) throws-> EventLoopFuture<[ForumListData]> {
        let user = try req.auth.require(User.self)
        // get user's taggedForum barrel
        return user.getBookmarkBarrel(of: .taggedForum, on: req).flatMap { (barrel) in
            return user.$forums.query(on: req.db)
                .sort(\.$title, .ascending)
                .all()
                .flatMap { (forums) in
					return buildForumListData(forums, on: req, favoritesBarrel: barrel)
            	}
        }
    }
    
    /// `POST /api/v3/forum/ID/create`
    ///
    /// Create a new `ForumPost` in the specified `Forum`.
    ///
    /// - Requires: `PostCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostCreateData` containing the post's text and optional image.
    /// - Throws: 403 error if the forum is locked or user is blocked.
    /// - Returns: `PostData` containing the post's contents and metadata.
    func postCreateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        let cacheUser = try req.userCache.getUser(user)
        // ensure user has write access
        guard user.accessLevel.hasAccess(.verified) else {
            throw Abort(.forbidden, reason: "user cannot post in forum")
        }
        // see `PostCreateData.validations()`
        try PostCreateData.validate(content: req)
        let data = try req.content.decode(PostCreateData.self)
        // get forum
        return Forum.findFromParameter("forum_id", on: req).throwingFlatMap { (forum) in
            guard !forum.isLocked else {
                throw Abort(.forbidden, reason: "forum is locked read-only")
            }
            // ensure user has access to forum; user cannot retrieve block-owned forum, but prevent end-run
			guard let creatorID = forum.creator.id, !cacheUser.getBlocks().contains(creatorID) else {
				throw Abort(.forbidden, reason: "user cannot post in forum")
			}
			// process image
			return self.processImage(data: data.imageData, forType: .forumPost, on: req).throwingFlatMap { (filename) in
				// create post
				let forumPost = try ForumPost(forum: forum, author: user, text: data.text, image: filename)
				return forumPost.save(on: req.db).flatMapThrowing { (_) in
					// return as PostData, with 201 status
					let response = Response(status: .created)
					try response.content.encode(PostData(post: forumPost, author: cacheUser.makeHeader()))
					return response
				}
			}
        }
    }
    
    /// `POST /api/v3/forum/post/ID/delete`
    ///
    /// Delete the specified `ForumPost`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No Content on success.
    func postDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        return ForumPost.findFromParameter("post_id", on: req).flatMap { (post) in
            guard post.author.id == userID || user.accessLevel.hasAccess(.moderator) else {
                    return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot delete post"))
            }
            return post.delete(on: req.db).transform(to: .noContent)
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
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
    /// - Throws: 409 error if user has already reported the post.
    /// - Returns: 201 Created on success.
    func postReportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let parent = try user.parentAccount(on: req)
        let data = try req.content.decode(ReportData.self)
        return ForumPost.findFromParameter("post_id", on: req).and(parent).throwingFlatMap { (post, parent) in
			do {
				let report = try Report(reportType: .forumPost, reportedID: String(try post.requireID()),
							submitter: parent, submitterMessage: data.message)
				return post.fileReport(report, on: req)
			}
			catch {
				return req.eventLoop.makeFailedFuture(error)
			}
        }
    }
    
    /// `POST /api/v3/forum/post/ID/laugh`
    ///
    /// Add a "laugh" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: `PostData` containing the updated like info.
    func postLaughHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .laugh)
    }
    
        /// `POST /api/v3/forum/post/ID/like`
    ///
    /// Add a "like" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: `PostData` containing the updated like info.
    func postLikeHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .like)
	}
    
    /// `POST /api/v3/forum/post/ID/love`
    ///
    /// Add a "love" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: `PostData` containing the updated like info.
    func postLoveHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
    	return try postReactHandler(req, likeType: .love)
	}
	
	func postReactHandler(_ req: Request, likeType: LikeType) throws -> EventLoopFuture<PostData> {
        let user = try req.auth.require(User.self)
		let userID = try user.requireID()
        // get post
        return ForumPost.findFromParameter("post_id", on: req).addModelID().flatMap { (post, postID) in
            guard post.author.id != userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own post"))
            }
			return post.$likes.attachOrEdit(from: post, to: user, on: req.db) { postLike in
				postLike.likeType = likeType
			}.flatMap { 
				return buildPostData([post], user: user, on: req).map { postDataArray in
					return postDataArray[0]
				}
			}
		}
	}

    /// `GET /api/v3/forum/posts`
    ///
    /// Retrieve all `ForumPost`s authored by the user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all posts authored by the user.
    func postsHandler(_ req: Request) throws -> EventLoopFuture<[PostData]> {
        let user = try req.auth.require(User.self)
        // get posts
        return user.$posts.query(on: req.db)
            .sort(\.$createdAt, .ascending)
            .all()
            .flatMap { (posts) in
				return buildPostData(posts, user: user, on: req)
        	}
    }
    
    /// `POST /api/v3/forum/post/ID/unreact`
    ///
    /// Remove a `LikeType` reaction from the specified `ForumPost`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if there was no existing reaction. 403 error if user is the post's
    ///   creator.
    /// - Returns: `PostData` containing the updated like info.
    func postUnreactHandler(_ req: Request) throws -> EventLoopFuture<PostData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get post
        return ForumPost.findFromParameter("post_id", on: req).addModelID().flatMap { (post, postID) in
            guard post.author.id != userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own post"))
            }
			// check for existing like
			return PostLikes.query(on: req.db)
				.filter(\.$user.$id == userID)
				.filter(\.$post.$id == postID)
				.first()
				.throwingFlatMap { (like) in
					guard like != nil else {
						throw Abort(.badRequest, reason: "user does not have a reaction on the post")
					}
					// remove pivot
					return post.$likes.detach(user, on: req.db).flatMap { (_) in
						return buildPostData([post], user: user, on: req).map { postDataArray in
							return postDataArray[0]
						}
					}
				}
        }
    }
    
    /// `POST /api/v3/forum/post/ID/update`
    ///
    /// Update the specified `ForumPost`.
    ///
    /// - Note: This endpoint only changes the `.text` and `.image` *filename* of the post.
    ///   To change or remove the actual image asoociated with the post, use
    ///   `POST /api/v3/forum/post/ID/image` or `POST /api/v3/forum/post/ID/image/remove`.
    ///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is not post owner or has read-only access.
    /// - Returns: `PostData` containing the post's contents and metadata.
    func postUpateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
		// see `PostCreateData.validations()`
        try PostContentData.validate(content: req)
        let data = try req.content.decode(PostContentData.self)
        return ForumPost.findFromParameter("post_id", on: req).addModelID().throwingFlatMap { (post, postID) in
            // ensure user has write access
            guard post.author.id == userID, user.accessLevel.hasAccess(.verified) else {
					throw Abort(.forbidden, reason: "user cannot modify post")
            }
			// update if there are changes
			if post.text != data.text || post.image != data.imageFilename {
				// stash current contents first
				let forumEdit = try ForumEdit(post: post)
				post.text = data.text
				post.image = data.imageFilename
				return post.save(on: req.db).and(forumEdit.save(on: req.db)).transform(to: (post, true))
			}
			return req.eventLoop.future((post, false))
		}
		.flatMap { (post, wasCreated: Bool) in
			// return updated post as PostData, with 200 or 201 status
			return buildPostData([post], user: user, on: req).flatMapThrowing { postDataArray in
				let response = Response(status: wasCreated ? .created : .ok)
				try response.content.encode(postDataArray[0])
				return response
			}
		}
    }
}

// Utilities for route methods
extension ForumController {
	
	func buildForumListData(_ forums: [Forum], on req: Request, 
			favoritesBarrel: Barrel? = nil, forceIsFavorite: Bool? = nil) -> EventLoopFuture<[ForumListData]> {
		// get forum metadata
		var forumCounts: [EventLoopFuture<Int>] = []
		var forumTimestamps: [EventLoopFuture<Date?>] = []
		for forum in forums {
			forumCounts.append(forum.$posts.query(on: req.db).count())
			forumTimestamps.append(forum.$posts.query(on: req.db)
				.sort(\.$createdAt, .descending)
				.first()
				.map { (post) in
					post?.createdAt
				}
			)
		}
		// resolve futures
		return forumCounts.flatten(on: req.eventLoop).and(forumTimestamps.flatten(on: req.eventLoop))
			.flatMapThrowing { (counts, timestamps) in
				// return as ForumListData
				var returnListData: [ForumListData] = []
				for (index, forum) in forums.enumerated() {
					let userHeader = try req.userCache.getHeader(forum.$creator.id)
					returnListData.append(
						try ForumListData(
							forum: forum, 
							creator: userHeader, 
							postCount: counts[index], 
							lastPostAt: timestamps[index], 
							isFavorite: forceIsFavorite ?? favoritesBarrel?.contains(forum) ?? false)
					)
				}
				return returnListData
			}
	}
	
	func buildForumData(_ forum: Forum, posts: [ForumPost], user: User, on req: Request,
			mutewords: [String]? = nil, favoriteForumBarrel: Barrel? = nil) -> EventLoopFuture<ForumData> {
		return buildPostData(posts, user: user, on: req, mutewords: mutewords)
			.flatMapThrowing { (flattenedPosts) in
				let creatorHeader = try req.userCache.getHeader(forum.$creator.id)
				return try ForumData(forum: forum, creator: creatorHeader, 
						isFavorite: favoriteForumBarrel?.contains(forum) ?? false,
						posts: flattenedPosts)
			}
	}
	
	// Builds an array of PostData structures from the given posts, adding the user's bookmarks and likes
	// for the post, as well as the total count of likes. The optional parameters are for callers that
	// only need some of the functionality, or for whom some of the values are known in advance e.g.
	// the method that returns a user's bookmarked posts can assume all the posts it finds are in fact bookmarked.
	func buildPostData(_ posts: [ForumPost], user: User, on req: Request,
			mutewords: [String]? = nil, assumeBookmarked: Bool? = nil, assumeLikeType: LikeType? = nil) -> EventLoopFuture<[PostData]> {

		// remove muteword posts
		var filteredPosts = posts
		if let mutes = mutewords {
			 filteredPosts = posts.compactMap { $0.filterMutewords(using: mutes) }
		}
		// convert to PostData
		let postsData = filteredPosts.map { (filteredPost) -> EventLoopFuture<PostData> in
			do {
      			let author = try req.userCache.getHeader(filteredPost.$author.id)
				let bookmarked = assumeBookmarked == nil ? user.hasBookmarked(filteredPost, on: req) :
						req.eventLoop.future(assumeBookmarked!)
				let processUserLike = try author.userID != user.requireID() && assumeLikeType == nil
				let userLike = processUserLike ? try PostLikes.query(on: req.db)
					.filter(\.$post.$id == filteredPost.requireID())
					.filter(\.$user.$id == user.requireID())
					.first().map { $0?.likeType } : req.eventLoop.future(assumeLikeType)
				let likeCount = try PostLikes.query(on: req.db)
					.filter(\.$post.$id  == filteredPost.requireID())
					.count()
				return bookmarked.and(userLike).and(likeCount).flatMapThrowing { (arg0, count) in
					let (bookmarked, userLike) = arg0
					return try PostData(post: filteredPost, author: author, bookmarked: bookmarked, 
							userLike: userLike, likeCount: count)
				}
			}
			catch {
				return req.eventLoop.makeFailedFuture(error)
			}
		}
		return postsData.flatten(on: req.eventLoop)
	}
}

// posts can contain images
extension ForumController: ImageHandler {
    /// The base directory for storing ForumPost images.
    var imageDir: String {
        return "images/forum/"
    }
    
    /// The height of ForumPost image thumbnails.
    var thumbnailHeight: Int {
        return 100
    }
}
