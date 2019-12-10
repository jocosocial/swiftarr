import Vapor
import Crypto
import FluentSQL
import Fluent
import Redis

/// The collection of `/api/v3/forum/*` route endpoints and handler functions related
/// to forums.

struct ForumController: RouteCollection, ImageHandler {

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
        let basicAuthGroup = forumRoutes.grouped([basicAuthMiddleware, guardAuthMiddleware])
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
        
        // endpoints available only when logged in
        tokenAuthGroup.post(ForumCreateData.self, at: "categories", Category.parameter, "create", use: forumCreateHandler)
        tokenAuthGroup.post(PostCreateData.self, at: Forum.parameter, "create", use: postCreateHandler)
        tokenAuthGroup.post(Forum.parameter, "lock", use: forumLockHandler)
        tokenAuthGroup.post(Forum.parameter, "rename", String.parameter, use: forumRenameHandler)
        tokenAuthGroup.post(Forum.parameter, "unlock", use: forumUnlockHandler)
        tokenAuthGroup.get("owner", use: ownerHandler)
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
    /// Retrieve a `Forum` with all its `ForumPost`s. Content from blocked or muted users, or containing user's muteWords, is not returned.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the forum is not available.
    /// - Returns: `ForumData` containing the forum's metadata and all posts.
    func forumHandler(_ req: Request) throws -> Future<ForumData> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Forum.self).flatMap {
            (forum) in
            // 404 if block applies
            let cache = try req.keyedCache(for: .redis)
            let key = try "blocks:\(user.requireID())"
            let cachedBlocks = cache.get(key, as: [UUID].self)
            return cachedBlocks.flatMap {
                (blocks) in
                let blocked = blocks ?? []
                guard !blocked.contains(forum.creatorID) else {
                    throw Abort(.notFound, reason: "forum is unavailable")
                }
                
                // FIXME: need to handle w/mutes endpoint
                
                // remove blocks and mutes
                let mutesKey = try "mutes:\(user.requireID())"
                let cachedMutes = cache.get(mutesKey, as: [UUID].self)
                let muteWordsBarrel = try user.barrels.query(on: req)
                    .filter(\.barrelType == .keywordMute)
                    .first()
                return flatMap(cachedMutes, muteWordsBarrel) {
                    (mutes, barrel) in
                    let muted = mutes ?? []
                    let muteWords = barrel?.userInfo["muteWords"] ?? []
                    return try forum.posts.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .filter(\.text !~ muteWords)
                        .sort(\.createdAt, .ascending)
                        .all()
                        .map {
                            (posts) in
                            // return as ForumData
                            let forumData = try ForumData(
                                forumID: forum.requireID(),
                                title: forum.title,
                                creatorID: forum.creatorID,
                                isLocked: forum.isLocked,
                                posts: posts.map { try $0.convertToData() }
                            )
                            return forumData
                    }
                }
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
                            posts: [post.convertToData()]
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
    ///   - data: `PostCreateData` containg the post's text and optional image.
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
            let cache = try req.keyedCache(for: .redis)
            let key = try "blocks:\(user.requireID())"
            let cachedBlocks = cache.get(key, as: [UUID].self)
            return cachedBlocks.flatMap {
                (blocks) in
                let blocked = blocks ?? []
                guard !blocked.contains(forum.creatorID) else {
                    throw Abort(.forbidden, reason: "user cannot post in forum")
                }
                // process image
                return try self.processImage(data: data.image, forType: .forumPost, on: req).flatMap {
                    (imageName) in
                    // create post
                    let forumPost = try ForumPost(
                        forumID: forum.requireID(),
                        authorID: user.requireID(),
                        text: data.text,
                        image: imageName
                    )
                    return forumPost.save(on: req).map {
                        (savedPost) in
                        // return as PostData, with 201 status
                        let postData = try PostData(
                            postID: savedPost.requireID(),
                            createdAt: savedPost.createdAt ?? Date(),
                            authorID: try user.requireID(),
                            text: savedPost.text,
                            image: savedPost.image
                        )
                        let response = Response(http: HTTPResponse(status: .created), using: req)
                        try response.content.encode(postData)
                        return response
                    }
                }
            }
        }
    }
}
