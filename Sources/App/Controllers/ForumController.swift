import Vapor
import Crypto
import FluentSQL
import Fluent
import Redis

/// The collection of `/api/v3/forum/*` route endpoints and handler functions related
/// to forums.

struct ForumController: RouteCollection {
    
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
        sharedAuthGroup.get("categories", use: categoriesHandler)
        sharedAuthGroup.get("categories", "admin", use: categoriesAdminHandler)
        sharedAuthGroup.get("categories", "user", use: categoriesUserHandler)
        sharedAuthGroup.get("categories", Category.parameter, use: categoryForumsHandler)
        
        // endpoints available only when logged in
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
    /// Retrieve a list of all forums in the specifiec `Category`, sorted by title. If the
    /// forum is user-created and a user block applies, the forum will not be returned.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the category ID is not valid.
    /// - Returns: `[ForumData]` containing all category forums.
    func categoryForumsHandler(_ req: Request) throws -> Future<[ForumData]> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Category.self).flatMap {
            (category) in
            if category.isRestricted {
                // don't sort admin categories
                return try Forum.query(on: req)
                    .filter(\.categoryID == category.requireID())
                    .all()
                    .map {
                        (forums) in
                        // return as ForumData
                        return try forums.map {
                            try ForumData(forumID: $0.requireID(), title: $0.title)
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
                        .map {
                            (forums) in
                            // return as ForumData
                            return try forums.map {
                                try ForumData(forumID: $0.requireID(), title: $0.title)
                            }
                    }
                }
            }
        }
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `GET /api/v3/forum/owner`
    /// `GET /api/v3/user/forums`
    ///
    /// Retrieve a list of all `Forum`s created by the user, sorted by title.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[ForumData]` containing all forums created by the user.
    func ownerHandler(_ req: Request) throws-> Future<[ForumData]> {
        let user = try req.requireAuthenticated(User.self)
        return try user.forums.query(on: req)
            .sort(\.title, .ascending)
            .all()
            .map {
                (forums) in
                // return as ForumData
                return try forums.map {
                    try ForumData(forumID: $0.requireID(), title: $0.title)
                }
        }
    }
}
