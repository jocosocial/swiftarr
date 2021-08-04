import Vapor
import Crypto
import FluentSQL
import Fluent

/// The collection of `/api/v3/twitarr/*` route endpoint and handler functions related
/// to the twit-arr stream.

struct TwitarrController: RouteCollection {
    
	// Vapor uses ":pathParam" to declare a parameterized path element, and "pathParam" (no colon) to get 
	// the parameter value in route handlers. findFromParameter() has a variant that takes a PathComponent,
	// and it's slightly more type-safe to do this rather than relying on string matching.
	var twarrtIDParam = PathComponent(":twarrt_id")
    
// MARK: RouteCollection Conformance
	/// Required. Resisters routes to the incoming router.
	func boot(routes: RoutesBuilder) throws {
        
		// convenience route group for all /api/v3/twitarr endpoints
		let twitarrRoutes = routes.grouped("api", "v3", "twitarr")

		// instantiate authentication middleware
		let tokenAuthMiddleware = Token.authenticator()
		let guardAuthMiddleware = User.guardMiddleware()

		// set protected route groups
		let tokenAuthGroup = twitarrRoutes.grouped([tokenAuthMiddleware, guardAuthMiddleware])

		// endpoints only available when logged in
		tokenAuthGroup.get("", use: twarrtsHandler)
		tokenAuthGroup.get(twarrtIDParam, use: twarrtHandler)
		tokenAuthGroup.post(twarrtIDParam, "bookmark", use: bookmarkAddHandler)
		tokenAuthGroup.post(twarrtIDParam, "bookmark", "remove", use: bookmarkRemoveHandler)
		tokenAuthGroup.get("bookmarks", use: bookmarksHandler)
		tokenAuthGroup.post("create", use: twarrtCreateHandler)
		tokenAuthGroup.post(twarrtIDParam, "delete", use: twarrtDeleteHandler)
		tokenAuthGroup.delete(twarrtIDParam, use: twarrtDeleteHandler)
		tokenAuthGroup.post(twarrtIDParam, "laugh", use: twarrtLaughHandler)
		tokenAuthGroup.post(twarrtIDParam, "like", use: twarrtLikeHandler)
		tokenAuthGroup.post(twarrtIDParam, "love", use: twarrtLoveHandler)
		tokenAuthGroup.get("likes", use: likesHandler)
		tokenAuthGroup.post(twarrtIDParam, "reply", use: replyHandler)
		tokenAuthGroup.post(twarrtIDParam, "report", use: twarrtReportHandler)
		tokenAuthGroup.post(twarrtIDParam, "unreact", use: twarrtUnreactHandler)
		tokenAuthGroup.delete(twarrtIDParam, "laugh", use: twarrtUnreactHandler)
		tokenAuthGroup.delete(twarrtIDParam, "like", use: twarrtUnreactHandler)
		tokenAuthGroup.delete(twarrtIDParam, "love", use: twarrtUnreactHandler)
		tokenAuthGroup.post(twarrtIDParam, "update", use: twarrtUpdateHandler)
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
    /// - Returns: `TwarrtDetaildata` containing the specified twarrt.
    func twarrtHandler(_ req: Request) throws -> EventLoopFuture<TwarrtDetailData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
 		let cachedUser = try req.userCache.getUser(user)
        return Twarrt.findFromParameter(twarrtIDParam, on: req).addModelID().flatMap { (twarrt, twartID) in
            // we have twarrt, but need to filter
			if cachedUser.getBlocks().contains(twarrt.$author.id) || cachedUser.getMutes().contains(twarrt.$author.id) ||
					twarrt.containsMutewords(using: cachedUser.mutewords ?? []) {
				return req.eventLoop.makeFailedFuture(Abort(.notFound, reason: "twarrt is not available"))
			}
			return twarrt.$likes.$pivots.get(on: req.db).flatMap { twarrtLikes in
				return user.hasBookmarked(twarrt, on: req).flatMapThrowing { bookmarked in
						// get users
						let userUUIDs = twarrtLikes.map { $0.$user.id }
						let seamonkeys = req.userCache.getHeaders(userUUIDs).map { SeaMonkey(header: $0) }
						// init return struct
						guard let author = req.userCache.getUser(twarrt.$author.id)?.makeHeader() else {
							throw Abort(.internalServerError, reason: "Could not find author of twarrt.")
						}
						var twarrtDetailData = try TwarrtDetailData(
							postID: twarrt.requireID(),
							createdAt: twarrt.createdAt ?? Date(),
							author: author,
							text: twarrt.isQuarantined ? "This twarrt is under moderator review." : twarrt.text,
							images: twarrt.isQuarantined ? nil : twarrt.images,
							replyToID: twarrt.$replyTo.id,
							isBookmarked: bookmarked,
							userLike: nil,
							laughs: [],
							likes: [],
							loves: []
						)
						// sort seamonkeys into like types
						for (index, like) in twarrtLikes.enumerated() {
							if seamonkeys[index].userID == userID {
								twarrtDetailData.userLike = like.likeType
							}
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
    
    /// `GET /api/v3/twitarr`
    ///
    /// Retrieve an array of `Twarrt`s. This query supports several optional query parameters.
	/// 
	/// Parameters that filter the set of returned `Twarrt`s. These may be combined (but only one instance of each); 
	/// the result set will match all provided filters.
	/// * `?search=STRING` - Only return twarrts whose text contains the search string.
	/// * `?hashtag=STRING` - Only return twarrts whose text contains the given #hashtag. The # is not required in the  value.
	/// * `?mentions=STRING` - Only return twarrts that @mention the given username. The @ is not required in the value.
	/// * `?byuser=ID` - Only return twarrts authored by the given user.
	/// * `?inbarrel=ID` - Only return twarrts authored by any user in the given `.seamonkey` type `Barrel`.
    ///
	/// Parameters that set the anchor. The anchor can be a specific `Twarrt`, a `Date`, or the first or last twarrt in the stream.
	/// These parameters are mutually exclusive. The default anchor if none is specified is `?from=last`. 
	/// If you specify a twarrt ID as an anchor, that twarrt does not need to pass the filter params (see above).
    /// * `?after=ID` - the ID of the twarrt *after* which the retrieval should start (newer).
    /// * `?before=ID` - the ID of the twarrt *before* which the retrieval should start (older).
    /// * `?afterdate=DATE` - the timestamp *after* which the retrieval should start (newer).
    /// * `?beforedate=DATE` - the timestamp *before* which the retrieval should start (older).
    /// * `?from=STRING` - retrieve starting from "first" or "last".
	///
	/// These parameters operate on the filtered set of twarrts, starting at the anchor, above. These parameters can be used
	/// to implement paging that is invariant to new results being added while displaying filtered twarrts. That is, for an initial call
	/// with `?hashtag=joco&from=last`, on subsequent calls you can call `?hashtag=joco&before=<id of first result>&start=50`
	/// and you will get the 50 twarrts containing the #joco hashtag, occuring immediately before the 50 results returned in the first call--
	/// even if there have been more twarrts posted with the hashtag in the interim.
	/// * `?start=INT` - the offset from the anchor to start. Offset only counts twarrts that pass the filters.
    /// * `?limit=INT` - the maximum number of twarrts to retrieve: 1-200, default is 50
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
    func twarrtsHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
 		let cachedUser = try req.userCache.getUser(user)
        
		// Query builder always filters out blocks and mutes, and the range always applies.
        let start = (req.query[Int.self, at: "start"] ?? 0)
        let limit = (req.query[Int.self, at: "limit"] ?? 50).clamped(to: 0...Settings.shared.maximumTwarrts)
        var postFilterMentions: String? = nil
		let futureTwarrts = Twarrt.query(on: req.db)
				.filter(\.$author.$id !~ cachedUser.getBlocks())
				.filter(\.$author.$id !~ cachedUser.getMutes())
				.range(start..<(start + limit))
		
		// Process query params that set an anchor twarrt and search direction.
		var sortDescending = true
		if let afterID = req.query[Int.self, at: "after"] {
			futureTwarrts.filter(\.$id > afterID)
			sortDescending = false
		}
		else if let beforeID = req.query[Int.self, at: "before"]{
			futureTwarrts.filter(\.$id < beforeID)
		}
		else if let afterDate = req.query[String.self, at: "afterdate"] {
			guard let date = TwitarrController.dateFromParameter(string: afterDate) else {
				throw Abort(.badRequest, reason: "not a recognized date format")
			}
			futureTwarrts.filter(\.$createdAt > date)
			sortDescending = false
		}
		else if let beforeDate = req.query[String.self, at: "beforedate"] {
			guard let date = TwitarrController.dateFromParameter(string: beforeDate) else {
				throw Abort(.badRequest, reason: "not a recognized date format")
			}
			futureTwarrts.filter(\.$createdAt < date)
		}
		else if let from = req.query[String.self, at: "from"]?.lowercased(), from == "first" {
			sortDescending = false
		}
		
		// Process query params that filter for specific content.
		if let searchStr = req.query[String.self, at: "search"] {
			futureTwarrts.filter(\.$text, .custom("ILIKE"), "%\(searchStr)%")
		}
		if var hashtag = req.query[String.self, at: "hashtag"] {
			if !hashtag.hasPrefix("#") {
				hashtag = "#\(hashtag)"
			}
			futureTwarrts.filter(\.$text, .custom("ILIKE"), "%\(hashtag)%")
		}
		if var mentions = req.query[String.self, at: "mentions"] {
			if !mentions.hasPrefix("@") {
				mentions = "@\(mentions)"
			}
			postFilterMentions = mentions
			futureTwarrts.filter(\.$text, .custom("ILIKE"), "%\(mentions)%")
		}
		if let byuser = req.query[String.self, at: "byuser"] {
			guard let authorUUID = UUID(byuser) else {
				throw Abort(.badRequest, reason: "byuser parameter requires a valid UUID")
			}
			futureTwarrts.filter(\.$author.$id == authorUUID)
		}
		
		var barrelFinder: EventLoopFuture<Barrel?> = req.eventLoop.future(nil)
		if let inBarrel = req.query[String.self, at: "inbarrel"] {
			guard let barrelID = UUID(inBarrel) else {
				throw Abort(.badRequest, reason: "inbarrel parameter requires a valid barrel UUID")
			}
			barrelFinder = Barrel.find(barrelID, on: req.db).flatMapThrowing { (barrel) in
				guard let foundBarrel = barrel else {
					throw Abort(.badRequest, reason: "No barrel found with given barrel ID")
            	}
				// ensure .seamonkey type
				guard foundBarrel.barrelType == .seamonkey else {
					throw Abort(.badRequest, reason: "barrel is not a seamonkey barrel")
            	}
            	return barrel
			}
		}
		
		return barrelFinder.flatMap { barrel in
			if let foundBarrel = barrel {
				futureTwarrts.filter(\.$author.$id ~~ foundBarrel.modelUUIDs)
			}
			return futureTwarrts.sort(\.$id, sortDescending ? .descending : .ascending).all().flatMap { (twarrts) in
				// The filter() for mentions will include usernames that are prefixes for other usernames and other false positives.
				// This filters those out after the query. 
				var postFilteredTwarrts = twarrts
				if let postFilter = postFilterMentions {
					postFilteredTwarrts = twarrts.compactMap { $0.filterForMention(of: postFilter) }
				}
			
				// correct to descending order if necessary
				let sortedTwarrts: [Twarrt] = sortDescending ? postFilteredTwarrts : postFilteredTwarrts.reversed()
				return buildTwarrtData(from: sortedTwarrts, user: user, on: req, mutewords: cachedUser.mutewords)
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
    func bookmarkAddHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get twarrt
        return Twarrt.findFromParameter(twarrtIDParam, on: req).addModelID().flatMap {
            (twarrt, twarrtID) in
            // get user's bookmarkedTwarrt barrel
            return user.getBookmarkBarrel(of:.bookmarkedTwarrt, on: req).flatMap {
                (bookmarkBarrel) in
                // create barrel if needed
                let barrel = bookmarkBarrel ?? Barrel(ownerID: userID, barrelType: .bookmarkedTwarrt)
                // ensure bookmark doesn't exist
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                let twarrtIDStr = String(twarrtID)
                guard !bookmarks.contains(twarrtIDStr) else {
                    return req.eventLoop.makeFailedFuture(Abort(.badRequest, reason: "twarrt already bookmarked"))
                }
                // add twarrt and return 201
                bookmarks.append(twarrtIDStr)
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel.save(on: req.db).transform(to: .created)
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/bookmark/remove`
    ///
    /// Remove a bookmark of the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the user has not bookmarked any twarrts.
    func bookmarkRemoveHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        // get twarrt
        return Twarrt.findFromParameter(twarrtIDParam, on: req).addModelID().flatMap {
            (twarrt, twarrtID) in
            // get user's bookmarkedTwarrt barrel
            return user.getBookmarkBarrel(of:.bookmarkedTwarrt, on: req)
            	.unwrap(or: Abort(.badRequest, reason: "user has not bookmarked any twarrts"))
            	.flatMap { (barrel) in
                var bookmarks = barrel.userInfo["bookmarks"] ?? []
                // remove twarrt and return 204
                let twarrtID = String(twarrtID)
                if let index = bookmarks.firstIndex(of: twarrtID) {
                    bookmarks.remove(at: index)
                }
                barrel.userInfo["bookmarks"] = bookmarks
                return barrel.save(on: req.db).transform(to: .noContent)
            }
        }
    }
    
    /// `GET /api/v3/twitarr/bookmarks`
    ///
    /// Retrieve all `Twarrt`s the user has bookmarked.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all bookmarked posts.
    func bookmarksHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get bookmarkedTwarrt barrel
        return user.getBookmarkBarrel(of:.bookmarkedTwarrt, on: req).flatMap { (barrel) in
            let bookmarkStrings = barrel?.userInfo["bookmarks"] ?? []
            // convert to IDs
            let bookmarks = bookmarkStrings.compactMap { Int($0) }
            // filter blocks only
            let blocked = req.userCache.getBlocks(userID)
			// get twarrts
			return Twarrt.query(on: req.db)
				.filter(\.$id ~~ bookmarks)
				.filter(\.$author.$id !~ blocked)
				.sort(\.$id, .descending)
				.all()
				.flatMap { (twarrts) in
					return buildTwarrtData(from: twarrts, user: user, on: req, assumeBookmarked: true)
				}
		}
    }
        
    /// `GET /api/v3/twitarr/likes`
    ///
    /// Retrieve all `Twarrt`s the user has liked.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all liked posts.
    func likesHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        // respect blocks
        let blocked = try req.userCache.getBlocks(user)
		// get liked twarrts
		return user.$twarrtLikes.query(on: req.db)
			.filter(\.$author.$id !~ blocked)
			.all()
			.flatMap { (twarrts) in
				return buildTwarrtData(from: twarrts, user: user, on: req)
		}
    }
        
    /// `POST /api/v3/twitarr/ID/reply`
    ///
    /// Create a `Twarrt` as a reply to an existing twarrt. If the replyTo twarrt is in
    /// quarantine, the post is rejected.
    ///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    /// - Throws: 400 error if the replyTo twarrt is in quarantine.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata. HTTP 201 status if successful.
    func replyHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
		try user.guardCanCreateContent(customErrorString: "user cannot post twarrts")
		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
        // get replyTo twarrt
        return Twarrt.findFromParameter(twarrtIDParam, on: req).throwingFlatMap { (replyTo) in
			guard !replyTo.isQuarantined else {
				throw Abort(.badRequest, reason: "moderator-bot: twarrt cannot be replied to")
			}
			// process images
			return self.processImages(data.images, usage: .twarrt, on: req).throwingFlatMap { (filenames) in
				// create twarrt
				let twarrt = try Twarrt(author: user, text: data.text, images: filenames, replyTo: replyTo)
				return twarrt.save(on: req.db).flatMapThrowing { (savedTwarrt) in
					processTwarrtMentions(twarrt: twarrt, editedText: nil, isCreate: true, on: req)
					// return as TwarrtData with 201 status
					let authorHeader = try req.userCache.getHeader(twarrt.$author.id)
					let response = Response(status: .created)
					try response.content.encode(TwarrtData(twarrt: twarrt, creator: authorHeader, isBookmarked: false,
							userLike: nil, likeCount: 0))
					return response
				}
			}
        }
    }
        
    /// `POST /api/v3/twitarr/create`
    ///
    /// Create a new `Twarrt` in the twitarr stream.
    ///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata. HTTP 201 status if successful.
    func twarrtCreateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
		try user.guardCanCreateContent(customErrorString: "user cannot post twarrts")
 		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
        // process images
        return self.processImages(data.images, usage: .twarrt, on: req).throwingFlatMap { (filenames) in
            // create twarrt
			let twarrt = try Twarrt(author: user, text: data.text, images: filenames)
            return twarrt.save(on: req.db).flatMapThrowing { _ in
				processTwarrtMentions(twarrt: twarrt, editedText: nil, isCreate: true, on: req)
                // return as TwarrtData with 201 status
				let authorHeader = try req.userCache.getHeader(twarrt.$author.id)
                let response = Response(status: .created)
                try response.content.encode(TwarrtData(twarrt: twarrt, creator: authorHeader, isBookmarked: false,
						userLike: nil, likeCount: 0))
                return response
            }
        }
    }
    
    /// `POST /api/v3/twitarr/ID/delete`
	/// `DELETE /api/v3/twitarr/ID`
    ///
    /// Delete the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if the user is not permitted to delete.
    /// - Returns: 204 No Content on success.
    func twarrtDeleteHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        return Twarrt.findFromParameter(twarrtIDParam, on: req).throwingFlatMap { (twarrt) in
			try user.guardCanModifyContent(twarrt, customErrorString: "user cannot delete twarrt")
			processTwarrtMentions(twarrt: twarrt, editedText: nil, on: req)
			twarrt.logIfModeratorAction(.delete, user: user, on: req)
            return twarrt.delete(on: req.db).transform(to: .noContent)
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
    func twarrtReportHandler(_ req: Request) throws -> EventLoopFuture<HTTPStatus> {
        let user = try req.auth.require(User.self)
        let data = try req.content.decode(ReportData.self)
        return Twarrt.findFromParameter(twarrtIDParam, on: req).throwingFlatMap { twarrt in
        	return try twarrt.fileReport(submitter: user, submitterMessage: data.message, on: req)
		}
    }
    
    /// `POST /api/v3/twitarr/ID/laugh`
    ///
    /// Add a "laugh" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtLaughHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
    	return try twarrtReactHandler(req, likeType: .laugh)
    }
    
    /// `POST /api/v3/twitarr/ID/like`
    ///
    /// Add a "like" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
	func twarrtLikeHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
    	return try twarrtReactHandler(req, likeType: .like)
    }

    /// `POST /api/v3/twitarr/ID/love`
    ///
    /// Add a "love" reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtLoveHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
    	return try twarrtReactHandler(req, likeType: .love)
    }

    /// Add a  reaction to the specified `Twarrt`. If there is an existing `LikeType` reaction by the user, it is replaced.
	///  All 3 reaction handlers use this function as they all do the same thing.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
	/// - Parameter likeType: The type of reaction being set.
    /// - Throws: 403 error if user is the twarrt's creator.
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtReactHandler(_ req: Request, likeType: LikeType) throws -> EventLoopFuture<TwarrtData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get twarrt
        return Twarrt.findFromParameter(twarrtIDParam, on: req).addModelID().flatMap { (twarrt, twarrtID) in
            guard twarrt.$author.id != userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own twarrt"))
            }
			// check for existing like
			return TwarrtLikes.query(on: req.db)
				.filter(\.$user.$id == userID)
				.filter(\.$twarrt.$id == twarrtID)
				.first()
				.throwingFlatMap { (like) in
					let newLike = try like ?? TwarrtLikes(user, twarrt, likeType: .laugh)
					newLike.likeType = likeType
					return newLike.save(on: req.db) .flatMap { (_) in
						return buildTwarrtData(from: twarrt, user: user, on: req)
					}
            }
        }
    }
        
    /// `POST /api/v3/twitarr/ID/unreact`
    /// `DELETE /api/v3/twitarr/ID/reaction`
    ///
    /// Remove a `LikeType` reaction from the specified `Twarrt`.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Throws: 403 error if user is is the twarrt's creator. 404 if no twarrt with the ID is found. 
    /// - Returns: `TwarrtData` containing the updated like info.
    func twarrtUnreactHandler(_ req: Request) throws -> EventLoopFuture<TwarrtData> {
        let user = try req.auth.require(User.self)
        let userID = try user.requireID()
        // get twarrt
        return Twarrt.findFromParameter(twarrtIDParam, on: req).flatMap { twarrt in
            guard twarrt.$author.id != userID else {
                return req.eventLoop.makeFailedFuture(Abort(.forbidden, reason: "user cannot like own post"))
            }
			// remove pivot
			return twarrt.$likes.detach(user, on: req.db).flatMap { (_) in
				return buildTwarrtData(from: twarrt, user: user, on: req)
			}
        }
    }
    
    /// `POST /api/v3/twitarr/ID/update`
    ///
    /// Update the specified `Twarrt`.
	///
    /// - Requires: `PostContentData` payload in the HTTP body.
    /// - Parameters:
    ///   - req: The incoming `Request`, provided automatically.
    ///   - data: `PostContentData` containing the twarrt's text and image filename.
    /// - Throws: 403 error if user is not twarrt owner or has read-only access.
    /// - Returns: `TwarrtData` containing the twarrt's contents and metadata.
    func twarrtUpdateHandler(_ req: Request) throws -> EventLoopFuture<Response> {
        let user = try req.auth.require(User.self)
		let data = try ValidatingJSONDecoder().decode(PostContentData.self, fromBodyOf: req)
        return Twarrt.findFromParameter(twarrtIDParam, on: req).throwingFlatMap { (twarrt) in
			// I *think* the author should be allowed to edit a quarantined twarrt?
			// ensure user has write access
			try user.guardCanModifyContent(twarrt, customErrorString: "user cannot modify twarrt")
			return processImages(data.images, usage: .twarrt, on: req).map { filenames in
				return (twarrt, filenames)
			}
		}
		.throwingFlatMap { (twarrt: Twarrt, filenames: [String]) in
			// update if there are changes
			let normalizedText = data.text.replacingOccurrences(of: "\r\n", with: "\r")
			if twarrt.text != normalizedText || twarrt.images != filenames {
				processTwarrtMentions(twarrt: twarrt, editedText: normalizedText, on: req)
				// stash current twarrt contents before modifying
				let twarrtEdit = try TwarrtEdit(twarrt: twarrt, editor: user)
				twarrt.text = normalizedText
				twarrt.images = filenames
				return twarrt.save(on: req.db)
					.flatMap { twarrtEdit.save(on: req.db) }
					.transform(to: (twarrt, HTTPStatus.created))
			}
			return req.eventLoop.future((twarrt, HTTPStatus.ok))
		}
		.flatMap { (twarrt: Twarrt, status: HTTPStatus) in
			twarrt.logIfModeratorAction(.edit, user: user, on: req)
			return buildTwarrtData(from: twarrt, user: user, on: req).flatMapThrowing { (twarrtData) in
				// return updated twarrt as TwarrtData, with 201 status
				let response = Response(status: status)
				try response.content.encode(twarrtData)
				return response
			}
		}
    }
    
    /// `GET /api/v3/twitarr/user`
    ///
    /// Retrieve all `Twarrt`s authored by the user.
    ///
    /// - Parameter req: The incoming `Request`, provided automatically.
    /// - Returns: `[TwarrtData]` containing all twarrts containing mentions.
    func userHandler(_ req: Request) throws -> EventLoopFuture<[TwarrtData]> {
        let user = try req.auth.require(User.self)
        // get twarrts
        return user.$twarrts.query(on: req.db)
            .sort(\.$createdAt, .ascending)
            .all()
            .flatMap { (twarrts) in
                // convert to TwarrtData
				return buildTwarrtData(from: twarrts, user: user, on: req)
        	}
    }

}

// MARK: -
extension TwitarrController {
	// Builds a TwarrtData from a Twarrt. Somewhat stupidly, uses the array builder to do its work,
	// instead of the other way around.
	func buildTwarrtData(from twarrt: Twarrt, user: User, on req: Request) -> EventLoopFuture<TwarrtData> {
		return buildTwarrtData(from: [twarrt], user: user, on: req)
			.flatMapThrowing { (twarrtData: [TwarrtData]) in
				guard let result = twarrtData.first else {
					throw Abort(.internalServerError, reason: "Twarrt not found.")
				}
				return result
		}
	}

	// Builds an array of TwarrtDatas from an array of Twarrts.
	func buildTwarrtData(from twarrts: [Twarrt], user: User, on req: Request, 
			mutewords: [String]? = nil, assumeBookmarked: Bool? = nil, matchHashtag: String? = nil) -> EventLoopFuture<[TwarrtData]> {
		do {
			// remove muteword twarrts
			var filteredTwarrts = twarrts
			if let mutewords = mutewords {
				 filteredTwarrts = twarrts.compactMap { $0.filterOutStrings(using: mutewords) }
			}
			
			// get exact hashtag if we're matching on hashtag
			if let hashtag = matchHashtag {
				filteredTwarrts = filteredTwarrts.compactMap { (filteredTwarrt) -> Twarrt? in
					let text = filteredTwarrt.text.lowercased()
					let words = text.components(separatedBy: .whitespacesAndNewlines + .contentSeparators)
					return words.contains(hashtag) ? filteredTwarrt : nil
				}
			}

			// convert to an array TwarrtData futures
			let futures = try filteredTwarrts.map { (twarrt) -> EventLoopFuture<TwarrtData> in
      			let author = try req.userCache.getHeader(twarrt.$author.id)
				let bookmarked = assumeBookmarked == nil ? user.hasBookmarked(twarrt, on: req) :
						req.eventLoop.makeSucceededFuture(assumeBookmarked!)
				let userLike: EventLoopFuture<TwarrtLikes?>
				if try author.userID == user.requireID() {
					// A user cannot like their own content, ergo there's no userLike for a user's own twarrt.
					userLike = req.eventLoop.future(nil)
				}
				else {
					userLike = try TwarrtLikes.query(on: req.db)
						.filter(\.$twarrt.$id == twarrt.requireID())
						.filter(\.$user.$id == user.requireID())
						.first()
				}
				let likeCount = try TwarrtLikes.query(on: req.db)
					.filter(\.$twarrt.$id == twarrt.requireID())
					.count()
				return bookmarked.and(userLike).and(likeCount).flatMapThrowing { (arg0, count) in
					let (bookmarked, userLike) = arg0
					return try TwarrtData(twarrt: twarrt, creator: author, isBookmarked: bookmarked, 
							userLike: userLike?.likeType, likeCount: count)
				}
			}
			return futures.flatten(on: req.eventLoop)
		}
		catch {
			return req.eventLoop.makeFailedFuture(error)
		}
	}
	
	// Scans the text of twarrts as they are created/edited/deleted, finds @mentions, updates mention counts for
	// mentioned `User`s.
	@discardableResult func processTwarrtMentions(twarrt: Twarrt, editedText: String?, 
			isCreate: Bool = false, on req: Request) -> EventLoopFuture<Void> {	
		let (subtracts, adds) = twarrt.getMentionsDiffs(editedString: editedText, isCreate: isCreate)
		if subtracts.isEmpty && adds.isEmpty {
			return req.eventLoop.future()
		}
		return User.query(on: req.db).filter(\.$username ~~ subtracts).all().flatMap { subtractUsers in
			return User.query(on: req.db).filter(\.$username ~~ adds).all().flatMap { addUsers in
				var saveFutures = subtractUsers.map { (user: User) -> EventLoopFuture<Void> in
					user.twarrtMentions -= 1
					return user.save(on: req.db)
				}
				addUsers.forEach {
					$0.twarrtMentions += 1
					saveFutures.append($0.save(on: req.db))
				}
				return saveFutures.flatten(on: req.eventLoop)
			}
		}
	}
}

