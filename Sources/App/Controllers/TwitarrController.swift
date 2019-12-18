import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/twitarr/*` route endpoint and handler functions related
/// to the twit-arr stream.

struct TwitarrController: RouteCollection {
    // MARK: RouteCollection Conformance
    
    /// Required. Resisters routes to the incoming router.
    func boot(router: Router) throws {
        
        // convenience route group for all /api/v3/twitarr endpoints
        let twitarrRoutes = router.grouped("api", "v3", "twitarr")
        
        // instantiate authentication middleware
        let basicAuthMiddleware = User.basicAuthMiddleware(using: BCryptDigest())
        let guardAuthMiddleware = User.guardAuthMiddleware()
        let tokenAuthMiddleware = User.tokenAuthMiddleware()
        
        // set protected route groups
        let sharedAuthGroup = twitarrRoutes.grouped([basicAuthMiddleware, tokenAuthMiddleware, guardAuthMiddleware])
        let tokenAuthGroup = twitarrRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])
        
        // endpoints available whether logged in or not
        sharedAuthGroup.get(Twarrt.parameter, use: twarrtHandler)
        
        // endpoints only available when logged in
        tokenAuthGroup.post(Twarrt.parameter, "bookmark", use: bookmarkAddHandler)
        tokenAuthGroup.post(Twarrt.parameter, "bookmark", "remove", use: bookmarkRemoveHandler)
        tokenAuthGroup.get("bookmarks", use: bookmarksHandler)
        tokenAuthGroup.post(PostCreateData.self, at: "create", use: twarrtCreateHandler)
        tokenAuthGroup.post(Twarrt.parameter, "delete", use: twarrtDeleteHandler)
        tokenAuthGroup.post(ImageUploadData.self, at: Twarrt.parameter, "image", use: imageHandler)
        tokenAuthGroup.post(Twarrt.parameter, "image", "remove", use: imageRemoveHandler)
        tokenAuthGroup.post(Twarrt.parameter, "laugh", use: twarrtLaughHandler)
        tokenAuthGroup.post(Twarrt.parameter, "like", use: twarrtLikeHandler)
        tokenAuthGroup.get("likes", use: likesHandler)
        tokenAuthGroup.post(Twarrt.parameter, "love", use: twarrtLoveHandler)
        tokenAuthGroup.post(ReportData.self, at: Twarrt.parameter, "report", use: twarrtReportHandler)
        tokenAuthGroup.post(Twarrt.parameter, "unreact", use: twarrtUnreactHandler)
        tokenAuthGroup.post(PostContentData.self, at: Twarrt.parameter, "update", use: twarrtUpdateHandler)
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/twitarr/ID`
    ///
    /// Retrieve the specfied `Twarrt` with full user `LikeType` data.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the twarrt is not available.
    /// - Returns: `PostDetaildata` containing the specified twarrt.
    func twarrtHandler(_ req: Request) throws -> Future<PostDetailData> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrtParameter) in
            // we have twarrt, but need to filter
            return try self.getCachedFilters(for: user, on: req).flatMap {
                (tuple) in
                let blocked = tuple.0
                let muted = tuple.1
                let mutewords = tuple.2
                // NOW we can find (again!), using postgres to filter
                return try Twarrt.query(on: req)
                    .filter(\.id == twarrtParameter.requireID())
                    .filter(\.authorID !~ blocked)
                    .filter(\.authorID !~ muted)
                    .first()
                    .unwrap(or: Abort(.notFound, reason: "twarrt is not available"))
                    .flatMap {
                        (existingTwarrt) in
                        // remove mutewords
                        let filteredTwarrt = self.filterMutewords(for: existingTwarrt, using: mutewords, on: req)
                        guard let twarrt = filteredTwarrt else {
                            throw Abort(.notFound, reason: "twarrt is not available")
                        }
                        // get likes data
                        return try TwarrtLikes.query(on: req)
                            .filter(\.twarrtID == twarrt.requireID())
                            .all()
                            .flatMap {
                                (twarrtLikes) in
                                // get users
                                let likeUsers: [Future<User>] = twarrtLikes.map {
                                    (twarrtLike) -> Future<User> in
                                    return User.find(twarrtLike.userID, on: req)
                                        .unwrap(or: Abort(.internalServerError, reason: "user not found"))
                                }
                                return likeUsers.flatten(on: req).map {
                                    (users) in
                                    let seamonkeys = try users.map {
                                        try $0.convertToSeaMonkey()
                                    }
                                    // init return struct
                                    var twarrtDetailData = try PostDetailData(
                                        postID: twarrt.requireID(),
                                        createdAt: twarrt.createdAt ?? Date(),
                                        authorID: twarrt.authorID,
                                        text: twarrt.text,
                                        image: twarrt.image,
                                        laughs: [],
                                        likes: [],
                                        loves: []
                                    )
                                    // sort seamonkeys into like types
                                    for (index, like) in twarrtLikes.enumerated() {
                                        switch like.likeType {
                                            case .laugh:
                                                twarrtDetailData.laughs.append(seamonkeys[index])
                                            case .like:
                                                twarrtDetailData.likes.append(seamonkeys[index])
                                            case .love:
                                                twarrtDetailData.loves.append(seamonkeys[index])
                                            default: continue
                                        }
                                    }
                                    return twarrtDetailData
                                }
                        }
                }
            }
        }
    }
    
    // MARK: - tokenAuthGroup Handlers (logged in)
    // All handlers in this route group require a valid HTTP Bearer Authentication
    // header in the request.
    
    /// `POST /api/v3/twitarr/ID/bookmark`
    ///
    /// Add a bookmark of the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the twarrt is already bookmarked.
    /// - Returns: 201 Created on success.
    func bookmarkAddHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        // get twarrt
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            // get user's bookmarkedTwarrt barrel
            return try self.getBookmarkBarrel(for: user, on: req).flatMap {
                (bookmarkBarrel) in
                // create barrel if needed
                let barrel = try bookmarkBarrel ?? Barrel(
                    ownerID: user.requireID(),
                    barrelType: .bookmarkedTwarrt
                )
                // ensure bookmark doesn't exist
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                let twarrtID = String(try twarrt.requireID())
                guard !bookmarks.contains(twarrtID) else {
                    throw Abort(.badRequest, reason: "twarrt already bookmarked")
                }
                // add twarrt and return 201
                bookmarks.append(String(try twarrt.requireID()))
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel.save(on: req).transform(to: .created)
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/bookmark/remove`
    ///
    /// Remove a bookmark of the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the user has not bookmarked any twarrts.
    func bookmarkRemoveHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        // get twarrt
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            // get user's bookmarkedTwarrt barrel
            return try self.getBookmarkBarrel(for: user, on: req).flatMap {
                (barrel) in
                guard let barrel = barrel else {
                    throw Abort(.badRequest, reason: "user has not bookmarked any twarrts")
                }
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                // remove twarrt and return 204
                let twarrtID = String(try twarrt.requireID())
                if let index = bookmarks.firstIndex(of: twarrtID) {
                    bookmarks.remove(at: index)
                }
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel.save(on: req).transform(to: .noContent)
            }
        }
    }
    
    /// `GET /api/v3/twitarr/bookmarks`
    ///
    /// Retrieve all `Twarrt`s the user has bookmarked, sorted by creation timestamp.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all bookmarked posts.
    func bookmarksHandler(_ req: Request) throws -> Future<[TwarrtData]> {
        let user = try req.requireAuthenticated(User.self)
        // get bookmarkedTwarrt barrel
        return try self.getBookmarkBarrel(for: user, on: req).flatMap {
            (barrel) in
            let bookmarkStrings = barrel?.userInfo["bookmarks"] ?? []
            // convert to IDs
            let bookmarks = bookmarkStrings.compactMap { Int($0) }
            // filter blocks only
            let cache = try req.keyedCache(for: .redis)
            let key = try "blocks:\(user.requireID())"
            let cachedBlocks = cache.get(key, as: [UUID].self)
            return cachedBlocks.flatMap {
                (blocks) in
                let blocked = blocks ?? []
                // get twarrts
                return Twarrt.query(on: req)
                    .filter(\.id ~~ bookmarks)
                    .filter(\.authorID !~ blocked)
                    .sort(\.createdAt, .ascending)
                    .all()
                    .flatMap {
                        (twarrts) in
                        // convert to TwarrtData
                        let twarrtsData = try twarrts.map {
                            (twarrt) -> Future<TwarrtData> in
                            let userLike = try TwarrtLikes.query(on: req)
                                .filter(\.twarrtID == twarrt.requireID())
                                .filter(\.userID == user.requireID())
                                .first()
                            let likeCount = try TwarrtLikes.query(on: req)
                                .filter(\.twarrtID == twarrt.requireID())
                                .count()
                            return map(userLike, likeCount) {
                                (userLike, count) in
                                return try twarrt.convertToData(
                                    bookmarked: true,
                                    userLike: userLike?.likeType,
                                    likeCount: count
                                )
                            }
                        }
                        return twarrtsData.flatten(on: req)
                }
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/image`
    ///
    /// Sets the `Twarrt` image to the file uploaded in the HTTP body.
    ///
    /// - Requires: `ImageUploadData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ImageUploadData` containing the filename and image file.
    /// - Throws: 403 error if user does not have permission to modify the twarrt.
    /// - Returns: `TwarrtData` containing the updated image value.
    func imageHandler(_ req: Request, data: ImageUploadData) throws -> Future<TwarrtData> {
        let user = try req.requireAuthenticated(User.self)
        // get twarrt
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            guard try twarrt.authorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "user cannot modify twarrt")
            }
            // get like count
            return try TwarrtLikes.query(on: req)
                .filter(\.twarrtID == twarrt.requireID())
                .count()
                .flatMap {
                    (count) in
                    // get generated filename
                    return try self.processImage(data: data.image, forType: .twarrt, on: req).flatMap {
                        (filename) in
                        // replace existing image
                        if !twarrt.image.isEmpty {
                            // create TwarrtEdit record
                            let twarrtEdit = try TwarrtEdit(
                                twarrtID: twarrt.requireID(),
                                twarrtContent: PostContentData(text: twarrt.text, image: twarrt.image)
                            )
                            // archive thumbnail
                            DispatchQueue.global(qos: .background).async {
                                self.archiveImage(twarrt.image, from: self.imageDir)
                            }
                            return twarrtEdit.save(on: req).flatMap {
                                (_) in
                                // get isBookmarked state
                                return try self.isBookmarked(
                                    idValue: twarrt.requireID(),
                                    byUser: user,
                                    on: req
                                ).flatMap {
                                    (bookmarked) in
                                    // update twarrt
                                    twarrt.image = filename
                                    return twarrt.save(on: req).map {
                                        (savedTwarrt) in
                                        // return as TwartData
                                        return try savedTwarrt.convertToData(
                                            bookmarked: bookmarked,
                                            userLike: nil,
                                            likeCount: count
                                        )
                                    }
                                }
                            }
                        }
                        // else add new image
                        twarrt.image = filename
                        // get isBookmarked state
                        return try self.isBookmarked(
                            idValue: twarrt.requireID(),
                            byUser: user,
                            on: req
                        ).flatMap {
                            (bookmarked) in
                            return twarrt.save(on: req).map {
                                (savedTwarrt) in
                                // return as TwarrtData
                                return try savedTwarrt.convertToData(
                                    bookmarked: bookmarked,
                                    userLike: nil,
                                    likeCount: count
                                )
                            }
                        }
                    }
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/image/remove`
    ///
    /// Remove the image from a `Twarrt`, if there is one. A `TwarrtEdit` record is created
    /// if there was an image to remove.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user does not have permission to modify the twarrt.
    /// - Returns: `TwarrtData` containing the updated image name.
    func imageRemoveHandler(_ req: Request) throws -> Future<TwarrtData> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            guard try twarrt.authorID == user.requireID()
                || user.accessLevel.rawValue == UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "user cannot modify twarrt")
            }
            // get isBookmarked state
            return try self.isBookmarked(idValue: twarrt.requireID(), byUser: user, on: req).flatMap {
                (bookmarked) in
                // get like count
                return try TwarrtLikes.query(on: req)
                    .filter(\.twarrtID == twarrt.requireID())
                    .count()
                    .flatMap {
                        (count) in
                        if !twarrt.image.isEmpty {
                            // create TwarrtEdit record
                            let twarrtEdit = try TwarrtEdit(
                                twarrtID: twarrt.requireID(),
                                twarrtContent: PostContentData(text: twarrt.text, image: twarrt.image)
                            )
                            // archive thumbnail
                            DispatchQueue.global(qos: .background).async {
                                self.archiveImage(twarrt.image, from: self.imageDir)
                            }
                            return twarrtEdit.save(on: req).flatMap {
                                (_) in
                                // remove image filename from twarrt
                                twarrt.image = ""
                                return twarrt.save(on: req).map {
                                    (savedTwarrt) in
                                    // return as TwarrtData
                                    return try savedTwarrt.convertToData(
                                        bookmarked: bookmarked,
                                        userLike: nil,
                                        likeCount: count
                                    )
                                }
                            }
                        }
                        // no existing image, return TwarrtData
                        return req.future(
                            try twarrt.convertToData(
                                bookmarked: bookmarked,
                                userLike: nil,
                                likeCount: count
                            )
                        )
                }
            }
        }
    }
    
    /// `GET /api/v3/twitarr/likes`
    ///
    /// Retrieve all `Twarrt`s the user has liked.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all liked posts.
    func likesHandler(_ req: Request) throws -> Future<[TwarrtData]> {
        let user = try req.requireAuthenticated(User.self)
        // respect blocks
        let cache = try req.keyedCache(for: .redis)
        let key = try "blocks:\(user.requireID())"
        let cachedBlocks = cache.get(key, as: [UUID].self)
        return cachedBlocks.flatMap {
            (blocks) in
            let blocked = blocks ?? []
            // get liked twarrts
            return try user.twarrtLikes.query(on: req)
                .filter(\.authorID !~ blocked)
                .all()
                .flatMap {
                    (twarrts) in
                    // convert to TwarrtData
                    let twarrtsData = try twarrts.map {
                        (twarrt) -> Future<TwarrtData> in
                        let bookmarked = try self.isBookmarked(
                            idValue: twarrt.requireID(),
                            byUser: user,
                            on: req
                        )
                        let userLike = try TwarrtLikes.query(on: req)
                            .filter(\.twarrtID == twarrt.requireID())
                            .filter(\.userID == user.requireID())
                            .first()
                        let likeCount = try TwarrtLikes.query(on: req)
                            .filter(\.twarrtID == twarrt.requireID())
                            .count()
                        return map(bookmarked, userLike, likeCount) {
                            (bookmarked, userLike, count) in
                            return try twarrt.convertToData(
                                bookmarked: bookmarked,
                                userLike: userLike?.likeType,
                                likeCount: count
                            )
                        }
                    }
                    return twarrtsData.flatten(on: req)
            }
        }
    }
    
    /// `GET /api/v3/twitarr/mentions`
    ///
    /// Retrieve all `Twarrt`s whose content mentions the user, in descending timestamp order.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all twarrts containing mentions.
    func mentionsHandler(_ req: Request) throws -> Future<[TwarrtData]> {
        let user = try req.requireAuthenticated(User.self)
        // respect blocks
        let cache = try req.keyedCache(for: .redis)
        let key = try "blocks:\(user.requireID())"
        let cachedBlocks = cache.get(key, as: [UUID].self)
        return cachedBlocks.flatMap {
            (blocks) in
            let blocked = blocks ?? []
            // get mention twarrts
            return Twarrt.query(on: req)
                .filter(\.authorID !~ blocked)
                .filter(\.text, .ilike, "%@\(user.username) %")
                .sort(\.createdAt, .descending)
                .all()
                .flatMap {
                    (twarrts) in
                    // convert to TwarrtData
                    let twarrtsData = try twarrts.map {
                        (twarrt) -> Future<TwarrtData> in
                        let bookmarked = try self.isBookmarked(
                            idValue: twarrt.requireID(),
                            byUser: user,
                            on: req
                        )
                        let userLike = try TwarrtLikes.query(on: req)
                            .filter(\.twarrtID == twarrt.requireID())
                            .filter(\.userID == user.requireID())
                            .first()
                        let likeCount = try TwarrtLikes.query(on: req)
                            .filter(\.twarrtID == twarrt.requireID())
                            .count()
                        return map(bookmarked, userLike, likeCount) {
                            (bookmarked, userLike, count) in
                            return try twarrt.convertToData(
                                bookmarked: bookmarked,
                                userLike: userLike?.likeType,
                                likeCount: count
                            )
                        }
                    }
                    return twarrtsData.flatten(on: req)
            }
        }
    }
    
    /// `GET /api/v3/twitarr/twarrts`
    ///
    /// Retrieve all `Twarrt`s authored by the user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all twarrts containing mentions.
    func twarrtsHandler(_ req: Request) throws -> Future<[TwarrtData]> {
        let user = try req.requireAuthenticated(User.self)
        // get twarrts
        return try user.twarrts.query(on: req)
            .sort(\.createdAt, .ascending)
            .all()
            .flatMap {
                (twarrts) in
                // convert to TwarrtData
                let twarrtsData = try twarrts.map {
                    (twarrt) -> Future<TwarrtData> in
                    let bookmarked = try self.isBookmarked(
                        idValue: twarrt.requireID(),
                        byUser: user,
                        on: req
                    )
                    let likeCount = try TwarrtLikes.query(on: req)
                        .filter(\.twarrtID == twarrt.requireID())
                        .count()
                    return map(bookmarked, likeCount) {
                        (bookmarked, count) in
                        return try twarrt.convertToData(
                            bookmarked: bookmarked,
                            userLike: nil,
                            likeCount: count
                        )
                    }
                }
                return twarrtsData.flatten(on: req)
        }
    }
    
    /// `POST /api/v3/twitarr/create`
    ///
    /// Create a new `Twarrt` in the twitarr stream.
    ///
    /// - Requires: `PostCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostCreateData` containing the twarrt's text and optional image.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata.
    func twarrtCreateHandler(_ req: Request, data: PostCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // see `PostCreateData.validations()`
        try data.validate()
        // process image
        return try self.processImage(data: data.imageData, forType: .twarrt, on: req).flatMap {
            (filename) in
            // create twarrt
            let twarrt = try Twarrt(
                authorID: user.requireID(),
                text: data.text,
                image: filename
            )
            return twarrt.save(on: req).map {
                (savedTwarrt) in
                // return as TwarrtData with 201 status
                let response = Response(http: HTTPResponse(status: .created), using: req)
                try response.content.encode(
                    try savedTwarrt.convertToData(bookmarked: false, userLike: nil, likeCount: 0)
                )
                return response
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/delete`
    ///
    /// Delete the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No COntent on success.
    func twarrtDeleteHandler(_ req: Request) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            guard try twarrt.authorID == user.requireID()
                || user.accessLevel.rawValue >= UserAccessLevel.moderator.rawValue else {
                    throw Abort(.forbidden, reason: "user cannot delete twarrt")
            }
            return twarrt.delete(on: req).transform(to: .noContent)
        }
    }
    
    /// `POST /api/v3/twitarr/ID/report`
    ///
    /// Create a `Report` regarding the specified `Twarrt`.
    ///
    /// - Note: The accompanying report message is optional on the part of the submitting user,
    ///   but the `ReportData` is mandatory in order to allow one. If there is no message,
    ///   sent an empty string in the `.message` field.
    ///
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
    /// - Returns: 201 Created on success.
    func twarrtReportHandler(_ req: Request, data: ReportData) throws -> Future<HTTPStatus> {
        let user = try req.requireAuthenticated(User.self)
        let parent = try user.parentAccount(on: req)
        let twarrt = try req.parameters.next(Twarrt.self)
        return flatMap(parent, twarrt) {
            (parent, twarrt) in
            return try Report.query(on: req)
                .filter(\.reportedID == String(twarrt.requireID()))
                .filter(\.submitterID == parent.requireID())
                .count()
                .flatMap {
                    (count) in
                    guard count == 0 else {
                        throw Abort(.conflict, reason: "user has already reported twarrt")
                    }
                    let report = try Report(
                        reportType: .twarrt,
                        reportedID: String(twarrt.requireID()),
                        submitterID: parent.requireID(),
                        submitterMessage: data.message
                    )
                    return report.save(on: req).transform(to: .created)
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/laugh`
    ///
    /// Add a "laugh" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtLaughHandler(_ req: Request) throws -> Future<TwarrtData> {
        let user = try req.requireAuthenticated(User.self)
        // get twarrt
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            guard try twarrt.authorID != user.requireID() else {
                throw Abort(.forbidden, reason: "user cannot like own twarrt")
            }
            // get isBookmarked state
            return try self.isBookmarked(idValue: twarrt.requireID(), byUser: user, on: req).flatMap {
                (bookmarked) in
                // check for existing like
                return try TwarrtLikes.query(on: req)
                    .filter(\.userID == user.requireID())
                    .filter(\.twarrtID == twarrt.requireID())
                    .first()
                    .flatMap {
                        (like) in
                        // re-type if existing like
                        if let like = like {
                            like.likeType = .laugh
                            return like.save(on: req).flatMap {
                                (savedLike) in
                                // get likes count
                                return try TwarrtLikes.query(on: req)
                                    .filter(\.twarrtID == twarrt.requireID())
                                    .count()
                                    .map {
                                        (count) in
                                        // return as TwarrtData
                                        return try twarrt.convertToData(
                                            bookmarked: bookmarked,
                                            userLike: .laugh,
                                            likeCount: count
                                        )
                                }
                            }
                        }
                        // otherwise create laugh
                        let twarrtLike = try TwarrtLikes(user, twarrt, likeType: .laugh)
                        return twarrtLike.save(on: req).flatMap {
                            (savedLike) in
                            // get likes count
                            return try TwarrtLikes.query(on: req)
                                .filter(\.twarrtID == twarrt.requireID())
                                .count()
                                .map {
                                    (count) in
                                    // return as TwarrtData
                                    return try twarrt.convertToData(
                                        bookmarked: bookmarked,
                                        userLike: .laugh,
                                        likeCount: count)
                            }
                        }
                }
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/like`
    ///
    /// Add a "like" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtLikeHandler(_ req: Request) throws -> Future<TwarrtData> {
        let user = try req.requireAuthenticated(User.self)
        // get twarrt
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            guard try twarrt.authorID != user.requireID() else {
                throw Abort(.forbidden, reason: "user cannot like own twarrt")
            }
            // get isBookmarked state
            return try self.isBookmarked(idValue: twarrt.requireID(), byUser: user, on: req).flatMap {
                (bookmarked) in
                // check for existing like
                return try TwarrtLikes.query(on: req)
                    .filter(\.userID == user.requireID())
                    .filter(\.twarrtID == twarrt.requireID())
                    .first()
                    .flatMap {
                        (like) in
                        // re-type if existing like
                        if let like = like {
                            like.likeType = .like
                            return like.save(on: req).flatMap {
                                (savedLike) in
                                // get likes count
                                return try TwarrtLikes.query(on: req)
                                    .filter(\.twarrtID == twarrt.requireID())
                                    .count()
                                    .map {
                                        (count) in
                                        // return as TwarrtData
                                        return try twarrt.convertToData(
                                            bookmarked: bookmarked,
                                            userLike: .like,
                                            likeCount: count
                                        )
                                }
                            }
                        }
                        // otherwise create like
                        let twarrtLike = try TwarrtLikes(user, twarrt, likeType: .like)
                        return twarrtLike.save(on: req).flatMap {
                            (savedLike) in
                            // get likes count
                            return try TwarrtLikes.query(on: req)
                                .filter(\.twarrtID == twarrt.requireID())
                                .count()
                                .map {
                                    (count) in
                                    // return as TwarrtData
                                    return try twarrt.convertToData(
                                        bookmarked: bookmarked,
                                        userLike: .like,
                                        likeCount: count
                                    )
                            }
                        }
                }
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/love`
    ///
    /// Add a "love" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtLoveHandler(_ req: Request) throws -> Future<TwarrtData> {
        let user = try req.requireAuthenticated(User.self)
        // get twarrt
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            guard try twarrt.authorID != user.requireID() else {
                throw Abort(.forbidden, reason: "user cannot like own twarrt")
            }
            // get isBookmarked state
            return try self.isBookmarked(idValue: twarrt.requireID(), byUser: user, on: req).flatMap {
                (bookmarked) in
                // check for existing like
                return try TwarrtLikes.query(on: req)
                    .filter(\.userID == user.requireID())
                    .filter(\.twarrtID == twarrt.requireID())
                    .first()
                    .flatMap {
                        (like) in
                        // re-type if existing like
                        if let like = like {
                            like.likeType = .love
                            return like.save(on: req).flatMap {
                                (savedLike) in
                                // get likes count
                                return try TwarrtLikes.query(on: req)
                                    .filter(\.twarrtID == twarrt.requireID())
                                    .count()
                                    .map {
                                        (count) in
                                        // return as TwarrtData
                                        return try twarrt.convertToData(
                                            bookmarked: bookmarked,
                                            userLike: .love,
                                            likeCount: count
                                        )
                                }
                            }
                        }
                        // otherwise create love
                        let twarrtLike = try TwarrtLikes(user, twarrt, likeType: .love)
                        return twarrtLike.save(on: req).flatMap {
                            (savedLike) in
                            // get likes count
                            return try TwarrtLikes.query(on: req)
                                .filter(\.twarrtID == twarrt.requireID())
                                .count()
                                .map {
                                    (count) in
                                    // return as TwarrtData
                                    return try twarrt.convertToData(
                                        bookmarked: bookmarked,
                                        userLike: .love,
                                        likeCount: count
                                    )
                            }
                        }
                }
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/unreact`
    ///
    /// Remove a `LikeType` reaction from the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error it there was no existing reaction. 403 error if user is the twarrt's
    ///   creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtUnreactHandler(_ req: Request) throws -> Future<TwarrtData> {
        let user = try req.requireAuthenticated(User.self)
        // get twarrt
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            guard try twarrt.authorID != user.requireID() else {
                throw Abort(.forbidden, reason: "user cannot like own post")
            }
            // get isBookmarked state
            return try self.isBookmarked(idValue: twarrt.requireID(), byUser: user, on: req).flatMap {
                (bookmarked) in
                // check for existing like
                return try TwarrtLikes.query(on: req)
                    .filter(\.userID == user.requireID())
                    .filter(\.twarrtID == twarrt.requireID())
                    .first()
                    .flatMap {
                        (like) in
                        guard like != nil else {
                            throw Abort(.badRequest, reason: "user does not have a reaction on the twarrt")
                        }
                        // remove pivot
                        return twarrt.likes.detach(user, on: req).flatMap {
                            (_) in
                            // get likes count
                            return try TwarrtLikes.query(on: req)
                                .filter(\.twarrtID == twarrt.requireID())
                                .count()
                                .map {
                                    (count) in
                                    // return as TwarrtData
                                    return try twarrt.convertToData(
                                        bookmarked: bookmarked,
                                        userLike: nil,
                                        likeCount: count
                                    )
                            }
                        }
                }
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/update`
    ///
    /// Update the specified `Twarrt`.
    ///
    /// - Note: This endpoint only changes the `.text` and `.image` *filename* of the twarrt.
    ///   To change or remove the actual image associated with the twarrt, use
    ///   `POST /api/v3/twitarr/ID/image`  or `POST /api/v3/twitarr/ID/image/remove`.
    ///
    /// - Requires: `PostCOntentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostCOntentData` containing the twarrt's text and image filename.
    /// - Throws: 403 error if user is not post owner or has read-only access.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata.
    func twarrtUpdateHandler(_ req: Request, data: PostContentData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        return try req.parameters.next(Twarrt.self).flatMap {
            (twarrt) in
            // ensure user has write access
            guard try twarrt.authorID == user.requireID(),
                user.accessLevel.rawValue >= UserAccessLevel.verified.rawValue else {
                    throw Abort(.forbidden, reason: "user cannot modify twarrt")
            }
            // get isBookmarked state
            return try self.isBookmarked(idValue: twarrt.requireID(), byUser: user, on: req).flatMap {
                (bookmarked) in
                // get like count
                return try TwarrtLikes.query(on: req)
                    .filter(\.twarrtID == twarrt.requireID())
                    .count()
                    .flatMap {
                        (count) in
                        // see `PostCreateData.validation()`
                        try data.validate()
                        // stash current contents
                        let twarrtEdit = try TwarrtEdit(
                            twarrtID: twarrt.requireID(),
                            twarrtContent: PostContentData(text: twarrt.text, image: twarrt.image)
                        )
                        // update if there are changes
                        if twarrt.text != data.text || twarrt.image != data.image {
                            twarrt.text = data.text
                            twarrt.image = data.image
                            return twarrt.save(on: req).flatMap {
                                (savedTwarrt) in
                                // save TwarrtEdit
                                return twarrtEdit.save(on: req).map {
                                    (_) in
                                    // return updated twarrt as TwarrtData, with 201 status
                                    let response = Response(http: HTTPResponse(status: .created), using: req)
                                    try response.content.encode(
                                        try savedTwarrt.convertToData(
                                            bookmarked: bookmarked,
                                            userLike: nil,
                                            likeCount: count
                                        )
                                    )
                                    return response
                                }
                            }
                        } else {
                            // just return as TwarrtData, with 200 status
                            let response = Response(http: HTTPResponse(status: .ok), using: req)
                            try response.content.encode(
                                try twarrt.convertToData(
                                    bookmarked: bookmarked,
                                    userLike: nil,
                                    likeCount: count
                                )
                            )
                            return req.future(response)
                        }
                }
            }
        }
    }
}

// twarrts can be filtered by author and content
extension TwitarrController: ContentFilterable {}

// twarrts can contain images
extension TwitarrController: ImageHandler {
    /// The base directory for storing Twarrt images.
    var imageDir: String {
        return "images/twitarr/"
    }
    
    /// The height of Twarrt image thumbnails.
    var thumbnailHeight: Int {
        return 100
    }
}

// twarrts can be bookmarked
extension TwitarrController: UserBookmarkable {
    /// The barrel type for `Twarrt` bookmarking.
    var bookmarkBarrelType: BarrelType {
        return .bookmarkedTwarrt
    }
}
