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
        sharedAuthGroup.get("", use: twarrtsHandler)
        sharedAuthGroup.get(Twarrt.parameter, use: twarrtHandler)
        sharedAuthGroup.get("barrel", Barrel.parameter, use: twarrtsBarrelHandler)
        sharedAuthGroup.get("hashtag", String.parameter, use: twarrtsHashtagHandler)
        sharedAuthGroup.get("search", String.parameter, use: twarrtsSearchHandler)
        sharedAuthGroup.get("user", User.parameter, use: twarrtsUserHandler)
        
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
        tokenAuthGroup.get("mentions", use: mentionsHandler)
        tokenAuthGroup.post(Twarrt.parameter, "love", use: twarrtLoveHandler)
        tokenAuthGroup.post(PostCreateData.self, at: Twarrt.parameter, "reply", use: replyHandler)
        tokenAuthGroup.post(ReportData.self, at: Twarrt.parameter, "report", use: twarrtReportHandler)
        tokenAuthGroup.post(Twarrt.parameter, "unreact", use: twarrtUnreactHandler)
        tokenAuthGroup.post(PostContentData.self, at: Twarrt.parameter, "update", use: twarrtUpdateHandler)
        tokenAuthGroup.get("user", use: userHandler)
    }
    
    // MARK: - sharedAuthGroup Handlers (logged in or not)
    // All handlers in this route group require a valid HTTP Basic Authorization
    // *or* HTTP Bearer Authorization header in the request.
    
    /// `GET /api/v3/twitarr/barrel/ID`
    ///
    /// Retrieve all `Twarrt`s posted by users in the specified `.seamonkey` type `Barrel`.
    ///
    /// - Note: The barrel does not need to be owned by the requesting user, though all blocks
    ///   and mutes of the requesting user are applied regardless.
    ///
    /// - Requires: A specified `Barrel` of `BarrelType.seamonkey`.
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the barrel is not a barrel of seamonkeys.
    /// - Returns: `[TwarrtData]` containing all twarrts posted by the barrel seamonkeys.
    func twarrtsBarrelHandler(_ req: Request) throws -> Future<[TwarrtData]> {
        let user = try req.requireAuthenticated(User.self)
        // get seamonkey barrel
        return try req.parameters.next(Barrel.self).flatMap {
            (barrel) in
            // ensure .seamonkey type
            guard barrel.barrelType == .seamonkey else {
                throw Abort(.badRequest, reason: "barrel is not a seamonkey barrel")
            }
            // get filters
            return try self.getCachedFilters(for: user, on: req).flatMap {
                (tuple) in
                let blocked = tuple.0
                let muted = tuple.1
                let mutewords = tuple.2
                // get twarrts
                return Twarrt.query(on: req)
                    .filter(\.authorID ~~ barrel.modelUUIDs)
                    .filter(\.authorID !~ blocked)
                    .filter(\.authorID !~ muted)
                    .sort(\.createdAt, .descending)
                    .all()
                    .flatMap {
                        (twarrts) in
                        // filter mutewords
                        let filteredTwarrts = twarrts.compactMap {
                            self.filterMutewords(for: $0, using: mutewords, on: req)
                        }
                        // convert to TwarrtData
                        let twarrtsData = try filteredTwarrts.map {
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
    
    /// `GET /api/v3/twitarr/ID`
    ///
    /// Retrieve the specfied `Twarrt` with full user `LikeType` data.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 404 error if the twarrt is not available.
    /// - Returns: `TwarrtDetaildata` containing the specified twarrt.
    func twarrtHandler(_ req: Request) throws -> Future<TwarrtDetailData> {
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
                        let filteredTwarrt = self.filterMutewords(
                            for: existingTwarrt,
                            using: mutewords,
                            on: req
                        )
                        guard let twarrt = filteredTwarrt else {
                            throw Abort(.notFound, reason: "twarrt is not available")
                        }
                        return try self.isBookmarked(idValue: twarrt.requireID(), byUser: user, on: req).flatMap {
                            (bookmarked) in
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
                                        var twarrtDetailData = try TwarrtDetailData(
                                            postID: twarrt.requireID(),
                                            createdAt: twarrt.createdAt ?? Date(),
                                            authorID: twarrt.authorID,
                                            text: twarrt.isQuarantined ?
                                                "This twarrt is under moderator review." : twarrt.text,
                                            image: twarrt.image,
                                            replyToID: twarrt.replyToID,
                                            isBookmarked: bookmarked,
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
    }
    
    /// `GET /api/v3/twitarr`
    ///
    /// Retrieve an array of `Twarrt`s. This query supports several optional query parameters.
    ///
    /// * `?limit=INT` - the maximum number of twarrts to retrieve: 1-200, default is 50
    /// * `?after=ID` - the ID of the twarrt *after* which the retrieval should start (newer)
    /// * `?before=ID` - the ID of the twarrt *before* which the retrieval should start (older)
    /// * `?afterdate=DATE` - the timestamp *after* which the retrieval should start (newer)
    /// * `?beforedate=DATE` - the timestamp *before* which the retrieval should start (older)
    /// * `?from=STRING` - retrieve starting from "first" or "last"
    ///
    /// - Important: All parameters other than `limit` are **mutually exclusive**. If
    ///   additional conflicting parameters are sent, the first one listed in the order above
    ///   takes precedence (probably).
    ///
    /// A query without additional parameters defaults to `?limit=50&from=last`, the 50 most
    /// recent twarrts.
    ///
    /// `DATE` values can be either `TimeInterval` values (Doubles) since epoch, or ISO8601
    /// string representations including milliseconds ("yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"). The
    /// numeric value method is recommended.
    ///
    /// - Note: It is *highly* recommended that clients use `after=ID` or `before=ID` where
    ///   possible. `Twarrt` ID's are Int values and thus unambiguous. `DATE` values are
    ///   accurate only within 1 millisecond and are therefore prone to rounding errors. To
    ///   ensure that all twarrts of interest are returned when sending a date based on the
    ///   value found in a twarrt's timestamp, it is recommended that 1 millisecond be added
    ///   (if retrieving older) or subtracted (if retrieving newer) from that value for the
    ///   query. You will almost certainly receive the original anchor twarrt again, but it will
    ///   also ensure that any others possibly created within the same millisecond will not be
    ///   omitted.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if a date parameter was supplied and is in an unknown format.
    /// - Returns: `[TwarrtData]` containing the requested twarrts.
    func twarrtsHandler(_ req: Request) throws -> Future<[TwarrtData]> {
        let user = try req.requireAuthenticated(User.self)
        // get query parameters
        var limit = req.query[Int.self, at: "limit"] ?? 50
        let afterID = req.query[Int.self, at: "after"]
        let beforeID = req.query[Int.self, at: "before"]
        let afterDate = req.query[String.self, at: "afterdate"]
        let beforeDate = req.query[String.self, at: "beforedate"]
        let from = req.query[String.self, at: "from"]?.lowercased() ?? "last"
        // enforce maximum allowed
        if limit > Settings.shared.maximumTwarrts {
            limit = Settings.shared.maximumTwarrts
        }
        // get cached blocks
        return try self.getCachedFilters(for: user, on: req).flatMap {
            (tuple) in
            let blocked = tuple.0
            let muted = tuple.1
            let mutewords = tuple.2
            // get twarrts
            var futureTwarrts: Future<[Twarrt]>
            switch (afterID, beforeID, afterDate, beforeDate, from) {
                case (.some(let twarrtID), _, _, _, _):
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .filter(\.id > twarrtID)
                        .sort(\.id, .ascending)
                        .range(..<limit)
                        .all()
                case (_, .some(let twarrtID), _, _, _):
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .filter(\.id < twarrtID)
                        .sort(\.id, .descending)
                        .range(..<limit)
                        .all()
                case (_, _, .some(let twarrtDate), _, _):
                    guard let date = TwitarrController.dateFromParameter(string: twarrtDate) else {
                        throw Abort(.badRequest, reason: "not a recognized date format")
                    }
                    print(date.timeIntervalSince1970)
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .filter(\.createdAt > date)
                        .sort(\.createdAt, .ascending)
                        .range(..<limit)
                        .all()
                case (_, _, _, .some(let twarrtDate), _):
                    guard let date = TwitarrController.dateFromParameter(string: twarrtDate) else {
                        throw Abort(.badRequest, reason: "not a recognized date format")
                    }
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .filter(\.createdAt < date)
                        .sort(\.createdAt, .descending)
                        .range(..<limit)
                        .all()
                case (_, _, _, _, "first"):
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .sort(\.id, .ascending)
                        .range(..<limit)
                        .all()
                default:
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.authorID !~ muted)
                        .sort(\.id, .descending)
                        .range(..<limit)
                        .all()
            }
            return futureTwarrts.flatMap {
                (twarrts) in
                // correct to descending order
                var sortedTwarrts: [Twarrt]
                switch (afterID, beforeID, afterDate, beforeDate, from) {
                    case (.some(afterID), _, _, _, _):
                        sortedTwarrts = twarrts.reversed()
                    case (_, .some(beforeID), _, _, _):
                        sortedTwarrts = twarrts
                    case (_, _, .some(afterDate), _, _):
                        sortedTwarrts = twarrts.reversed()
                    case (_, _, _, .some(beforeDate), _):
                        sortedTwarrts = twarrts
                    case (_, _, _, _, "first"):
                        sortedTwarrts = twarrts.reversed()
                    default:
                        sortedTwarrts = twarrts
                }
                // remove muteword twarrts
                let filteredTwarrts = sortedTwarrts.compactMap {
                    self.filterMutewords(for: $0, using: mutewords, on: req)
                }
                // convert to TwarrtData
                let twarrtsData = try filteredTwarrts.map {
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
    
    /// `GET /api/v3/twitarr/hashtag/#STRING`
    ///
    /// Retrieve all `Twarrt`s that contain the exact specified hashtag.
    ///
    /// - Note: By "exact" we mean the string cannot be a substring of another hashtag (there
    ///   must be a preceeding space), but the match is not case-sensitive. For example, `#joco`
    ///   will not match `#joco2020` or `#joco#2020`, but will match `#JoCo`. Use the more
    ///   generic `GET /api/v3/twitarr/search/STRING` endpoint with the same `#joco` parameter
    ///   if you want that type of substring matching behavior.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the specified string is not a hashtag.
    /// - Returns: `[TwarrtData]` containing all matching twarrts.
    func twarrtsHashtagHandler(_ req: Request) throws -> Future<[TwarrtData]> {
        let user = try req.requireAuthenticated(User.self)
        var hashtag = try req.parameters.next(String.self)
        // ensure it's a hashtag
        guard hashtag.hasPrefix("#") else {
            throw Abort(.badRequest, reason: "hashtag parameter must start with '#'")
        }
        // postgres "_" and "%" are wildcards, so escape for literals
        hashtag = hashtag.replacingOccurrences(of: "_", with: "\\_")
        hashtag = hashtag.replacingOccurrences(of: "%", with: "\\%")
        hashtag = hashtag.trimmingCharacters(in: .whitespacesAndNewlines)
        // get cached blocks
        return try self.getCachedFilters(for: user, on: req).flatMap {
            (tuple) in
            let blocked = tuple.0
            let muted = tuple.1
            let mutewords = tuple.2
            // get twarrts
            return Twarrt.query(on: req)
                .filter(\.authorID !~ blocked)
                .filter(\.authorID !~ muted)
                .filter(\.text, .ilike, "%\(hashtag)%")
                .sort(\.id, .descending)
                .all()
                .flatMap {
                    (twarrts) in
                    // remove muteword twarrts
                    let filteredTwarrts = twarrts.compactMap {
                        self.filterMutewords(for: $0, using: mutewords, on: req)
                    }
                    // get exact hashtag
                    let matches = filteredTwarrts.compactMap {
                        (filteredTwarrt) -> Twarrt? in
                        let text = filteredTwarrt.text.lowercased()
                        let words = text.components(separatedBy: .whitespacesAndNewlines + .contentSeparators)
                        return words.contains(hashtag) ? filteredTwarrt : nil
                    }
                    // convert to TwarrtData
                    let twarrtsData = try matches.map {
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
    
    /// `GET /api/v3/twitarr/search/STRING`
    ///
    /// Retrieve all `Twarrt`s that contain the specified string.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all matching twarrts.
    func twarrtsSearchHandler(_ req: Request) throws -> Future<[TwarrtData]> {
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
            // get twarrts
            return Twarrt.query(on: req)
                .filter(\.authorID !~ blocked)
                .filter(\.authorID !~ muted)
                .filter(\.text, .ilike, "%\(search)%")
                .sort(\.id, .descending)
                .all()
                .flatMap {
                    (twarrts) in
                    // remove muteword twarrts
                    let filteredTwarrts = twarrts.compactMap {
                        self.filterMutewords(for: $0, using: mutewords, on: req)
                    }
                    // convert to TwarrtData
                    let twarrtsData = try filteredTwarrts.map {
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
    
    /// `GET /api/v3/twitarr/user/ID`
    ///
    /// Retrieve all `Twarrt`s posted by the specified `User`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all specified user's twarrts.
    func twarrtsUserHandler(_ req: Request) throws -> Future<[TwarrtData]> {
        let requester = try req.requireAuthenticated(User.self)
        return try req.parameters.next(User.self).flatMap {
            (user) in
            // get cached blocks
            return try self.getCachedFilters(for: requester, on: req).flatMap {
                (tuple) in
                let blocked = tuple.0
                let muted = tuple.1
                let mutewords = tuple.2
                // get twarrts
                return try Twarrt.query(on: req)
                    .filter(\.authorID !~ blocked)
                    .filter(\.authorID !~ muted)
                    .filter(\.authorID == user.requireID())
                    .sort(\.id, .descending)
                    .all()
                    .flatMap {
                        (twarrts) in
                        // remove muteword twarrts
                        let filteredTwarrts = twarrts.compactMap {
                            self.filterMutewords(for: $0, using: mutewords, on: req)
                        }
                        // convert to TwarrtData
                        let twarrtsData = try filteredTwarrts.map {
                            (twarrt) -> Future<TwarrtData> in
                            let bookmarked = try self.isBookmarked(
                                idValue: twarrt.requireID(),
                                byUser: requester,
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
    /// Retrieve all `Twarrt`s the user has bookmarked.
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
                    .sort(\.id, .descending)
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
        // get query parameters
        let afterID = req.query[Int.self, at: "after"]
        let afterDate = req.query[String.self, at: "afterdate"]
        // respect blocks
        let cache = try req.keyedCache(for: .redis)
        let key = try "blocks:\(user.requireID())"
        let cachedBlocks = cache.get(key, as: [UUID].self)
        return cachedBlocks.flatMap {
            (blocks) in
            let blocked = blocks ?? []
            // get mention twarrts
            var futureTwarrts: Future<[Twarrt]>
            switch (afterID, afterDate) {
                case (.some(let twarrtID), _):
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.text, .ilike, "%@\(user.username)%")
                        .filter(\.id > twarrtID)
                        .sort(\.id, .descending)
                        .all()
                case (_, .some(let twarrtDate)):
                    guard let date = TwitarrController.dateFromParameter(string: twarrtDate) else {
                        throw Abort(.badRequest, reason: "not a recognized date format")
                    }
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.text, .ilike, "%@\(user.username)%")
                        .filter(\.createdAt > date)
                        .sort(\.createdAt, .descending)
                        .all()
                default:
                    futureTwarrts = Twarrt.query(on: req)
                        .filter(\.authorID !~ blocked)
                        .filter(\.text, .ilike, "%@\(user.username)%")
                        .sort(\.createdAt, .descending)
                        .all()
            }
            return futureTwarrts.flatMap {
                (twarrts) in
                // get exact username
                let matches = twarrts.compactMap {
                    (twarrt) -> Twarrt? in
                    let text = twarrt.text.lowercased()
                    let words = text.components(separatedBy: .whitespacesAndNewlines + .contentSeparators)
                    return words.contains("@\(user.username)") ? twarrt : nil
                }
                    // convert to TwarrtData
                    let twarrtsData = try matches.map {
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
    
    /// `POST /api/v3/twitarr/ID/reply`
    ///
    /// Create a `Twarrt` as a reply to an existing twarrt. If the replyTo twarrt is in
    /// quarantine, the post is rejected.
    ///
    /// - Requires: `PostCreateData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostCreateData` containing the twarrt's text and optional image.
    /// - Throws: 400 error if the replyTo twarrt is in quarantine.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata.
    func replyHandler(_ req: Request, data: PostCreateData) throws -> Future<Response> {
        let user = try req.requireAuthenticated(User.self)
        // get replyTo twarrt
        return try req.parameters.next(Twarrt.self).flatMap {
            (replyTo) in
            guard !replyTo.isQuarantined else {
                throw Abort(.badRequest, reason: "moderator-bot: twarrt cannot be replied to")
            }
            // see `PostCreateData.validations()`
            try data.validate()
            // process image
            return try self.processImage(data: data.imageData, forType: .twarrt, on: req).flatMap {
                (filename) in
                // create twarrt
                let twarrt = try Twarrt(
                    authorID: user.requireID(),
                    text: data.text,
                    image: filename,
                    replyToID: replyTo.requireID()
                )
                return twarrt.save(on: req).map {
                    (savedTwarrt) in
                    // return as TwarrtData with 201 status
                    let response = Response(http: HTTPResponse(status: .created), using: req)
                    try response.content.encode(
                    try savedTwarrt.convertToData(bookmarked: false, userLike: nil, likeCount: 0))
                    return response
                }
            }
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
    /// Create a `Report` regarding the specified `Twarrt`. If the twarrt has reached the report
    /// threshold for auto-quarantining, it is quarantined.
    ///
    /// - Note: The accompanying report message is optional on the part of the submitting user,
    ///   but the `ReportData` is mandatory in order to allow one. If there is no message,
    ///   sent an empty string in the `.message` field.
    ///
    /// - Requires: `ReportData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `ReportData` containing an optional accompanying message.
    /// - Throws: 400 error if user has already submitted report.
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
                        throw Abort(.badRequest, reason: "user has already reported twarrt")
                    }
                    let report = try Report(
                        reportType: .twarrt,
                        reportedID: String(twarrt.requireID()),
                        submitterID: parent.requireID(),
                        submitterMessage: data.message
                    )
                    return report.save(on: req).flatMap {
                        (_) in
                        // quarantine if threshold is met
                        return try Report.query(on: req)
                            .filter(\.reportedID == String(twarrt.requireID()))
                            .count()
                            .flatMap {
                                (reportCount) in
                                if reportCount >= Settings.shared.postAutoQuarantineThreshold
                                    && !twarrt.isReviewed {
                                    twarrt.isQuarantined = true
                                    return twarrt.save(on: req).transform(to: .created)
                                }
                                return req.future(.created)
                        }
                    }
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
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostContentData` containing the twarrt's text and image filename.
    /// - Throws: 403 error if user is not twarrt owner or has read-only access.
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
    
    /// `GET /api/v3/twitarr/user`
    ///
    /// Retrieve all `Twarrt`s authored by the user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all twarrts containing mentions.
    func userHandler(_ req: Request) throws -> Future<[TwarrtData]> {
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
