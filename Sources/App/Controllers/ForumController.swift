import Vapor
import Crypto
import FluentSQL
import Fluent
import Redis

/// The collection of `/api/v3/forum/*` route endpoints and handler functions related
/// to forums.

struct ForumController: RouteCollection, ImageHandler, ContentFilterable {

    // MARK: ImageHandler Conformance
    
    /// The base directory for storing ForumPost images.
    var imageDir: String {
        return "images/forum/"
    }
    
    /// The height of ForumPost image thumbnails.
    var thumbnailHeight: Int {
        return 100
    }

    // MARK: RouteCollection Conformance
    
    /// Required. Registers routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/forum endpoints
        let forumRoutes = router.grouped("api", "v3", "forum")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let sharedAuthGroup = forumRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = forumRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // open access endpoints
        
        // endpoints available only when not logged in
        
        // endpoints available whether logged in or out
        sharedAuthGroup.get(Forum.parameter, use: forumHandler)
        sharedAuthGroup.get("categories", use: categoriesHandler)
        sharedAuthGroup.get("categories", "admin", use: categoriesAdminHandler)
        sharedAuthGroup.get("categories", "user", use: categoriesUserHandler)
        sharedAuthGroup.get("categories", Category.parameter, use: categoryForumsHandler)
        sharedAuthGroup.get("match", String.parameter, use: forumMatchHandler)
        sharedAuthGroup.get("post", ForumPost.parameter, use: postHandler)
        sharedAuthGroup.get("post", ForumPost.parameter, "forum", use: postForumHandler)
        sharedAuthGroup.get("post", "search", String.parameter, use: postSearchHandler)
        sharedAuthGroup.get(Forum.parameter, "search", String.parameter, use: forumSearchHandler)
        
        // endpoints available only when logged in
        tokenAuthGroup.post(ForumCreateData.self, at: "categories", Category.parameter, "create", use: forumCreateHandler)
        tokenAuthGroup.post(Forum.parameter, "lock", use: forumLockHandler)
        tokenAuthGroup.post(Forum.parameter, "rename", String.parameter, use: forumRenameHandler)
        tokenAuthGroup.post(ReportData.self, at: Forum.parameter, "report", use: forumReportHandler)
        tokenAuthGroup.post(Forum.parameter, "unlock", use: forumUnlockHandler)
        tokenAuthGroup.get("owner", use: ownerHandler)
        tokenAuthGroup.post(PostCreateData.self, at: Forum.parameter, "create", use: postCreateHandler)
        tokenAuthGroup.post("post", ForumPost.parameter, "delete", use: postDeleteHandler)
        tokenAuthGroup.post(ImageUploadData.self, at: "post", ForumPost.parameter, "image", use: imageHandler)
        tokenAuthGroup.post("post", ForumPost.parameter, "image", "remove", use: imageRemoveHandler)
        tokenAuthGroup.post("post", ForumPost.parameter, "laugh", use: postLaughHandler)
        tokenAuthGroup.post("post", ForumPost.parameter, "like", use: postLikeHandler)
        tokenAuthGroup.post("post", ForumPost.parameter, "love", use: postLoveHandler)
        tokenAuthGroup.post(ReportData.self, at: "post", ForumPost.parameter, "report", use: postReportHandler)
        tokenAuthGroup.post("post", ForumPost.parameter, "unreact", use: postUnreactHandler)
        tokenAuthGroup.post(PostContentData.self, at: "post", ForumPost.parameter, "update", use: postUpateHandler)
    }
    
    // MARK: - Open Access Handlers
    
    // MARK: - basicAuthGroup Handlers (not logged in)
    // All handlers in this route group require a valid HTTP Basic Authentication
    // header in the request.
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/forum/categories`
    ///
    /// Retrieve a list of all forum `Category`s, sorted by type (admin, user)
    /// and title (for user categories only).
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[CategoryData]` containing all category IDs and titles.
    func categoriesHandler(_ req: Request) throws -> Future<[CategoryData]> {
        var categories: [Category] = []
        // get admin categories
        return Category.query(on: req)
            .filter(\.isRestricted == true)
            .all()
            .flatMap {
                (adminCategories) in
                categories.append(contentsOf: adminCategories)
                // get sorted user categories
                return Category.query(on: req)
                    .filter(\.isRestricted == false)
                    .sort(\.title, .ascending)
                    .all()
                    .map {
                        (userCategories) in
                        categories.append(contentsOf: userCategories)
                        // return as CategoryData
                        return try categories.map {
                            try CategoryData(categoryID: $0.requireID(), title: $0.title)
                        }
                }
        }
    }
    
    /// `GET /api/v3/forum/categories/admin`
    ///
    /// Retrieve a list of all "official" forum `Category`s.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[CategoryData]` containing all administrative categories.
    func categoriesAdminHandler(_ req: Request) throws -> Future<[CategoryData]> {
        return Category.query(on: req)
            .filter(\.isRestricted == true)
            .all()
            .map {
                (categories) in
                // return as CategoryData
                return try categories.map {
                    try CategoryData(categoryID: $0.requireID(), title: $0.title)
                }
        }
    }
    
    /// `GET /api/v3/forum/categories/user`
    ///
    /// Retrieve a list of all user forum `Category`s, sorted by title.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[CategoryData]` containing all general user categories.
    func categoriesUserHandler(_ req: Request) throws -> Future<[CategoryData]> {
        return Category.query(on: req)
            .filter(\.isRestricted == false)
            .sort(\.title, .ascending)
            .all()
            .map {
                (categories) in
                // return as CategoryData
                return try categories.map {
                    try CategoryData(categoryID: $0.requireID(), title: $0.title)
                }
        }
    }
    
    /// `GET /api/v3/forum/catgories/ID`
    ///
    /// Retrieve a list of all forums in the specifiec `Category`, sorted by title if not an
    /// admin category. If the forum is user-created and a user block applies, the forum will
    /// not be returned.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the category ID is not valid.
    /// - Returns: `[ForumListData]` containing all category forums.
    func categoryForumsHandler(_ req: Request) throws -> Future<[ForumListData]> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Category.self).flatMap {
            (category) in
            if category.isRestricted {
                // don't sort admin categories
                return try Forum.query(on: req)
                    .filter(\.categoryID == category.requireID())
                    .all()
                    .flatMap {
                        (forums) in
                        // get forum metadata
                        var forumCounts: [Future<Int>] = []
                        var forumTimestamps: [Future<Date?>] = []
                        for forum in forums {
                            forumCounts.append(try forum.posts.query(on: req).count())
                            forumTimestamps.append(try forum.posts.query(on: req)
                                .sort(\.createdAt, .descending)
                                .first()
                                .map {
                                    (post) in
                                    post?.createdAt
                                }
                            )
                        }
                        // resolve futures
                        return forumCounts.flatten(on: req).flatMap {
                            (counts) in
                            return forumTimestamps.flatten(on: req).map {
                                (timestamps) in
                                // return as ForumListData
                                var returnListData: [ForumListData] = []
                                for (index, forum) in forums.enumerated() {
                                    returnListData.append(
                                        try ForumListData(
                                            forumID: forum.requireID(),
                                            title: forum.title,
                                            postCount: counts[index],
                                            lastPostAt: timestamps[index],
                                            isLocked: forum.isLocked
                                        )
                                    )
                                }
                                return returnListData
                            }
                        }
                }
            } else {
                // remove blocks from results
                let cache = try req.keyedCache(for: .redis)
                let key = try "blocks:\(user.requireID())"
                let cachedBlocks = cache.get(key, as: [UUID].self)
                return cachedBlocks.flatMap {
                    (blocks) in
                    let blocked = blocks ?? []
                    // sort user categories
                    return try Forum.query(on: req)
                        .filter(\.categoryID == category.requireID())
                        .filter(\.creatorID !~ blocked)
                        .sort(\.title, .ascending)
                        .all()
                        .flatMap {
                            (forums) in
                            // get forum metadata
                            var forumCounts: [Future<Int>] = []
                            var forumTimestamps: [Future<Date?>] = []
                            for forum in forums {
                                forumCounts.append(try forum.posts.query(on: req).count())
                                forumTimestamps.append(try forum.posts.query(on: req)
                                    .sort(\.createdAt, .descending)
                                    .first()
                                    .map {
                                        (post) in
                                        post?.createdAt
                                    }
                                )
                            }
                            // resolve futures
                            return forumCounts.flatten(on: req).flatMap {
                                (counts) in
                                return forumTimestamps.flatten(on: req).map {
                                    (timestamps) in
                                    // return as ForumListData
                                    var returnListData: [ForumListData] = []
                                    for (index, forum) in forums.enumerated() {
                                        returnListData.append(
                                            try ForumListData(
                                                forumID: forum.requireID(),
                                                title: forum.title,
                                                postCount: counts[index],
                                                lastPostAt: timestamps[index],
                                                isLocked: forum.isLocked
                                            )
                                        )
                                    }
                                    return returnListData
                                }
                            }
                    }
                }
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
    func forumHandler(_ req: Request) throws -> Future<ForumData> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Forum.self).flatMap {
            (forum) in
            // filter posts
            return try self.getCachedFilters(for: user, on: req).flatMap {
                (tuple) in
                let blocked = tuple.0
                let muted = tuple.1
                let mutewords = tuple.2
                return try forum.posts.query(on: req)
                    .filter(\.authorID !~ blocked)
                    .filter(\.authorID !~ muted)
                    .sort(\.createdAt, .ascending)
                    .all()
                    .flatMap {
                        (posts) in
                        // remove muteword posts
                        let filteredPosts = posts.compactMap {
                            self.filterMutewords(for: $0, using: mutewords, on: req)
                        }
                        // convert to PostData
                        let postsData = try filteredPosts.map {
                            (filteredPost) -> Future<PostData> in
                            let userLike = try PostLikes.query(on: req)
                                .filter(\.postID == filteredPost.requireID())
                                .filter(\.userID == user.requireID())
                                .first()
                            let likeCount = try PostLikes.query(on: req)
                                .filter(\.postID == filteredPost.requireID())
                                .count()
                            return map(userLike, likeCount) {
                                (resolvedLike, count) in
                                return try filteredPost.convertToData(
                                    withLike: resolvedLike?.likeType,
                                    likeCount: count
                                )
                            }
                        }
                        return postsData.flatten(on: req).map {
                            (flattenedPosts) in
                            return try ForumData(
                                forumID: forum.requireID(),
                                title: forum.title,
                                creatorID: forum.creatorID,
                                isLocked: forum.isLocked,
                                posts: flattenedPosts
                            )
                        }
                }
            }
        }
    }
    
    /// `GET /api/v3/forum/match/STRING`
    ///
    /// Retrieve all `Forum`s whose title contains the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumListData]` containing all matching forums.
    func forumMatchHandler(_ req: Request) throws -> Future<[ForumListData]> {
        let user = try req.requireAuthenticated(User.self)
        var search = try req.parameters.next(String.self)
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // remove blocks from results
        let cache = try req.keyedCache(for: .redis)
        let key = try "blocks:\(user.requireID())"
        let cachedBlocks = cache.get(key, as: [UUID].self)
        return cachedBlocks.flatMap {
            (blocks) in
            let blocked = blocks ?? []
            // get forums
            return Forum.query(on: req)
                .filter(\.creatorID !~ blocked)
                .filter(\.title, .ilike, "%\(search)%")
                .all()
                .flatMap {
                    (forums) in
                    // get forum metadata
                    var forumCounts: [Future<Int>] = []
                    var forumTimestamps: [Future<Date?>] = []
                    for forum in forums {
                        forumCounts.append(try forum.posts.query(on: req).count())
                        forumTimestamps.append(try forum.posts.query(on: req)
                            .sort(\.createdAt, .descending)
                            .first()
                            .map {
                                (post) in
                                post?.createdAt
                            }
                        )
                    }
                    // resolve futures
                    return forumCounts.flatten(on: req).flatMap {
                        (counts) in
                        return forumTimestamps.flatten(on: req).map {
                            (timestamps) in
                            // return as ForumListData
                            var returnListData: [ForumListData] = []
                            for (index, forum) in forums.enumerated() {
                                returnListData.append(
                                    try ForumListData(
                                        forumID: forum.requireID(),
                                        title: forum.title,
                                        postCount: counts[index],
                                        lastPostAt: timestamps[index],
                                        isLocked: forum.isLocked
                                    )
                                )
                            }
                            return returnListData
                        }
                    }
            }
        }
    }
    
    /// `GET /api/v3/forum/ID/search/STRING`
    ///
    /// Retrieve all `ForumPost`s in the specified `Forum` that contain the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all matching posts in the forum.
    func forumSearchHandler(_ req: Request) throws -> Future<[PostData]> {
        let user = try req.requireAuthenticated(User.self)
        // get forum
        return try req.parameters.next(Forum.self).flatMap {
            (forum) in
            var search = try req.parameters.next(String.self)
            // postgres "_" and "%" are wildcards, so escape for literals
            search = search.replacingOccurrences(of: "_", with: "\\_")
            search = search.replacingOccurrences(of: "%", with: "\\%")
            search = search.trimmingCharacters(in: .whitespacesAndNewlines)
            // get cached blocks
            return try self.getCachedFilters(for: user, on: req).flatMap {
                (tuple) in
                let blocked = tuple.0
                let muted = tuple.1
                let mutewords = tuple.2
                // get posts
                return try forum.posts.query(on: req)
                    .filter(\.authorID !~ blocked)
                    .filter(\.authorID !~ muted)
                    .filter(\.text, .ilike, "%\(search)%")
                    .all()
                        .flatMap {
                            (posts) in
                            // remove muteword posts
                            let filteredPosts = posts.compactMap {
                                self.filterMutewords(for: $0, using: mutewords, on: req)
                            }
                            // convert to PostData
                            let postsData = try filteredPosts.map {
                                (filteredPost) -> Future<PostData> in
                                let userLike = try PostLikes.query(on: req)
                                    .filter(\.postID == filteredPost.requireID())
                                    .filter(\.userID == user.requireID())
                                    .first()
                                let likeCount = try PostLikes.query(on: req)
                                    .filter(\.postID == filteredPost.requireID())
                                    .count()
                                return map(userLike, likeCount) {
                                    (resolvedLike, count) in
                                    return try filteredPost.convertToData(
                                        withLike: resolvedLike?.likeType,
                                        likeCount: count
                                    )
                                }
                            }
                            return postsData.flatten(on: req)
                    }
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
    func postForumHandler(_ req: Request) throws -> Future<ForumData> {
        let user = try req.requireAuthenticated(User.self)
        // get post
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            // get forum
            return post.forum.get(on: req).flatMap {
                (forum) in
                // filter posts
                return try self.getCachedFilters(for: user, on: req).flatMap {
                    (tuple) in
                    let blocked = tuple.0
                    let muted = tuple.1
                    let mutewords = tuple.2
                    return try forum.posts.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .sort(\.createdAt, .ascending)
                        .all()
                        .flatMap {
                            (posts) in
                            // remove muteword posts
                            let filteredPosts = posts.compactMap {
                                self.filterMutewords(for: $0, using: mutewords, on: req)
                            }
                            // convert to PostData
                            let postsData = try filteredPosts.map {
                                (filteredPost) -> Future<PostData> in
                                let userLike = try PostLikes.query(on: req)
                                    .filter(\.postID == filteredPost.requireID())
                                    .filter(\.userID == user.requireID())
                                    .first()
                                let likeCount = try PostLikes.query(on: req)
                                    .filter(\.postID == filteredPost.requireID())
                                    .count()
                                return map(userLike, likeCount) {
                                    (resolvedLike, count) in
                                    return try filteredPost.convertToData(
                                        withLike: resolvedLike?.likeType,
                                        likeCount: count
                                    )
                                }
                            }
                            return postsData.flatten(on: req).map {
                                (flattenedPosts) in
                                return try ForumData(
                                    forumID: forum.requireID(),
                                    title: forum.title,
                                    creatorID: forum.creatorID,
                                    isLocked: forum.isLocked,
                                    posts: flattenedPosts
                                )
                            }
                    }
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
    func postHandler(_ req: Request) throws -> Future<PostDetailData> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(ForumPost.self).flatMap {
            (postParameter) in
            // we have post, but need to filter
            return try self.getCachedFilters(for: user, on: req).flatMap {
                (tuple) in
                let blocked = tuple.0
                let muted = tuple.1
                let mutewords = tuple.2
                // NOW we can find (again!) using postgress to filter
                return try ForumPost.query(on: req)
                    .filter(\.id == postParameter.requireID())
                    .filter(\.authorID !~ blocked)
                    .filter(\.authorID !~ muted)
                    .first()
                    .unwrap(or: Abort(.notFound, reason: "post is not available"))
                    .flatMap {
                        (existingPost) in
                        // remove mutewords
                        let filteredPost = self.filterMutewords(for: existingPost, using: mutewords, on: req)
                        guard let post = filteredPost else {
                            throw Abort(.notFound, reason:"post is not available")
                        }
                        // get likes data
                        return try PostLikes.query(on: req)
                            .filter(\.postID == post.requireID())
                            .all()
                            .flatMap {
                                (postLikes) in
                                // get users
                                let likeUsers: [Future<User>] = postLikes.map {
                                    (postLike) -> Future<User> in
                                    return User.find(postLike.userID, on: req)
                                        .unwrap(or: Abort(.internalServerError, reason: "user not found"))
                                }
                                return likeUsers.flatten(on: req).map {
                                    (users) in
                                    let seamonkeys = try users.map { try $0.convertToSeaMonkey() }
                                    // init return struct
                                    var postDetailData = try PostDetailData(
                                        postID: post.requireID(),
                                        createdAt: post.createdAt ?? Date(),
                                        authorID: post.authorID,
                                        text: post.text,
                                        image: post.image,
                                        laughs: [],
                                        likes: [],
                                        loves: []
                                    )
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
        }
    }
    
    /// `GET /api/v3/forum/post/search/STRING`
    ///
    /// Retrieve all `ForumPost`s that contain the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[PostData]` containing all matching posts.
    func postSearchHandler(_ req: Request) throws -> Future<[PostData]> {
        let user = try req.requireAuthenticated(User.self)
        var search = try req.parameters.next(String.self)
        // postgres "_" and "%" are wildcards, so escape for literals
        search = search.replacingOccurrences(of: "_", with: "\\_")
        search = search.replacingOccurrences(of: "%", with: "\\%")
        search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        // get cached blocks
        return try self.getCachedFilters(for: user, on: req).flatMap {
            (tuple) in
            let blocked = tuple.0
            let muted = tuple.1
            let mutewords = tuple.2
            // get posts
            return ForumPost.query(on: req)
                .filter(\.authorID !~ blocked)
                .filter(\.authorID !~ muted)
                .filter(\.text, .ilike, "%\(search)%")
                .all()
                .flatMap {
                    (posts) in
                    // remove muteword posts
                    let filteredPosts = posts.compactMap {
                        self.filterMutewords(for: $0, using: mutewords, on: req)
                    }
                    // convert to PostData
                    let postsData = try filteredPosts.map {
                        (filteredPost) -> Future<PostData> in
                        let userLike = try PostLikes.query(on: req)
                            .filter(\.postID == filteredPost.requireID())
                            .filter(\.userID == user.requireID())
                            .first()
                        let likeCount = try PostLikes.query(on: req)
                            .filter(\.postID == filteredPost.requireID())
                            .count()
                        return map(userLike, likeCount) {
                            (resolvedLike, count) in
                            return try filteredPost.convertToData(
                                withLike: resolvedLike?.likeType,
                                likeCount: count
                            )
                        }
                    }
                    return postsData.flatten(on: req)
            }
        }
    }

    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
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
    func forumCreateHandler(_ req: Request, data: ForumCreateData) throws -> Future<ForumData> {
        let user = try req.requireAuthenticated(User.self)
        // check authorization to create
        return try req.parameters.next(Category.self).flatMap {
            (category) in
            guard !category.isRestricted
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "users cannot create forums in category")
            }
            // see `ForumCreateData.validations()`
            try data.validate()
            // create forum
            let forum = try Forum(
                title: data.title,
                categoryID: category.requireID(),
                creatorID: user.requireID(),
                isLocked: false
            )
            return forum.save(on: req).flatMap {
                (savedForum) in
                // process image
                return try self.processImage(data: data.image, forType: .forumPost, on: req).flatMap {
                    (imageName) in
                    // create first post
                    let forumPost = try ForumPost(
                        forumID: savedForum.requireID(),
                        authorID: savedForum.creatorID,
                        text: data.text,
                        image: imageName
                    )
                    // return as ForumData
                    return forumPost.save(on: req).map {
                        (post) in
                        let forumData = try ForumData(
                            forumID: savedForum.requireID(),
                            title: savedForum.title,
                            creatorID: savedForum.creatorID,
                            isLocked: savedForum.isLocked,
                            posts: [post.convertToData(withLike: nil, likeCount: 0)]
                        )
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
    func forumLockHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        let parameter = try req.parameters.next(Forum.self)
        return parameter.flatMap {
            (forum) in
            // must be forum owner or .moderator
            guard try forum.creatorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "forum cannot be modified by user")
            }
            forum.isLocked = true
            return forum.save(on: req).transform(to: .created)
        }
    }

    /// `POST /api/v3/forum/ID/unlock`
    ///
    /// Rename the specified `Forum` to the specified title string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have credentials to modify the forum. 404 error
    ///   if the forum ID is not valid.
    /// - Returns: 201 Created on success.
    func forumRenameHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        let forumParameter = try req.parameters.next(Forum.self)
        let nameParameter = try req.parameters.next(String.self)
        return forumParameter.flatMap {
            (forum) in
            // must be forum owner or .moderator
            guard try forum.creatorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "forum cannot be modified by user")
            }
            forum.title = nameParameter
            return forum.save(on: req).transform(to: .created)
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
    func forumReportHandler(_ req: Request, data: ReportData) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        let parent = try user.parentAccount(on: req)
        let forum = try req.parameters.next(Forum.self)
        return flatMap(parent, forum) {
            (parent, forum) in
            let report = Report(
                reportType: .forum,
                reportedID: try forum.requireID().uuidString,
                submitterID: try parent.requireID(),
                submitterMessage: data.message
            )
            return report.save(on: req).transform(to: .created)
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
    func forumUnlockHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        let parameter = try req.parameters.next(Forum.self)
        return parameter.flatMap {
            (forum) in
            // must be forum owner or .moderator
            guard try forum.creatorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "forum cannot be modified by user")
            }
            forum.isLocked = false
            return forum.save(on: req).transform(to: .noContent)
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
    /// - Returns: `UploadedImageData` containing the generated image identifier string.
    func imageHandler(_ req: Request, data: ImageUploadData) throws -> Future<PostData> {
        let user = try req.requireAuthenticated(User.self)
        // get post
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            guard try post.authorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "user cannot modify post")
            }
            // get like count
            return try PostLikes.query(on: req)
                .filter(\.postID == post.requireID())
                .count()
                .flatMap {
                    (count) in
                    // get generated filename
                    return try self.processImage(data: data.image, forType: .userProfile, on: req).flatMap {
                        (filename) in
                        // replace existing image
                        if !post.image.isEmpty {
                            // create ForumEdit record
                            let forumEdit = try ForumEdit(
                                postID: post.requireID(),
                                postContent: PostContentData(text: post.text, image: post.image)
                            )
                            // archive thumbnail
                            DispatchQueue.global(qos: .background).async {
                                self.archiveImage(post.image, from: self.imageDir)
                            }
                            return forumEdit.save(on: req).flatMap {
                                (_) in
                                // update post
                                post.image = filename
                                return post.save(on: req).map {
                                    (savedPost) in
                                    // return as PostData
                                    return try savedPost.convertToData(withLike: nil, likeCount: count)
                                }
                            }
                        }
                        // else add new image
                        post.image = filename
                        return post.save(on: req).map {
                            (savedPost) in
                            // return as PostData
                            return try savedPost.convertToData(withLike: nil, likeCount: count)
                        }

            }

            
            }
        }
    }
    
    /// `POST /api/v3/forum/post/ID/image/remove`
    ///
    /// Removes the image from a `ForumPost`, if there is one. A `ForumEdit` record is created
    /// if there was actually an image to remove.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have permission to modify the post.
    /// - Returns: `PostData` containing updated image name.
    func imageRemoveHandler(_ req: Request) throws -> Future<PostData> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            guard try post.authorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "user cannot modify post")
            }
            // get like count
            return try PostLikes.query(on: req)
                .filter(\.postID == post.requireID())
                .count()
                .flatMap {
                    (count) in
                    if !post.image.isEmpty {
                        // create ForumEdit record
                        let forumEdit = try ForumEdit(
                            postID: post.requireID(),
                            postContent: PostContentData(text: post.text, image: post.image)
                        )
                        // archive thumbnail
                        DispatchQueue.global(qos: .background).async {
                            self.archiveImage(post.image, from: self.imageDir)
                        }
                        return forumEdit.save(on: req).flatMap {
                            (_) in
                            // remove image filename from post
                            post.image = ""
                            return post.save(on: req).map {
                                (savedPost) in
                                // return as PostData
                                return try savedPost.convertToData(withLike: nil, likeCount: count)
                            }
                        }
                    }
                    // no existing image, return PostData
                    return req.future(try post.convertToData(withLike: nil, likeCount: count))
            }
        }
    }
    
    /// `GET /api/v3/forum/owner`
    /// `GET /api/v3/user/forums`
    ///
    /// Retrieve a list of all `Forum`s created by the user, sorted by title.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumListData]` containing all forums created by the user.
    func ownerHandler(_ req: Request) throws-> Future<[ForumListData]> {
        let user = try req.requireAuthenticated(User.self)
        return try user.forums.query(on: req)
            .sort(\.title, .ascending)
            .all()
            .flatMap {
                (forums) in
                // get forum metadata
                var forumCounts: [Future<Int>] = []
                var forumTimestamps: [Future<Date?>] = []
                for forum in forums {
                    forumCounts.append(try forum.posts.query(on: req).count())
                    forumTimestamps.append(try forum.posts.query(on: req)
                        .sort(\.createdAt, .descending)
                        .first()
                        .map {
                            (post) in
                            post?.createdAt
                        }
                    )
                }
                // resolve futures
                return forumCounts.flatten(on: req).flatMap {
                    (counts) in
                    return forumTimestamps.flatten(on: req).map {
                        (timestamps) in
                        // return as ForumListData
                        var returnListData: [ForumListData] = []
                        for (index, forum) in forums.enumerated() {
                            returnListData.append(
                                try ForumListData(
                                    forumID: forum.requireID(),
                                    title: forum.title,
                                    postCount: counts[index],
                                    lastPostAt: timestamps[index],
                                    isLocked: forum.isLocked
                                )
                            )
                        }
                        return returnListData
                    }
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
    func postCreateHandler(_ req: Request, data: PostCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // ensure user has write access
        guard user.accessLevel.rawValue >= UserAccessLevel.verified.rawValue else {
            throw Abort(.forbidden, reason: "user cannot post in forum")
        }
        // see `PostCreateData.validations()`
        try data.validate()
        // get forum
        return try req.parameters.next(Forum.self).flatMap {
            (forum) in
            guard !forum.isLocked else {
                throw Abort(.forbidden, reason: "forum is locked read-only")
            }
            // ensure user has access to forum
            return try self.getCachedFilters(for: user, on: req).flatMap {
                (tuple) in
                let blocked = tuple.0
                // user cannot retrieve block-owned forum, but prevent end-run
                guard !blocked.contains(forum.creatorID) else {
                    throw Abort(.forbidden, reason: "user cannot post in forum")
                }
                // process image
                return try self.processImage(data: data.imageData, forType: .forumPost, on: req).flatMap {
                    (filename) in
                    // create post
                    let forumPost = try ForumPost(
                        forumID: forum.requireID(),
                        authorID: user.requireID(),
                        text: data.text,
                        image: filename
                    )
                    return forumPost.save(on: req).map {
                        (savedPost) in
                        // return as PostData, with 201 status
                        let response = Response(http: HTTPResponse(status: .created), using: req)
                        try response.content.encode(try savedPost.convertToData(withLike: nil, likeCount: 0))
                        return response
                    }
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
    func postDeleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            guard try post.authorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "user is not permitted to delete post")
            }
            return post.delete(on: req).transform(to: .noContent)
        }
    }
    
    /// `POST /api/v3/forum/post/ID/report`
    ///
    /// Creates a `Report` regarding the specified `ForumPost`.
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
    func postReportHandler(_ req: Request, data: ReportData) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        let parent = try user.parentAccount(on: req)
        let forumPost = try req.parameters.next(ForumPost.self)
        return flatMap(parent, forumPost) {
            (parent, post) in
            return Report.query(on: req)
                .filter(\.reportedID == String(try post.requireID()))
                .filter(\.submitterID == (try parent.requireID()))
                .count()
                .flatMap {
                    (count) in
                    guard count == 0 else {
                        throw Abort(.conflict, reason: "user has already reported post")
                    }
                    let report = Report(
                        reportType: .forumPost,
                        reportedID: String(try post.requireID()),
                        submitterID: try parent.requireID(),
                        submitterMessage: data.message
                    )
                    return report.save(on: req).transform(to: .created)
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
    func postLaughHandler(_ req: Request) throws -> Future<PostData> {
        let user = try req.requireAuthenticated(User.self)
        // get post
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            guard try post.authorID != user.requireID() else {
                throw Abort(.forbidden, reason: "user cannot like own post")
            }
            // check for existing like
            return try PostLikes.query(on: req)
                .filter(\.userID == user.requireID())
                .filter(\.postID == post.requireID())
                .first()
                .flatMap {
                    (like) in
                    // re-type if existing like
                    if let like = like {
                        like.likeType = .laugh
                        return like.save(on: req).flatMap {
                            (savedLike) in
                            // get likes count
                            return try PostLikes.query(on: req)
                                .filter(\.postID == post.requireID())
                                .count()
                                .map {
                                    (count) in
                                    // return as PostData
                                    return try post.convertToData(withLike: .laugh, likeCount: count)
                            }
                        }
                    }
                    // otherwise create like
                    let postLike = try PostLikes(user, post, likeType: .laugh)
                    return postLike.save(on: req).flatMap {
                        (savedLike) in
                        // get likes count
                        return try PostLikes.query(on: req)
                            .filter(\.postID == post.requireID())
                            .count()
                            .map {
                                (count) in
                                // return as PostData
                                return try post.convertToData(withLike: .laugh, likeCount: count)
                        }
                    }
            }
        }
    }
    
    /// `POST /api/v3/forum/post/ID/like`
    ///
    /// Add a "like" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: `PostData` containing the updated like info.
    func postLikeHandler(_ req: Request) throws -> Future<PostData> {
        let user = try req.requireAuthenticated(User.self)
        // get post
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            guard try post.authorID != user.requireID() else {
                throw Abort(.forbidden, reason: "user cannot like own post")
            }
            // check for existing like
            return try PostLikes.query(on: req)
                .filter(\.userID == user.requireID())
                .filter(\.postID == post.requireID())
                .first()
                .flatMap {
                    (like) in
                    // re-type if existing like
                    if let like = like {
                        like.likeType = .like
                        return like.save(on: req).flatMap {
                            (savedLike) in
                            // get likes count
                            return try PostLikes.query(on: req)
                                .filter(\.postID == post.requireID())
                                .count()
                                .map {
                                    (count) in
                                    // return as PostData
                                    return try post.convertToData(withLike: .like, likeCount: count)
                            }
                        }
                    }
                    // otherwise create like
                    let postLike = try PostLikes(user, post, likeType: .like)
                    return postLike.save(on: req).flatMap {
                        (savedLike) in
                        // get likes count
                        return try PostLikes.query(on: req)
                            .filter(\.postID == post.requireID())
                            .count()
                            .map {
                                (count) in
                                // return as PostData
                                return try post.convertToData(withLike: .like, likeCount: count)
                        }
                    }
            }
        }
    }
    
    /// `POST /api/v3/forum/post/ID/love`
    ///
    /// Add a "love" reaction to the specified `ForumPost`. If there is an existing `LikeType`
    /// reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the post's creator.
    /// - Returns: `PostData` containing the updated like info.
    func postLoveHandler(_ req: Request) throws -> Future<PostData> {
        let user = try req.requireAuthenticated(User.self)
        // get post
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            guard try post.authorID != user.requireID() else {
                throw Abort(.forbidden, reason: "user cannot like own post")
            }
            // check for existing like
            return try PostLikes.query(on: req)
                .filter(\.userID == user.requireID())
                .filter(\.postID == post.requireID())
                .first()
                .flatMap {
                    (like) in
                    // re-type if existing like
                    if let like = like {
                        like.likeType = .love
                        return like.save(on: req).flatMap {
                            (savedLike) in
                            // get likes count
                            return try PostLikes.query(on: req)
                                .filter(\.postID == post.requireID())
                                .count()
                                .map {
                                    (count) in
                                    // return as PostData
                                    return try post.convertToData(withLike: .love, likeCount: count)
                            }
                        }
                    }
                    // otherwise create like
                    let postLike = try PostLikes(user, post, likeType: .love)
                    return postLike.save(on: req).flatMap {
                        (savedLike) in
                        // get likes count
                        return try PostLikes.query(on: req)
                            .filter(\.postID == post.requireID())
                            .count()
                            .map {
                                (count) in
                                // return as PostData
                                return try post.convertToData(withLike: .love, likeCount: count)
                        }
                    }
            }
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
    func postUnreactHandler(_ req: Request) throws -> Future<PostData> {
        let user = try req.requireAuthenticated(User.self)
        // get post
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            guard try post.authorID != user.requireID() else {
                throw Abort(.forbidden, reason: "user cannot like own post")
            }
            // check for existing like
            return try PostLikes.query(on: req)
                .filter(\.userID == user.requireID())
                .filter(\.postID == post.requireID())
                .first()
                .flatMap {
                    (like) in
                    guard like != nil else {
                        throw Abort(.badRequest, reason: "user does not have a reaction on the post")
                    }
                    // remove pivot
                    return post.likes.detach(user, on: req).flatMap {
                        (_) in
                        // get likes count
                        return try PostLikes.query(on: req)
                            .filter(\.postID == post.requireID())
                            .count()
                            .map {
                                (count) in
                                // return as PostData
                                return try post.convertToData(withLike: nil, likeCount: count)
                        }
                    }
            }
        }
    }

    /// `POST /api/v3/forum/post/ID/update`
    ///
    /// Update the specified`ForumPost`.
    ///
    /// - Note: This endpoint only changes the `.text` and `.image` *filename* of the post.
    ///   To change or remove the actual image asoociated with the post, use
    ///   `POST /api/v3/forum/post/ID/image` or `POST /api/v3/forum/post/ID/image/remove`.
    ///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostContentData` containing the post's text and image filename.
    /// - Throws: 403 error if user is not post owner or has read-only access.
    /// - Returns: `PostData` containing the post's contents and metadata.
    func postUpateHandler(_ req: Request, data: PostContentData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(ForumPost.self).flatMap {
            (post) in
            // ensure user has write access
            guard try post.authorID == user.requireID(),
                user.accessLevel.rawValue >= UserAccessLevel.verified.rawValue else {
                    throw Abort(.forbidden, reason: "user not permitted to edit post")
            }
            // get like count
            return try PostLikes.query(on: req)
                .filter(\.postID == post.requireID())
                .count()
                .flatMap {
                    (count) in
                    // see `PostCreateData.validations()`
                    try data.validate()
                    // stash current contents
                    let forumEdit = try ForumEdit(
                        postID: post.requireID(),
                        postContent: PostContentData(text: post.text, image: post.image)
                    )
                    // update if there are changes
                    if post.text != data.text || post.image != data.image {
                        post.text = data.text
                        post.image = data.image
                        return post.save(on: req).flatMap {
                            (savedPost) in
                            // save ForumEdit
                            return forumEdit.save(on: req).map {
                                (_) in
                                // return updated post as PostData, with 201 status
                                let response = Response(http: HTTPResponse(status: .created), using: req)
                                try response.content.encode(
                                    try savedPost.convertToData(withLike: nil, likeCount: count)
                                )
                                return response
                            }
                        }
                    } else {
                        // just return post as PostData, with 200 status
                        let response = Response(http: HTTPResponse(status: .ok), using: req)
                        try response.content.encode(
                            try post.convertToData(withLike: nil, likeCount: count)
                        )
                        return req.future(response)
                    }
            }
        }
    }
}
